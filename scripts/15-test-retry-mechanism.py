#!/usr/bin/env python3
"""
Retry-mechanism load test
=========================
Verifies that retrying HTTP 5xx errors up to 3 times (as configured in
networking/virtual-service-reviews-timeout-3s.yaml) significantly improves
the success rate of requests to the reviews service.

TWO MODES
---------
Mock mode (default — no cluster required):
    A lightweight local HTTP server is started; it returns HTTP 500 for a
    configurable fraction of requests (default 40 %).  Two phases are run:
      Phase 1 – No retry:   each of N logical requests is attempted once.
      Phase 2 – With retry: each logical request is retried up to 3 times on
                            5xx, mirroring the Istio VirtualService retries block.
    The theoretical gain at 40 % fault rate:
      without retry : 60.0 % success
      with retry    : 93.6 % success  (1 − 0.4^3)

Cluster mode (--url URL):
    Pass the URL that exposes the reviews (or productpage) endpoint, e.g.:
        http://localhost:31080/api/v1/products/0/reviews
    Apply a fault-injection VirtualService first so there are 5xx errors to
    retry against:
        kubectl -n bookinfo apply -f networking/virtual-service-ratings-test-abort.yaml
    Phase 1 hits the URL without any client-side retry.
    Phase 2 adds up to 3 client-side retries on 5xx, mirroring Istio behaviour.

USAGE
-----
    # self-contained demo (no cluster needed)
    python scripts/15-test-retry-mechanism.py

    # higher fault rate, more requests
    python scripts/15-test-retry-mechanism.py --fault-rate 0.5 --requests 1000

    # against a running cluster with fault injection already applied
    python scripts/15-test-retry-mechanism.py \\
        --url http://localhost:31080/api/v1/products/0/reviews

EXIT CODE
---------
    0  success-rate improved by at least --min-improvement (default 20 pp)
    1  improvement fell short of the threshold
"""

import argparse
import concurrent.futures
import http.server
import random
import sys
import threading
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field


# ---------------------------------------------------------------------------
# Mock HTTP server — injects random HTTP 500 faults
# ---------------------------------------------------------------------------

def _make_fault_handler(fault_rate):
    """Returns an HTTPServer handler class that returns 500 at `fault_rate` probability."""

    class _FaultHandler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if random.random() < fault_rate:
                body = b'{"error": "simulated 5xx fault"}'
                self.send_response(500)
            else:
                body = b'{"reviews": [{"reviewer": "Alice", "text": "Excellent read!"}]}'
                self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *_):
            pass  # silence per-request logs

    return _FaultHandler


def start_mock_server(fault_rate):
    """Start the mock server in a daemon thread. Returns (url, server)."""
    server = http.server.HTTPServer(("127.0.0.1", 0), _make_fault_handler(fault_rate))
    port = server.server_address[1]
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return f"http://127.0.0.1:{port}/reviews", server


# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------

def fetch_once(url, timeout):
    """Single HTTP GET. Returns status code, or -1 on network/timeout error."""
    try:
        with urllib.request.urlopen(url, timeout=timeout) as resp:
            return resp.status
    except urllib.error.HTTPError as exc:
        return exc.code
    except Exception:
        return -1


def fetch_with_retry(url, max_attempts, per_try_timeout):
    """
    Retries on 5xx up to `max_attempts` times — mirrors the Istio retries block:
        attempts:      3
        perTryTimeout: 2s
        retryOn:       5xx

    Returns (final_status_code, number_of_attempts_used).
    """
    status = -1
    for attempt in range(1, max_attempts + 1):
        status = fetch_once(url, per_try_timeout)
        if not (500 <= status <= 599):
            return status, attempt
    return status, max_attempts  # all attempts exhausted, still failing


# ---------------------------------------------------------------------------
# Phase runner
# ---------------------------------------------------------------------------

@dataclass
class PhaseResult:
    name: str
    total: int
    status_counts: dict = field(default_factory=dict)
    total_attempts: int = 0

    @property
    def successes(self):
        return sum(v for k, v in self.status_counts.items() if 200 <= k <= 299)

    @property
    def client_errors(self):
        return sum(v for k, v in self.status_counts.items() if 400 <= k <= 499)

    @property
    def server_errors(self):
        return sum(v for k, v in self.status_counts.items() if 500 <= k <= 599)

    @property
    def connection_errors(self):
        return self.status_counts.get(-1, 0)

    @property
    def success_rate(self):
        return self.successes / self.total if self.total else 0.0

    @property
    def avg_attempts(self):
        return self.total_attempts / self.total if self.total else 1.0


def run_phase(name, url, total_requests, workers, use_retry, max_attempts, per_try_timeout):
    result = PhaseResult(name=name, total=total_requests)
    lock = threading.Lock()

    def _send_one(_):
        if use_retry:
            status, attempts = fetch_with_retry(url, max_attempts, per_try_timeout)
        else:
            status = fetch_once(url, per_try_timeout)
            attempts = 1
        with lock:
            result.status_counts[status] = result.status_counts.get(status, 0) + 1
            result.total_attempts += attempts

    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        list(pool.map(_send_one, range(total_requests)))

    return result


# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

_SEP = "-" * 62
_SEP_HEAVY = "=" * 62


def _print_phase(r):
    print(f"\n{_SEP_HEAVY}")
    print(f"  Phase: {r.name}")
    print(_SEP_HEAVY)
    print(f"  Total logical requests : {r.total:>6}")
    print(f"  Successes  (2xx)       : {r.successes:>6}  ({r.success_rate * 100:.1f} %)")
    print(f"  Server errors (5xx)    : {r.server_errors:>6}")
    print(f"  Client errors (4xx)    : {r.client_errors:>6}")
    print(f"  Connection errors      : {r.connection_errors:>6}")
    print(f"  Avg HTTP attempts/req  : {r.avg_attempts:>6.2f}")
    print(f"  {_SEP}")
    print(f"  Status code breakdown:")
    for code in sorted(r.status_counts):
        label = "(connection/timeout)" if code == -1 else ""
        print(f"    HTTP {code if code != -1 else '---':>3} : "
              f"{r.status_counts[code]:>6} requests  {label}")


def _print_comparison(baseline, retried, min_improvement):
    delta = retried.success_rate - baseline.success_rate
    passed = delta >= min_improvement

    print(f"\n{_SEP_HEAVY}")
    print("  COMPARISON SUMMARY")
    print(_SEP_HEAVY)
    print(f"  Without retry  ->  {baseline.success_rate * 100:>6.1f} % success rate")
    print(f"  With retry     ->  {retried.success_rate * 100:>6.1f} % success rate")
    print(f"  Improvement    ->  +{delta * 100:.1f} percentage points")
    print(f"  Required       ->  +{min_improvement * 100:.1f} percentage points")
    print(_SEP)
    if passed:
        print("  RESULT: PASS")
        print("  The retry mechanism significantly improved the success rate.")
    else:
        print("  RESULT: FAIL")
        print("  Improvement did not meet the required threshold.")
    print(_SEP_HEAVY)
    return passed


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _build_parser():
    p = argparse.ArgumentParser(
        description="Verify that retrying HTTP 5xx errors improves the success rate.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    p.add_argument(
        "--url",
        default=None,
        metavar="URL",
        help="Target URL to test (default: start a local mock server)",
    )
    p.add_argument(
        "--fault-rate",
        type=float,
        default=0.40,
        metavar="RATE",
        help="Fraction of mock-server responses returned as HTTP 500 (default: 0.40)",
    )
    p.add_argument(
        "--requests",
        type=int,
        default=500,
        help="Logical requests per phase (default: 500)",
    )
    p.add_argument(
        "--workers",
        type=int,
        default=20,
        help="Concurrent request workers (default: 20)",
    )
    p.add_argument(
        "--retry-attempts",
        type=int,
        default=3,
        help="Max retries per logical request on 5xx "
             "(default: 3 — matches VirtualService config)",
    )
    p.add_argument(
        "--per-try-timeout",
        type=float,
        default=2.0,
        metavar="SECS",
        help="Per-attempt timeout in seconds "
             "(default: 2.0 — matches VirtualService config)",
    )
    p.add_argument(
        "--min-improvement",
        type=float,
        default=0.20,
        metavar="RATE",
        help="Minimum required success-rate improvement (0-1) to pass the test "
             "(default: 0.20 = 20 percentage points)",
    )
    return p


def main():
    args = _build_parser().parse_args()
    use_mock = args.url is None
    server = None

    print(_SEP_HEAVY)
    print("  Istio Retry Mechanism — Load Test")
    print(_SEP_HEAVY)

    if use_mock:
        print(f"\nMode          : mock server  (fault rate: {args.fault_rate * 100:.0f} %)")
        url, server = start_mock_server(args.fault_rate)
        time.sleep(0.05)  # let the socket become ready
        print(f"Mock server   : {url}")
    else:
        print(f"\nMode          : cluster endpoint")
        print(f"URL           : {args.url}")
        url = args.url

    print(f"\nTest parameters")
    print(f"  Requests per phase  : {args.requests}")
    print(f"  Concurrent workers  : {args.workers}")
    print(f"  Retry attempts      : {args.retry_attempts}  (retryOn: 5xx)")
    print(f"  Per-try timeout     : {args.per_try_timeout} s")

    if use_mock:
        p_no_retry = 1 - args.fault_rate
        p_with_retry = 1 - (args.fault_rate ** args.retry_attempts)
        print(f"\nTheoretical expectations (independent i.i.d. faults)")
        print(f"  Without retry : ~{p_no_retry * 100:.1f} % success  "
              f"(each request has {args.fault_rate * 100:.0f} % chance of 500)")
        print(f"  With retry    : ~{p_with_retry * 100:.1f} % success  "
              f"(all {args.retry_attempts} attempts fail with p = "
              f"{args.fault_rate:.2f}^{args.retry_attempts} = "
              f"{args.fault_rate ** args.retry_attempts:.4f})")

    # ── Phase 1: no retry ────────────────────────────────────────────────────
    print(f"\nRunning Phase 1 — no retry ({args.requests} requests) ...")
    t0 = time.monotonic()
    phase1 = run_phase(
        name="No Retry (baseline)",
        url=url,
        total_requests=args.requests,
        workers=args.workers,
        use_retry=False,
        max_attempts=1,
        per_try_timeout=args.per_try_timeout,
    )
    elapsed1 = time.monotonic() - t0
    _print_phase(phase1)
    print(f"  Elapsed: {elapsed1:.1f} s  "
          f"({args.requests / elapsed1:.0f} req/s)")

    # ── Phase 2: with retry ──────────────────────────────────────────────────
    print(f"\nRunning Phase 2 — with retry "
          f"({args.retry_attempts} attempts on 5xx, {args.requests} requests) ...")
    t0 = time.monotonic()
    phase2 = run_phase(
        name=f"With Retry  ({args.retry_attempts} attempts, "
             f"perTryTimeout={args.per_try_timeout} s, retryOn=5xx)",
        url=url,
        total_requests=args.requests,
        workers=args.workers,
        use_retry=True,
        max_attempts=args.retry_attempts,
        per_try_timeout=args.per_try_timeout,
    )
    elapsed2 = time.monotonic() - t0
    _print_phase(phase2)
    print(f"  Elapsed: {elapsed2:.1f} s  "
          f"({args.requests / elapsed2:.0f} req/s)")

    # ── Final verdict ────────────────────────────────────────────────────────
    passed = _print_comparison(phase1, phase2, args.min_improvement)

    if server:
        server.shutdown()

    sys.exit(0 if passed else 1)


if __name__ == "__main__":
    main()

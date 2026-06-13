# Bookinfo on local Kubernetes (kind) with Istio service mesh

Phase 2 of the project: get the Istio Bookinfo sample app running on a local
Kubernetes cluster created with [kind](https://kind.sigs.k8s.io/), with the
Istio service mesh installed and configured. This includes installing the Istio control plane
(istiod) and enabling sidecar injection for the Bookinfo namespace.

## What this gives you

- A single-node kind cluster named `bookinfo`.
- Istio control plane (istiod) installed with demo profile and ingress gateway enabled.
- The 6 Bookinfo workloads deployed in a `bookinfo` namespace with Istio sidecar
  injection enabled: `productpage-v1`, `details-v1`, `ratings-v1`, `reviews-v1`,
  `reviews-v2`, `reviews-v3`.
- The `productpage` frontend exposed through the Istio ingress gateway at
  <http://localhost:31080/productpage>.
- An Istio `Gateway` and `VirtualService` that route external traffic to `productpage`.
- An automated smoke test that verifies the page actually renders data coming
  from the `details` and `reviews` services, and that Istio is properly installed.
- Prometheus + Grafana for metrics, with a Bookinfo dashboard.
- Jaeger + Kiali for tracing and topology (100% sampling in `bookinfo`).
- A traffic generator that starts automatically when the project runs.

## Prerequisites

| Tool | Version used |
| ------- | ------------ |
| Docker | 29.x (Docker Desktop on Windows; daemon must be running) |
| kind | 0.31.0 |
| kubectl | 1.34.x |
| istioctl | 1.22.x (Istio CLI installed locally) |
| bash | Git Bash, WSL, or any POSIX-ish shell |
| curl | for the validation script |

All must be on `PATH`. Run `docker info` once to make sure the daemon is
reachable.

## Files added in this phase

```text
bookinfo/
├── demo-profile-no-gateways.yaml        # Istio operator config (ingress gateway enabled)
├── kind-config.yaml                     # kind cluster definition + port mappings
├── docs/
│   └── BookinfoKindIstioSetup.md        # (this file)
└── scripts/
  ├── 01-create-cluster.sh             # creates the kind cluster
  ├── 02-install-istio.sh              # installs Istio control plane using local istioctl
  ├── 03-deploy-bookinfo.sh            # applies manifests + enables sidecar injection + applies gateway
  ├── 04-port-forward.sh               # alternative exposure via kubectl port-forward
  ├── 05-validate.sh                   # smoke test against productpage + Istio validation
  ├── 06-install-metrics.sh            # installs Prometheus + Grafana + Bookinfo dashboard
  ├── 07-install-tracing.sh            # installs Jaeger + Kiali + Telemetry
  ├── 08-start-load-generator.sh       # starts the traffic generator in background
  ├── 09-stop-load-generator.sh        # stops the traffic generator
  ├── 99-cleanup.sh                    # deletes the kind cluster
  ├── run-all.sh                       # 01 -> 02 -> 03 -> 05 -> 06 -> 07 -> 08
  └── productpage-nodeport-31080.yaml  # Optional NodePort override (fallback)
```

The upstream Istio sample manifests under `platform/kube/` are **not modified**.
The optional NodePort override lives in `scripts/` for fallback use, but the
default path is through the Istio ingress gateway.

## How `kind-config.yaml` is set up

Single control-plane node with three host port mappings:

| Container port | Host port | Used for |
| --- | --- | --- |
| 31080 | 31080 | Istio ingress gateway NodePort (HTTP) |
| 80 | 8080 | reserved for an ingress controller (future) |
| 443 | 8443 | reserved for an ingress controller (future) |

## Quick start (TL;DR)

From the project root run:

```bash
bash scripts/run-all.sh
```

This runs the full project, including ingress routing, metrics, tracing, and the traffic generator.

Open the app:

- <http://localhost:31080/productpage>

Expose the UIs (run each in its own terminal; keep them running):

```bash
kubectl -n istio-system port-forward svc/grafana 3000:3000
kubectl -n kiali port-forward svc/kiali 20001:20001
kubectl -n jaeger port-forward svc/tracing 16686:80
```

Open the tools:

- Grafana: <http://localhost:3000>
- Kiali: <http://localhost:20001/kiali>
- Jaeger: <http://localhost:16686/jaeger>

To stop the traffic generator:

```bash
bash scripts/09-stop-load-generator.sh
```

To tear everything down:

```bash
bash scripts/99-cleanup.sh
```

## Step-by-step

If you prefer to run each phase manually:

### 1. Create the cluster

```bash
bash scripts/01-create-cluster.sh
```

What it does:

- Verifies `docker`, `kind`, `kubectl` are on PATH and the Docker daemon is up.
- Skips creation if a kind cluster named `bookinfo` already exists.
- Otherwise runs `kind create cluster --name bookinfo --config kind-config.yaml`.
- Switches kubectl to context `kind-bookinfo` and prints node info.

Expected: a `bookinfo-control-plane` node appears (it shows `NotReady` for a
few seconds while CNI initializes — that's normal).

### 2. Install Istio

```bash
bash scripts/02-install-istio.sh
```

What it does:

- Verifies `kubectl`, `istioctl` are on PATH.
- Installs Istio control plane using the demo profile with ingress gateway enabled.
- Waits for `istiod` deployment to be ready.

Expected: Istio components running in `istio-system` namespace.

### 3. Deploy Bookinfo

```bash
bash scripts/03-deploy-bookinfo.sh
```

What it does:

- Creates the `bookinfo` namespace if it doesn't exist.
- Labels the namespace for Istio sidecar injection.
- Applies all Bookinfo manifests from `platform/kube/bookinfo.yaml`.
- Applies the Istio `Gateway` and `VirtualService` for Bookinfo.
- Waits for all deployments to be Available.

Expected: 6 pods running in `bookinfo` namespace, each with an Istio sidecar (2/2 Ready).

### 4. Validate

```bash
bash scripts/05-validate.sh
```

What it does:

- Checks that Istio control plane is installed and ready.
- `curl`s <http://localhost:31080/productpage> and asserts HTTP 200.
- Greps the response for the productpage HTML title, the "Book Details" section
  (proves the `details` service was reached), and the "Book Reviews" section
  (proves a `reviews` pod was reached). Reviews itself calls `ratings`, so any
  non-v1 reviews variant exercises that hop too.

If all three checks pass, the local deployment is healthy. Open the URL in a
browser and refresh several times — you should see the reviews section cycle
between the v1 (no stars), v2 (black stars), and v3 (red stars) variants because
Kubernetes load-balances across the three `reviews` Deployments round-robin via
the `reviews` Service.

Expected: "Bookinfo is reachable and rendering all upstream services."

### 5. Configure reviews routing

```bash
# canary routing
kubectl -n bookinfo apply -f networking/virtual-service-canary.yaml

# header-based routing
kubectl -n bookinfo apply -f networking/combined-virtual-service.yaml
```

What it does:

- `networking/virtual-service-canary.yaml` routes `reviews` traffic through the
  canary configuration and is used by the `canary` routing mode.
- `networking/combined-virtual-service.yaml` enables header-based routing so
  requests with `end-user: jason` are sent to the targeted version of
  `reviews`.

If you want to verify routing behavior manually after applying one of the
VirtualServices, use:

```bash
bash scripts/10-verify-canary.sh
bash scripts/11-test-header-routing.sh
```

### 6. Fault injection — 7-second latency on `ratings` for a test user

This step injects an artificial 7-second delay into the `ratings` service
scoped only to requests that carry the header `end-user: jason`, so all other
users continue to see normal response times.

#### Prerequisites

Steps 1–4 must be complete and the DestinationRules must be applied:

```bash
kubectl apply -f networking/destination-rule-all.yaml -n bookinfo
```

#### Apply the fault

Route user `jason` to `reviews-v2` (the only variant that calls `ratings`),
then inject the delay:

```bash
kubectl apply -f networking/virtual-service-reviews-test-v2.yaml -n bookinfo
kubectl apply -f networking/virtual-service-ratings-test-delay.yaml -n bookinfo
```

Confirm both VirtualServices are active:

```bash
kubectl get virtualservices -n bookinfo
```

Expected output includes entries for `ratings` and `reviews`.

#### Test as Jason

1. Open <http://localhost:31080/productpage> (or <http://localhost:9080/productpage> if using port-forward).
2. Click **Sign in** and log in as `jason` (password: `jason`).
3. Observe a **~7-second pause** before the reviews section renders — this is the injected delay propagating from `ratings` through `reviews-v2` to `productpage`.
4. Log out and reload the page as an anonymous user — the page should load instantly with no delay.

#### Verify via `curl`

```bash
# With the delay (jason) — takes ~7 s
curl -s -o /dev/null -w "%{time_total}s\n" \
  -H "end-user: jason" \
  http://localhost:31080/productpage

# Without the delay (anonymous) — returns quickly
curl -s -o /dev/null -w "%{time_total}s\n" \
  http://localhost:31080/productpage
```

#### Automated test

`scripts/13-test-latency-fault.sh` automates the checks above: it confirms
the `ratings` VirtualService has the 7s fault delay, then sends one request
as an anonymous user (expects a fast response with reviews rendered) and one
as `jason` (expects a ~6s response — the 7s `ratings` delay trips
productpage's hardcoded 3s timeout with one retry — showing "Sorry, product
reviews are currently unavailable for this book.").

```bash
bash scripts/13-test-latency-fault.sh
```

#### Observe in Grafana / Prometheus

Port-forward the observability stack if not already running:

```bash
kubectl -n istio-system port-forward svc/prometheus 9090:9090 &
kubectl -n istio-system port-forward svc/grafana 3000:3000 &
```

- **Prometheus** (<http://localhost:9090>) — query `istio_request_duration_milliseconds_bucket` filtered by `destination_service="ratings.bookinfo.svc.cluster.local"` to see the latency spike.
- **Grafana** (<http://localhost:3000>) — open the **Bookinfo** dashboard; the `ratings` service panel will show elevated p99 latency only during the period when `jason` was generating traffic.

#### Remove the fault

```bash
kubectl delete -f networking/virtual-service-ratings-test-delay.yaml -n bookinfo
```

To also restore `reviews` to round-robin across all versions:

```bash
kubectl delete -f networking/virtual-service-reviews-test-v2.yaml -n bookinfo
```

### 7. Percentage-based fault injection — 50% of traffic to `ratings`

[networking/virtual-service-ratings-test-delay-50-percent.yaml](networking/virtual-service-ratings-test-delay-50-percent.yaml)
applies the same 7s `ratings` delay as step 6, but with `fault.delay.percentage.value: 50.0`
and **no `end-user` header match** — it affects 50% of *all* traffic that
reaches `ratings`, regardless of who the caller is.

#### Apply and validate

`scripts/14-test-percentage-fault.sh` applies the required VirtualServices
(`virtual-service-reviews-test-v2.yaml` so `jason` is routed to `reviews-v2`,
which calls `ratings`, plus the 50% delay rule above), runs the load
generator as `jason` for 60s while capturing per-request latencies, and
asserts that the observed delay rate matches the configured percentage:

```bash
bash scripts/14-test-percentage-fault.sh
```

Because `productpage` retries its call to `reviews` once with a hardcoded 3s
timeout (see `src/productpage/productpage.py:getProductReviews`), and each
attempt makes its own independent call to `ratings`, a single `/productpage`
request lands in one of three latency clusters:

- **~0s** — first `ratings` call wasn't delayed, page renders normally.
- **~3s** — first `ratings` call was delayed (1st attempt times out), but the
  retry's `ratings` call wasn't delayed.
- **~6s** — both `ratings` calls were delayed; `productpage` gives up and
  shows "Sorry, product reviews are currently unavailable for this book."

The fraction of requests taking **>= 1.5s** (i.e. landing in the ~3s or ~6s
clusters) equals the probability that the *first* `ratings` call was
delayed — which is exactly the configured `fault.delay.percentage.value`.

You can tune the run with env vars, e.g. `DURATION`, `THREADS`,
`LATENCY_THRESHOLD`, `TOLERANCE`. Captured samples are written to
`logs/14-latency-fault-percentage.csv` (`timestamp,thread_id,elapsed,status`).

#### Remove the fault

```bash
kubectl delete -f networking/virtual-service-ratings-test-delay-50-percent.yaml -n bookinfo
kubectl delete -f networking/virtual-service-reviews-test-v2.yaml -n bookinfo
```

## Alternative exposure: `kubectl port-forward`

If you can't or don't want to use the NodePort (for example on multi-node kind
or a cluster that wasn't created from this `kind-config.yaml`):

```bash
bash scripts/04-port-forward.sh
```

This forwards `svc/productpage:9080` to `localhost:9080` and stays in the
foreground. Open <http://localhost:9080/productpage>. Stop with `Ctrl+C`.

## Part 2: Metrics and load generation

Install Prometheus and Grafana:

```bash
bash scripts/06-install-metrics.sh
```

Grafana access:

```bash
kubectl -n istio-system port-forward svc/grafana 3000:3000
```

Open <http://localhost:3000> and look for the Bookinfo dashboard.

Traffic generation starts automatically when you run `scripts/run-all.sh`.
If you need to start it manually:

```bash
bash scripts/08-start-load-generator.sh
```

## Part 3: Tracing and topology

Reapply the Istio profile to ensure the tracing backend is configured:

```bash
bash scripts/02-install-istio.sh
```

Install Jaeger, Kiali, Kiali CRDs/CR, and Telemetry (100% sampling for bookinfo):

```bash
bash scripts/07-install-tracing.sh
```

Access Kiali:

```bash
kubectl -n kiali port-forward svc/kiali 20001:20001
```

Access Jaeger:

```bash
kubectl -n jaeger port-forward svc/tracing 16686:80
```

## Cleanup

Stop port-forwards (Ctrl+C in each terminal) and stop the traffic generator:

```bash
bash scripts/09-stop-load-generator.sh
```

```bash
bash scripts/99-cleanup.sh
```

Deletes the `bookinfo` kind cluster (and therefore everything inside it). The
script is a no-op if the cluster doesn't exist.

## Configuration knobs

All scripts honor a few env vars if you want to deviate from the defaults:

| Variable | Default | Used by |
| ------------- | ---------- | ------- |
| `CLUSTER_NAME` | `bookinfo` | 01, 02, 03, 99 |
| `NAMESPACE` | `bookinfo` | 02, 03 |
| `LOCAL_PORT` | `9080` | 03 |
| `URL` | `http://localhost:31080/productpage` | 04 |
| `URL` | `http://localhost:31080/productpage` | 08 |
| `THREADS` | `5` | 08 |
| `DELAY_MIN` | `0.1` | 08 |
| `DELAY_MAX` | `1.0` | 08 |

Example: `CLUSTER_NAME=demo bash scripts/01-create-cluster.sh`.

## Troubleshooting

- **`docker daemon is not reachable`** — start Docker Desktop and wait until
  the whale icon stops animating, then retry.
- **`context 'kind-bookinfo' not found`** when running 02 — you skipped step
  01. Run `bash scripts/01-create-cluster.sh` first.
- **Validate script fails with HTTP 000 / connection refused** — pods may not
  be Ready yet. Check `kubectl -n bookinfo get pods`. If they're stuck in
  `ContainerCreating`, the images are still being pulled — wait and retry.
- **Port 31080 already in use on the host** — something else is bound to it.
-  Either free the port or destroy the cluster, edit `kind-config.yaml` to use
  a different `hostPort`, and recreate.
- **Ingress gateway NodePort conflict** — if `istio-ingressgateway` cannot
  bind `31080`, delete any leftover `productpage` NodePort service or run
  `bash scripts/99-cleanup.sh` and re-run `bash scripts/run-all.sh`.

## What's next

Once the no-mesh baseline is verified, the next phases will introduce Istio
using the manifests already present in this repository:

- `networking/` — DestinationRules and VirtualServices for traffic routing.
- `gateway-api/` — Kubernetes Gateway API resources.
- `policy/` — example AuthorizationPolicy and friends.
- `demo-profile-no-gateways.yaml` — IstioOperator profile to install the
  control plane without the default gateways.

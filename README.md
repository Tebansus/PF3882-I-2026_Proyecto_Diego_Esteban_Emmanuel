# Bookinfo on local Kubernetes (kind) with Istio service mesh

A complete local service-mesh lab built on [kind](https://kind.sigs.k8s.io/) and
[Istio](https://istio.io/), using the Bookinfo sample application as the workload.
The project covers the full lifecycle of a service mesh: cluster provisioning,
Istio installation, Bookinfo deployment, traffic engineering (canary, header-based
routing), fault injection (latency, percentage-based), timeout and retry policies,
resilience load testing, and a full observability stack (Prometheus, Grafana, Jaeger,
Kiali).

## What this gives you

- A single-node kind cluster named `bookinfo` with pre-configured port mappings.
- Istio control plane (`istiod`) installed with the demo profile and ingress gateway
  enabled.
- The 6 Bookinfo workloads deployed in a `bookinfo` namespace with Istio sidecar
  injection enabled: `productpage-v1`, `details-v1`, `ratings-v1`, `reviews-v1`,
  `reviews-v2`, `reviews-v3`.
- The `productpage` frontend exposed through the Istio ingress gateway at
  <http://localhost:31080/productpage>.
- An Istio `Gateway` and `VirtualService` that route external traffic to
  `productpage`.
- Canary deployment — 90 % `reviews-v1`, 5 % v2, 5 % v3 — with an automated
  validation script.
- Header-based routing that sends requests carrying `end-user: jason` to a specific
  `reviews` version.
- Latency fault injection — a 7-second delay on `ratings` scoped to the `jason`
  user, with an automated test that verifies the timeout cascade.
- Percentage-based fault injection — 7-second delay on 50 % of all `ratings`
  requests, with latency histogram measurement and statistical validation.
- Timeout and retry configuration for `reviews` — 3-second request timeout with
  up to 3 automatic retries on 5xx errors and a 2-second per-try timeout.
- Retry mechanism load test (`scripts/15-test-retry-mechanism.py`) — runs in
  self-contained mock mode (no cluster required) or against a live cluster; proves
  that the configured retry policy raises the success rate from ~60 % to ~94 % at
  a 40 % fault rate.
- Prometheus + Grafana for metrics, with a Bookinfo dashboard.
- Jaeger + Kiali for distributed tracing and service topology (100 % sampling in
  `bookinfo`).
- An in-cluster load generator that starts automatically and can be scaled
  independently.
- An automated smoke test that verifies the page actually renders data from the
  `details` and `reviews` services and that Istio is properly installed.

## Prerequisites

| Tool | Version used |
| --------- | ------------ |
| Docker | 29.x (Docker Desktop on Windows; daemon must be running) |
| kind | 0.31.0 |
| kubectl | 1.34.x |
| istioctl | 1.22.x (Istio CLI installed locally) |
| Python | 3.x (`python` or `python3` on PATH) |
| bash | Git Bash, WSL, or any POSIX-ish shell |
| curl | for the validation script |

All must be on `PATH`. Run `docker info` once to confirm the daemon is reachable.

## Project files

```text
.
├── kind-config.yaml                          # kind cluster definition + port mappings
├── demo-profile-no-gateways.yaml             # Istio operator config (ingress gateway enabled)
├── swagger.yaml                              # API documentation for Bookinfo endpoints
│
├── scripts/
│   ├── run-all.sh                            # Full end-to-end setup and test run
│   ├── 01-create-cluster.sh                  # Creates the kind cluster
│   ├── 02-install-istio.sh                   # Installs Istio control plane
│   ├── 03-deploy-bookinfo.sh                 # Deploys Bookinfo + gateway + destination rules
│   ├── 04-port-forward.sh                    # Alternative exposure via kubectl port-forward
│   ├── 05-validate.sh                        # Smoke test (HTTP 200 + HTML content checks)
│   ├── 06-install-metrics.sh                 # Installs Prometheus + Grafana + dashboard
│   ├── 07-install-tracing.sh                 # Installs Jaeger + Kiali + 100% sampling telemetry
│   ├── 08-start-load-generator.sh            # Scales up the in-cluster load generator
│   ├── 09-stop-load-generator.sh             # Scales down the in-cluster load generator
│   ├── 10-verify-canary.sh                   # Validates the 90/5/5 canary traffic split
│   ├── 11-test-header-routing.sh             # Validates header-based routing for user jason
│   ├── 12-query-metrics.sh                   # Queries Prometheus for live traffic metrics
│   ├── 13-test-latency-fault.sh              # Validates the 7s ratings delay and timeout cascade
│   ├── 14-test-percentage-fault.sh           # Validates 50% percentage-based latency injection
│   ├── 15-test-retry-mechanism.py            # Retry load test (mock + cluster modes)
│   ├── load-generator.py                     # Configurable traffic simulator script
│   ├── load-generator-deploy.yaml            # Kubernetes Deployment for the load generator
│   ├── Dockerfile.loadgen                    # Container image for the load generator
│   └── productpage-nodeport-31080.yaml       # Optional NodePort fallback (no ingress needed)
│
├── networking/
│   ├── bookinfo-gateway.yaml                 # Istio Gateway (port 31080, HTTP)
│   ├── destination-rule-all.yaml             # DestinationRules with v1/v2/v3 subsets for all services
│   ├── destination-rule-reviews.yaml         # DestinationRules for reviews only
│   ├── destination-rules.yaml                # Minimal destination rules
│   ├── destination-rule-all-mtls.yaml        # DestinationRules with mTLS mode
│   ├── virtual-service-all-v1.yaml           # Routes all services to v1
│   ├── virtual-service-canary.yaml           # Canary: 90% v1, 5% v2, 5% v3 for reviews
│   ├── virtual-service-header.yaml           # Header-based routing example
│   ├── combined-virtual-service.yaml         # Header routing + canary fallback combined
│   ├── virtual-service-reviews-test-v2.yaml  # Routes all reviews traffic to v2
│   ├── virtual-service-reviews-timeout-3s.yaml # 3s timeout + 3 retries on 5xx for reviews
│   ├── virtual-service-reviews-80-20.yaml    # 80/20 traffic split
│   ├── virtual-service-reviews-90-10.yaml    # 90/10 traffic split
│   ├── virtual-service-reviews-50-v3.yaml    # 50% traffic to v3
│   ├── virtual-service-reviews-v2-v3.yaml    # Split between v2 and v3
│   ├── virtual-service-reviews-v3.yaml       # Routes all reviews to v3
│   ├── virtual-service-reviews-jason-v2-v3.yaml # Jason → v2, others → v3
│   ├── virtual-service-ratings-test-delay.yaml # 7s latency on ratings (end-user: jason only)
│   ├── virtual-service-ratings-test-delay-50-percent.yaml # 7s latency on 50% of ratings requests
│   ├── virtual-service-ratings-test-abort.yaml # HTTP abort injection for ratings
│   ├── virtual-service-ratings-db.yaml       # Routes ratings to database-backed version
│   ├── virtual-service-ratings-mysql.yaml    # Routes ratings to MySQL backend
│   ├── virtual-service-ratings-mysql-vm.yaml # Routes ratings to external MySQL VM
│   ├── virtual-service-details-v2.yaml       # Routes details to v2
│   ├── fault-injection-details-v1.yaml       # Fault injection for details v1
│   ├── egress-rule-google-apis.yaml          # Egress access to external Google APIs
│   └── certmanager-gateway.yaml              # Gateway with cert-manager TLS
│
├── metrics/
│   ├── prometheus.yaml                       # Prometheus deployment
│   ├── grafana.yaml                          # Grafana deployment
│   ├── bookinfo-dashboard.yaml               # ConfigMap with Bookinfo Grafana dashboard
│   └── bookinfo-dashboard.json               # Dashboard JSON (request volume, latency, errors)
│
├── tracing/
│   ├── jaeger.yaml                           # Jaeger all-in-one deployment (in-memory)
│   ├── kiali.yaml                            # Kiali deployment
│   ├── kiali-crd.yaml                        # Kiali custom resource definitions
│   ├── kiali-cr.yaml                         # Kiali custom resource instance
│   ├── telemetry-bookinfo.yaml               # Telemetry resource: 100% trace sampling in bookinfo
│   └── namespaces.yaml                       # Namespace setup for observability tools
│
├── platform/kube/
│   ├── bookinfo.yaml                         # Complete Bookinfo manifests (all deployments + services)
│   ├── bookinfo-versions.yaml                # Multi-version deployment configuration
│   ├── bookinfo-db.yaml                      # Database service definitions
│   ├── bookinfo-mysql.yaml                   # MySQL deployment with init script
│   ├── bookinfo-ratings-v2-mysql.yaml        # Ratings v2 with MySQL backend
│   ├── bookinfo-ratings-v2-mysql-vm.yaml     # Ratings v2 against an external MySQL VM
│   ├── bookinfo-ratings-discovery.yaml       # Service discovery configuration for ratings
│   ├── bookinfo-details-v2.yaml              # Details v2 deployment
│   ├── bookinfo-reviews-v2.yaml              # Reviews v2 deployment
│   ├── bookinfo-psa.yaml                     # Pod Security Admission enforcement
│   ├── bookinfo-dualstack.yaml               # IPv4/IPv6 dual-stack networking
│   ├── bookinfo-certificate.yaml             # TLS certificate configuration
│   ├── bookinfo-ingress.yaml                 # Non-Istio ingress (alternative)
│   └── productpage-nodeport.yaml             # NodePort exposure for productpage
│
├── policy/
│   └── productpage_envoy_ratelimit.yaml      # Envoy rate limiting for productpage
│
├── gateway-api/
│   ├── bookinfo-gateway.yaml                 # Kubernetes Gateway API Gateway resource
│   ├── route-all-v1.yaml                     # HTTPRoute to all v1 versions
│   ├── route-reviews-v1.yaml                 # HTTPRoute to reviews v1
│   ├── route-reviews-v3.yaml                 # HTTPRoute to reviews v3
│   ├── route-reviews-50-v3.yaml              # HTTPRoute with 50% split to v3
│   └── route-reviews-90-10.yaml              # HTTPRoute with 90/10 split
│
├── src/
│   ├── productpage/                          # Python/Flask frontend; aggregates details, reviews, ratings
│   ├── details/                              # Ruby microservice; returns book metadata
│   ├── ratings/                              # Node.js microservice; returns star ratings
│   ├── reviews/                              # Java (OpenLiberty) microservice; three versions (no/black/red stars)
│   ├── mongodb/                              # MongoDB seed data for ratings v2
│   └── mysql/                                # MySQL schema for ratings v2
│
├── docs/
│   ├── ProjectProposal.md                    # Project objectives and scope
│   ├── TrafficEngineering.md                 # Traffic split and header routing walkthrough
│   └── BookinfoSampleBuildAndPush.md         # Custom Docker image build and push guide
│
└── logs/                                     # Runtime output and CSV captures from test scripts
```

## How `kind-config.yaml` is set up

Single control-plane node with three host port mappings:

| Container port | Host port | Used for |
| --- | --- | --- |
| 31080 | 31080 | Istio ingress gateway NodePort (HTTP) |
| 80 | 8080 | Reserved for a non-Istio ingress controller |
| 443 | 8443 | Reserved for a non-Istio ingress controller |

## Quick start (TL;DR)

From the project root run:

```bash
bash scripts/run-all.sh
```

This performs the complete setup in order: cluster creation, Istio install, Bookinfo
deployment, smoke test, metrics and tracing installation, canary validation, header
routing validation, latency fault injection and testing, percentage fault injection
and testing, retry mechanism configuration and validation, and load generator
deployment.

Open the app:

- <http://localhost:31080/productpage>

Expose the observability UIs (run each in its own terminal; keep them running):

```bash
kubectl -n istio-system port-forward svc/grafana 3000:3000
kubectl -n kiali port-forward svc/kiali 20001:20001
kubectl -n jaeger port-forward svc/tracing 16686:80
```

Open the tools:

- Grafana: <http://localhost:3000>
- Kiali: <http://localhost:20001/kiali>
- Jaeger: <http://localhost:16686/jaeger>

Start or stop the load generator:

```bash
bash scripts/08-start-load-generator.sh
bash scripts/09-stop-load-generator.sh
```

Tear everything down:

```bash
bash scripts/99-cleanup.sh
```

## Step-by-step

### 1. Create the cluster

```bash
bash scripts/01-create-cluster.sh
```

- Verifies `docker`, `kind`, `kubectl` are on PATH and the Docker daemon is up.
- Skips creation if a kind cluster named `bookinfo` already exists.
- Runs `kind create cluster --name bookinfo --config kind-config.yaml`.
- Switches kubectl to context `kind-bookinfo` and prints node info.

Expected: a `bookinfo-control-plane` node appears (briefly `NotReady` while CNI
initializes — that's normal).

### 2. Install Istio

```bash
bash scripts/02-install-istio.sh
```

- Installs Istio control plane using the demo profile with ingress gateway enabled.
- Waits for `istiod` deployment to be ready.

Expected: Istio components running in `istio-system` namespace.

### 3. Deploy Bookinfo

```bash
bash scripts/03-deploy-bookinfo.sh
```

- Creates the `bookinfo` namespace and labels it for Istio sidecar injection.
- Applies all Bookinfo manifests from `platform/kube/bookinfo.yaml`.
- Applies the Istio `Gateway` and `VirtualService` for `productpage`.
- Waits for all deployments to be Available.

Expected: 6 pods running in `bookinfo` namespace, each with an Istio sidecar (2/2
Ready).

### 4. Validate

```bash
bash scripts/05-validate.sh
```

- Checks that the Istio control plane is ready.
- `curl`s <http://localhost:31080/productpage> and asserts HTTP 200.
- Greps the response for the productpage title, the "Book Details" section (proves
  `details` was reached), and the "Book Reviews" section (proves a `reviews` pod
  was reached).

Expected: "Bookinfo is reachable and rendering all upstream services."

### 5. Canary routing

```bash
kubectl -n bookinfo apply -f networking/virtual-service-canary.yaml
bash scripts/10-verify-canary.sh
```

Applies a `VirtualService` that routes 90 % of `reviews` traffic to v1, 5 % to v2,
and 5 % to v3. The verify script sends multiple requests and checks that the observed
version distribution matches the configured weights.

### 6. Header-based routing

```bash
kubectl -n bookinfo apply -f networking/combined-virtual-service.yaml
bash scripts/11-test-header-routing.sh
```

Requests carrying `end-user: jason` are routed exclusively to the configured
`reviews` version; all other requests fall through to the canary split. The test
script validates both paths with `curl`.

### 7. Latency fault injection — 7-second delay on `ratings` for user `jason`

Inject an artificial 7-second delay into the `ratings` service, scoped only to
requests that carry `end-user: jason`.

#### Latency fault prerequisites

Steps 1–4 must be complete and DestinationRules must be applied:

```bash
kubectl apply -f networking/destination-rule-all.yaml -n bookinfo
```

#### Apply the fault

Route `jason` to `reviews-v2` (the only variant that calls `ratings`), then inject
the delay:

```bash
kubectl apply -f networking/virtual-service-reviews-test-v2.yaml -n bookinfo
kubectl apply -f networking/virtual-service-ratings-test-delay.yaml -n bookinfo
```

#### Test as Jason

1. Open <http://localhost:31080/productpage>.
2. Click **Sign in** and log in as `jason` (password: `jason`).
3. Observe a ~7-second pause before the reviews section renders.
4. Log out and reload — the page should load instantly as an anonymous user.

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

```bash
bash scripts/13-test-latency-fault.sh
```

Confirms the 7s fault delay is configured on the `ratings` VirtualService, sends
one anonymous request (expects a fast response with reviews rendered), and one
`jason` request (expects the productpage "unavailable" message because the 7s delay
trips its hardcoded 3s timeout after one retry).

#### Remove the latency fault

```bash
kubectl delete -f networking/virtual-service-ratings-test-delay.yaml -n bookinfo
kubectl delete -f networking/virtual-service-reviews-test-v2.yaml -n bookinfo
```

### 8. Percentage-based fault injection — 50 % of all `ratings` traffic

```bash
kubectl apply -f networking/virtual-service-ratings-test-delay-50-percent.yaml -n bookinfo
kubectl apply -f networking/virtual-service-reviews-test-v2.yaml -n bookinfo
bash scripts/14-test-percentage-fault.sh
```

Applies the same 7s delay but with `fault.delay.percentage.value: 50.0` and no
header match — it affects half of *all* `ratings` requests.

Because `productpage` retries its call to `reviews` once with a 3s timeout, each
`/productpage` request lands in one of three latency clusters:

- **~0 s** — first `ratings` call was not delayed.
- **~3 s** — first call delayed (times out), retry's call not delayed.
- **~6 s** — both calls delayed; page shows "Sorry, product reviews are currently
  unavailable."

The fraction of requests taking ≥ 1.5 s matches the configured fault percentage.
Captured latency samples are written to `logs/14-latency-fault-percentage.csv`.

You can tune the run with env vars: `DURATION`, `THREADS`, `LATENCY_THRESHOLD`,
`TOLERANCE`.

#### Remove the percentage fault

```bash
kubectl delete -f networking/virtual-service-ratings-test-delay-50-percent.yaml -n bookinfo
kubectl delete -f networking/virtual-service-reviews-test-v2.yaml -n bookinfo
```

### 9. Timeout and retry configuration

```bash
kubectl apply -f networking/virtual-service-reviews-timeout-3s.yaml -n bookinfo
```

Configures the `reviews` VirtualService with:

- **3-second** overall request timeout.
- Up to **3 retry attempts** on 5xx responses.
- **2-second per-try timeout**.

This means Istio automatically retries transient failures before surfacing an error
to the caller, without any changes to the application code.

### 10. Retry mechanism validation

```bash
python scripts/15-test-retry-mechanism.py
```

Runs in self-contained mock mode by default — no cluster required. Starts a local
HTTP server that returns HTTP 500 for a configurable fraction of requests (default
40 %). Runs two phases:

- **Phase 1 — No retry:** each logical request is attempted once. Expected success
  rate: ~60 %.
- **Phase 2 — With retry:** each logical request is retried up to 3 times on 5xx,
  mirroring the Istio VirtualService `retries` block. Expected success rate: ~94 %
  (1 − 0.4³).

Against a live cluster with a fault-injection VirtualService already applied, pass
`--url http://localhost:31080/api/v1/products/0/reviews` to run the same two phases
against the real endpoint.

### 11. Load generator

The load generator is deployed as an in-cluster Kubernetes `Deployment` and is built
from `scripts/Dockerfile.loadgen`. It is built and loaded into kind automatically
by `run-all.sh`. To manage it manually:

```bash
# Start
bash scripts/08-start-load-generator.sh

# Stop
bash scripts/09-stop-load-generator.sh
```

Configure traffic shape via env vars on the Deployment (see Configuration knobs
below).

## Alternative exposure: `kubectl port-forward`

If you cannot use the NodePort (for example, on a cluster not created from this
`kind-config.yaml`):

```bash
bash scripts/04-port-forward.sh
```

Forwards `svc/productpage:9080` to `localhost:9080`. Open
<http://localhost:9080/productpage>. Stop with `Ctrl+C`.

## Observability

Install Prometheus and Grafana (included in `run-all.sh`):

```bash
bash scripts/06-install-metrics.sh
kubectl -n istio-system port-forward svc/grafana 3000:3000
```

Open <http://localhost:3000> and look for the **Bookinfo** dashboard.

Install Jaeger, Kiali, and telemetry (included in `run-all.sh`):

```bash
bash scripts/07-install-tracing.sh
kubectl -n kiali port-forward svc/kiali 20001:20001
kubectl -n jaeger port-forward svc/tracing 16686:80
```

Query live Prometheus metrics:

```bash
bash scripts/12-query-metrics.sh
```

## Cleanup

Stop port-forwards (`Ctrl+C` in each terminal), stop the traffic generator, then
delete the cluster:

```bash
bash scripts/09-stop-load-generator.sh
bash scripts/99-cleanup.sh
```

`99-cleanup.sh` deletes the `bookinfo` kind cluster (and therefore everything inside
it). It is a no-op if the cluster does not exist.

## Configuration knobs

All scripts honor a few env vars if you want to deviate from the defaults:

| Variable | Default | Used by |
| ---------------- | ------------------------------------ | ------- |
| `CLUSTER_NAME` | `bookinfo` | 01, 02, 03, 99 |
| `NAMESPACE` | `bookinfo` | 02, 03 |
| `LOCAL_PORT` | `9080` | 04 |
| `URL` | `http://localhost:31080/productpage` | 08, 14 |
| `THREADS` | `5` | 08, 14 |
| `DELAY_MIN` | `0.1` | 08 |
| `DELAY_MAX` | `1.0` | 08 |
| `DURATION` | `60` | 14 |
| `LATENCY_THRESHOLD` | `2.5` | 14 |
| `TOLERANCE` | `0.15` | 14 |

Example: `CLUSTER_NAME=demo bash scripts/01-create-cluster.sh`.

## Troubleshooting

- **`docker daemon is not reachable`** — start Docker Desktop and wait until the
  whale icon stops animating, then retry.
- **`context 'kind-bookinfo' not found`** when running `02-install-istio.sh` — you
  skipped step 1. Run `bash scripts/01-create-cluster.sh` first.
- **Validate script fails with HTTP 000 / connection refused** — pods may not be
  Ready yet. Check `kubectl -n bookinfo get pods`. If they're stuck in
  `ContainerCreating`, images are still being pulled — wait and retry.
- **Port 31080 already in use on the host** — free the port, or destroy the cluster,
  edit `kind-config.yaml` to use a different `hostPort`, and recreate.
- **Ingress gateway NodePort conflict** — if `istio-ingressgateway` cannot bind
  31080, delete any leftover `productpage` NodePort service or run
  `bash scripts/99-cleanup.sh` and re-run `bash scripts/run-all.sh`.
- **`python` not found** when running `run-all.sh` — install Python 3 and ensure
  `python` or `python3` is on `PATH`.
- **Kiali CRD race on a clean restart** — if Kiali fails to start because the CRDs
  are not yet established, re-run `bash scripts/07-install-tracing.sh`; the script
  waits for CRDs before applying the CR.

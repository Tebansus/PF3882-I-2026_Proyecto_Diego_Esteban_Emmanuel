# Bookinfo on local Kubernetes (kind) with Istio service mesh

Phase 2 of the project: get the Istio Bookinfo sample app running on a local
Kubernetes cluster created with [kind](https://kind.sigs.k8s.io/), with the
Istio service mesh installed and configured. This includes installing the Istio control plane
(istiod) and enabling sidecar injection for the Bookinfo namespace.

## What this gives you

- A single-node kind cluster named `bookinfo`.
- Istio control plane (istiod) installed with demo profile (no gateways).
- The 6 Bookinfo workloads deployed in a `bookinfo` namespace with Istio sidecar
  injection enabled: `productpage-v1`, `details-v1`, `ratings-v1`, `reviews-v1`,
  `reviews-v2`, `reviews-v3`.
- The `productpage` frontend exposed on the host at
  <http://localhost:30080/productpage> via a `NodePort` mapped through kind's
  `extraPortMappings`.
- An automated smoke test that verifies the page actually renders data coming
  from the `details` and `reviews` services, and that Istio is properly installed.

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
├── demo-profile-no-gateways.yaml        # Istio operator config for demo profile without gateways
├── kind-config.yaml                     # kind cluster definition + port mappings
├── MyREADME.md                          # (this file)
└── scripts/
    ├── 01-create-cluster.sh             # creates the kind cluster
    ├── 02-install-istio.sh              # installs Istio control plane using local istioctl
    ├── 03-deploy-bookinfo.sh            # applies manifests + enables sidecar injection + waits for Ready
    ├── 04-port-forward.sh               # alternative exposure via kubectl port-forward
    ├── 05-validate.sh                   # smoke test against productpage + Istio validation
    ├── 99-cleanup.sh                    # deletes the kind cluster
    ├── run-all.sh                       # 01 -> 02 -> 03 -> 05
    └── productpage-nodeport-30080.yaml  # NodePort override pinned to 30080
```

The upstream Istio sample manifests under `platform/kube/` are **not modified**.
The NodePort override lives in `scripts/` and replaces the default ClusterIP
`productpage` Service applied from `platform/kube/bookinfo.yaml`.

## How `kind-config.yaml` is set up

Single control-plane node with three host port mappings:

| Container port | Host port | Used for |
| --- | --- | --- |
| 30080 | 30080 | `productpage` NodePort (this phase) |
| 80 | 8080 | reserved for an ingress controller (future) |
| 443 | 8443 | reserved for an ingress controller (future) |

## Quick start (TL;DR)

From the project root (`bookinfo/`):

```bash
bash scripts/run-all.sh
```

Then open <http://localhost:30080/productpage>.

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
- Installs Istio control plane using the demo profile (no gateways).
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
- Applies the NodePort override to expose `productpage` on port 30080.
- Waits for all deployments to be Available.

Expected: 6 pods running in `bookinfo` namespace, each with an Istio sidecar (2/2 Ready).

### 4. Validate

```bash
bash scripts/05-validate.sh
```

What it does:

- Checks that Istio control plane is installed and ready.
- `curl`s <http://localhost:30080/productpage> and asserts HTTP 200.
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

## Alternative exposure: `kubectl port-forward`

If you can't or don't want to use the NodePort (for example on multi-node kind
or a cluster that wasn't created from this `kind-config.yaml`):

```bash
bash scripts/04-port-forward.sh
```

This forwards `svc/productpage:9080` to `localhost:9080` and stays in the
foreground. Open <http://localhost:9080/productpage>. Stop with `Ctrl+C`.

## Cleanup

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
| `URL` | `http://localhost:30080/productpage` | 04 |

Example: `CLUSTER_NAME=demo bash scripts/01-create-cluster.sh`.

## Troubleshooting

- **`docker daemon is not reachable`** — start Docker Desktop and wait until
  the whale icon stops animating, then retry.
- **`context 'kind-bookinfo' not found`** when running 02 — you skipped step
  01. Run `bash scripts/01-create-cluster.sh` first.
- **Validate script fails with HTTP 000 / connection refused** — pods may not
  be Ready yet. Check `kubectl -n bookinfo get pods`. If they're stuck in
  `ContainerCreating`, the images are still being pulled — wait and retry.
- **Port 30080 already in use on the host** — something else is bound to it.
  Either free the port or destroy the cluster, edit `kind-config.yaml` to use
  a different `hostPort`, and recreate.

## What's next

Once the no-mesh baseline is verified, the next phases will introduce Istio
using the manifests already present in this repository:

- `networking/` — DestinationRules and VirtualServices for traffic routing.
- `gateway-api/` — Kubernetes Gateway API resources.
- `policy/` — example AuthorizationPolicy and friends.
- `demo-profile-no-gateways.yaml` — IstioOperator profile to install the
  control plane without the default gateways.

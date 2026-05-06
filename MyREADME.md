# Bookinfo on local Kubernetes (kind) — no Istio yet

Phase 1 of the project: get the Istio Bookinfo sample app running on a local
Kubernetes cluster created with [kind](https://kind.sigs.k8s.io/), without the
Istio service mesh. This is the baseline we will later compare against once the
mesh is introduced.

## What this gives you

- A single-node kind cluster named `bookinfo`.
- The 6 Bookinfo workloads deployed in a `bookinfo` namespace:
  `productpage-v1`, `details-v1`, `ratings-v1`, `reviews-v1`, `reviews-v2`,
  `reviews-v3`.
- The `productpage` frontend exposed on the host at
  <http://localhost:30080/productpage> via a `NodePort` mapped through kind's
  `extraPortMappings`.
- An automated smoke test that verifies the page actually renders data coming
  from the `details` and `reviews` services.

## Prerequisites

| Tool    | Version used |
| ------- | ------------ |
| Docker  | 29.x (Docker Desktop on Windows; daemon must be running) |
| kind    | 0.31.0 |
| kubectl | 1.34.x |
| bash    | Git Bash, WSL, or any POSIX-ish shell |
| curl    | for the validation script |

All four must be on `PATH`. Run `docker info` once to make sure the daemon is
reachable.

## Files added in this phase

```
bookinfo/
├── kind-config.yaml                     # kind cluster definition + port mappings
├── MyREADME.md                          # (this file)
└── scripts/
    ├── 01-create-cluster.sh             # creates the kind cluster
    ├── 02-deploy-bookinfo.sh            # applies manifests + waits for Ready
    ├── 03-port-forward.sh               # alternative exposure via kubectl port-forward
    ├── 04-validate.sh                   # smoke test against productpage
    ├── 99-cleanup.sh                    # deletes the kind cluster
    ├── run-all.sh                       # 01 -> 02 -> 04
    └── productpage-nodeport-30080.yaml  # NodePort override pinned to 30080
```

The upstream Istio sample manifests under `platform/kube/` are **not modified**.
The NodePort override lives in `scripts/` and replaces the default ClusterIP
`productpage` Service applied from `platform/kube/bookinfo.yaml`.

## How `kind-config.yaml` is set up

Single control-plane node with three host port mappings:

| Container port | Host port | Used for |
| --- | --- | --- |
| 30080 | 30080 | `productpage` NodePort (this phase)             |
| 80    | 8080  | reserved for an ingress controller (future)     |
| 443   | 8443  | reserved for an ingress controller (future)     |

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

### 2. Deploy Bookinfo

```bash
bash scripts/02-deploy-bookinfo.sh
```

What it does:

- Switches to the `kind-bookinfo` context.
- Creates the `bookinfo` namespace if missing.
- Applies `platform/kube/bookinfo.yaml` (Services, ServiceAccounts, Deployments).
- Applies `scripts/productpage-nodeport-30080.yaml` to convert the
  `productpage` Service to `NodePort` on port 30080.
- `kubectl wait`s up to 5 minutes for **all** deployments to become Available.
- Prints the resulting pods and services.

You should see all six pods `1/1 Running` and the `productpage` Service of
type `NodePort` mapping `9080:30080/TCP`.

### 3. Validate

```bash
bash scripts/04-validate.sh
```

What it does:

- `curl`s `http://localhost:30080/productpage`, asserts HTTP 200.
- Greps the response for the productpage HTML title, the "Book Details"
  section (proves the `details` service was reached), and the "Book Reviews"
  section (proves a `reviews` pod was reached). Reviews itself calls
  `ratings`, so any non-v1 reviews variant exercises that hop too.

If all three checks pass, the local deployment is healthy. Open the URL in a
browser and refresh several times — you should see the reviews section cycle
between the v1 (no stars), v2 (black stars), and v3 (red stars) variants
because Kubernetes load-balances across the three `reviews` Deployments
round-robin via the `reviews` Service.

## Alternative exposure: `kubectl port-forward`

If you can't or don't want to use the NodePort (for example on multi-node kind
or a cluster that wasn't created from this `kind-config.yaml`):

```bash
bash scripts/03-port-forward.sh
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

| Variable      | Default    | Used by |
| ------------- | ---------- | ------- |
| `CLUSTER_NAME` | `bookinfo` | 01, 02, 03, 99 |
| `NAMESPACE`    | `bookinfo` | 02, 03 |
| `LOCAL_PORT`   | `9080`     | 03 |
| `URL`          | `http://localhost:30080/productpage` | 04 |

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

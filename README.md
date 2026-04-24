***

# ✅ 1. One‑time setup on Windows

## 1.1 Install Docker Desktop

*   Enable:
    *   ✅ *Use WSL 2 based engine*
    *   ✅ *WSL integration → Ubuntu*

No Kubernetes needs to be enabled in Docker Desktop.

***

## 1.2 Install WSL2 + Ubuntu

Open **PowerShell as Administrator**:

```powershell
wsl --install -d Ubuntu
```

Restart Windows if prompted.

Open **Ubuntu** from the Start Menu.

***

## 2. Install required tools inside WSL (bash)

Inside the **Ubuntu terminal**:

```bash
sudo apt update
sudo apt install -y curl
```

### kubectl

```bash
curl -LO https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl
sudo install kubectl /usr/local/bin/kubectl
```

### kind

```bash
curl -Lo kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-amd64
chmod +x kind
sudo mv kind /usr/local/bin/kind
```

Verify:

```bash
docker version
kubectl version --client
kind version
```

***

# ✅ 3. Create the project directory

```bash
mkdir bookinfo-kind
cd bookinfo-kind
```

## Directory structure

```text
bookinfo-kind/
├── kind-config.yaml
├── scripts/
    ├── 00-create-cluster.sh
    ├── 01-deploy-bookinfo.sh
    ├── 02-validate.sh
    └── 99-delete-cluster.sh
```

***

# ✅ 4. kind-config.yaml

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: bookinfo
nodes:
  - role: control-plane
```

This is sufficient for Bookinfo + port‑forwarding.

***

# ✅ 5. Bash scripts

## 5.1 Create the cluster

`scripts/00-create-cluster.sh`

```bash
#!/usr/bin/env bash
set -e

if kind get clusters | grep -q "^bookinfo$"; then
  echo "Cluster already exists"
  exit 0
fi

kind create cluster --name bookinfo --config kind-config.yaml
kubectl cluster-info
```

***

## 5.2 Deploy the **official Istio Bookinfo manifests (no mesh)**

`scripts/01-deploy-bookinfo.sh`

```bash
#!/usr/bin/env bash
set -e

kubectl create namespace bookinfo --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -n bookinfo \
  -f https://raw.githubusercontent.com/istio/istio/master/samples/bookinfo/platform/kube/bookinfo.yaml

kubectl apply -n bookinfo \
  -f https://raw.githubusercontent.com/istio/istio/master/samples/bookinfo/platform/kube/bookinfo-versions.yaml
```

This deploys:

*   productpage
*   details
*   reviews (v1, v2, v3)
*   ratings

✅ **No Istio yet**  
✅ Exactly what the requirement states

***

## 5.3 Validate pods are running

`scripts/02-validate.sh`

```bash
#!/usr/bin/env bash
set -e

kubectl wait \
  -n bookinfo \
  --for=condition=Ready pod \
  --all \
  --timeout=180s

kubectl get pods -n bookinfo
```

***

## 5.4 Cleanup script

`scripts/99-delete-cluster.sh`

```bash
#!/usr/bin/env bash
set -e
kind delete cluster --name bookinfo
```

***

# ✅ 6. Run everything

Inside **Ubuntu (WSL)**:

```bash
chmod +x scripts/*.sh

scripts/00-create-cluster.sh
scripts/01-deploy-bookinfo.sh
scripts/02-validate.sh
```

***

# ✅ 7. Expose and validate the application

## Option A (recommended): kubectl port-forward

```bash
kubectl -n bookinfo port-forward svc/productpage 9080:9080
```

Now open:

    http://localhost:9080/productpage

***

# ✅ 8. What you should verify

✅ Product page loads  
✅ Book details are shown  
✅ Reviews appear  
✅ Some reviews show stars (ratings service)  
✅ Page refreshes show consistent service interaction

This confirms:

*   Kubernetes networking works
*   All microservices communicate
*   App is healthy **before introducing Istio**

***

param(
    [string]$ClusterName = "pf3882",
    [string]$Namespace = "bookinfo"
)

$ErrorActionPreference = "Stop"

function Test-Command {
    param([string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "No se encontró '$Name'. Instálalo y vuelve a ejecutar."
    }
}

function Assert-LastExitCode {
    param([string]$Step)

    if ($LASTEXITCODE -ne 0) {
        throw "Falló: $Step"
    }
}

Write-Host "==> Verificando prerequisitos..." -ForegroundColor Cyan
Test-Command docker
Test-Command kubectl
Test-Command kind

docker info | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Docker Desktop no está corriendo. Ábrelo y espera a que diga 'Engine running'."
}

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$configPath = Join-Path $root "infra\kind\cluster.yaml"
$bookinfoManifestPath = Join-Path $root "infra\k8s\bookinfo.yaml"

if (-not (Test-Path $configPath)) {
    throw "No existe infra/kind/cluster.yaml en: $configPath"
}

if (-not (Test-Path $bookinfoManifestPath)) {
    throw "No existe infra/k8s/bookinfo.yaml en: $bookinfoManifestPath"
}

Write-Host "==> Creando clúster kind '$ClusterName'..." -ForegroundColor Cyan
$existingClusters = kind get clusters
Assert-LastExitCode "listar clústeres kind"
if ($existingClusters -contains $ClusterName) {
    Write-Host "El clúster '$ClusterName' ya existe. Se reutiliza." -ForegroundColor Yellow
}
else {
    kind create cluster --name $ClusterName --config $configPath
    Assert-LastExitCode "crear clúster kind"
}

$context = "kind-$ClusterName"
kubectl config use-context $context | Out-Null
Assert-LastExitCode "seleccionar contexto kubectl"

Write-Host "==> Creando namespace '$Namespace'..." -ForegroundColor Cyan
kubectl create namespace $Namespace --dry-run=client -o yaml | kubectl apply -f - | Out-Null
Assert-LastExitCode "crear namespace"

$bookinfoExists = kubectl get deployment productpage-v1 -n $Namespace --ignore-not-found -o name
Assert-LastExitCode "verificar despliegue Bookinfo"

if ([string]::IsNullOrWhiteSpace($bookinfoExists)) {
    $images = @(
        "docker.io/istio/examples-bookinfo-details-v1:1.20.3",
        "docker.io/istio/examples-bookinfo-ratings-v1:1.20.3",
        "docker.io/istio/examples-bookinfo-reviews-v1:1.20.3",
        "docker.io/istio/examples-bookinfo-reviews-v2:1.20.3",
        "docker.io/istio/examples-bookinfo-reviews-v3:1.20.3",
        "docker.io/istio/examples-bookinfo-productpage-v1:1.20.3"
    )

    Write-Host "==> Verificando imágenes locales para modo local-only..." -ForegroundColor Cyan
    foreach ($image in $images) {
        docker image inspect $image | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Falta imagen local: $image. Ejecuta ./scripts/windows/preload-images.ps1 -PullIfMissing"
        }

        kind load docker-image $image --name $ClusterName
        Assert-LastExitCode "cargar imagen local $image en kind"
    }
}

Write-Host "==> Aplicando Bookinfo desde manifiesto local del repo..." -ForegroundColor Cyan
kubectl apply -n $Namespace -f $bookinfoManifestPath
Assert-LastExitCode "aplicar manifiesto local de Bookinfo"

$deployments = @(
    "details-v1",
    "productpage-v1",
    "ratings-v1",
    "reviews-v1",
    "reviews-v2",
    "reviews-v3"
)

Write-Host "==> Esperando despliegues..." -ForegroundColor Cyan
foreach ($deployment in $deployments) {
    kubectl rollout status deployment/$deployment -n $Namespace --timeout=240s
    Assert-LastExitCode "esperar deployment $deployment"
}

Write-Host "\n==> Estado final" -ForegroundColor Green
kubectl get pods -n $Namespace -o wide
Assert-LastExitCode "listar pods"
kubectl get svc -n $Namespace
Assert-LastExitCode "listar servicios"

Write-Host "\nBookinfo listo. Para abrirlo desde Windows usa:" -ForegroundColor Green
Write-Host "kubectl -n $Namespace port-forward svc/productpage 9080:9080" -ForegroundColor White
Write-Host "Luego navega a: http://localhost:9080/productpage" -ForegroundColor White

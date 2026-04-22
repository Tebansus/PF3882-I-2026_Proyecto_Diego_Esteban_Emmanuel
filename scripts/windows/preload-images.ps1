param(
    [string]$ClusterName = "pf3882",
    [switch]$PullIfMissing
)

$ErrorActionPreference = "Stop"

$images = @(
    "docker.io/istio/examples-bookinfo-details-v1:1.20.3",
    "docker.io/istio/examples-bookinfo-ratings-v1:1.20.3",
    "docker.io/istio/examples-bookinfo-reviews-v1:1.20.3",
    "docker.io/istio/examples-bookinfo-reviews-v2:1.20.3",
    "docker.io/istio/examples-bookinfo-reviews-v3:1.20.3",
    "docker.io/istio/examples-bookinfo-productpage-v1:1.20.3"
)

foreach ($image in $images) {
    docker image inspect $image | Out-Null
    if ($LASTEXITCODE -ne 0) {
        if ($PullIfMissing) {
            Write-Host "Descargando $image ..." -ForegroundColor Yellow
            docker pull $image
            if ($LASTEXITCODE -ne 0) {
                throw "No se pudo descargar $image"
            }
        }
        else {
            throw "Falta imagen local: $image. Ejecuta este script con -PullIfMissing al menos una vez."
        }
    }

    Write-Host "Cargando en kind: $image" -ForegroundColor Cyan
    kind load docker-image $image --name $ClusterName
    if ($LASTEXITCODE -ne 0) {
        throw "Falló kind load docker-image para $image"
    }
}

Write-Host "Imágenes Bookinfo cargadas en kind-$ClusterName" -ForegroundColor Green

param(
    [ValidateSet("v1", "v2", "v3")]
    [string]$Version = "v1",
    [string]$Namespace = "bookinfo"
)

$ErrorActionPreference = "Stop"

$allVersions = @("v1", "v2", "v3")

Write-Host "Cambiando reviews activo a $Version en namespace '$Namespace'..." -ForegroundColor Cyan

foreach ($v in $allVersions) {
    $replicas = if ($v -eq $Version) { 1 } else { 0 }
    kubectl -n $Namespace scale deployment/reviews-$v --replicas=$replicas | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "No se pudo escalar reviews-$v"
    }
}

kubectl -n $Namespace rollout status deployment/reviews-$Version --timeout=180s | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "reviews-$Version no quedó listo"
}

Write-Host "Listo. Versión activa: reviews-$Version" -ForegroundColor Green

switch ($Version) {
    "v1" { Write-Host "UI esperada: reseñas sin estrellas." -ForegroundColor White }
    "v2" { Write-Host "UI esperada: estrellas oscuras." -ForegroundColor White }
    "v3" { Write-Host "UI esperada: estrellas rojas." -ForegroundColor White }
}

kubectl get deploy -n $Namespace reviews-v1 reviews-v2 reviews-v3

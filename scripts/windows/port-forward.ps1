param(
    [string]$Namespace = "bookinfo"
)

$ErrorActionPreference = "Stop"

Write-Host "Exponiendo productpage en http://localhost:9080/productpage" -ForegroundColor Green
kubectl -n $Namespace port-forward svc/productpage 9080:9080

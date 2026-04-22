# PF3882-I-2026_Proyecto_Diego_Esteban_Emmanuel

Setup inicial (Semana 1–2): clúster local con kind + despliegue base de Bookinfo.

## Estructura ordenada

- `infra/kind/cluster.yaml`: definición del clúster kind.
- `infra/k8s/bookinfo.yaml`: manifiestos de todos los microservicios Bookinfo.
- `scripts/windows/setup.ps1`: levanta/reutiliza clúster y aplica Bookinfo.
- `scripts/windows/preload-images.ps1`: valida/precarga imágenes locales en kind.
- `scripts/windows/port-forward.ps1`: expone `productpage` en localhost.
- `scripts/windows/switch-reviews.ps1`: activa una sola versión de `reviews` (`v1`, `v2` o `v3`).

## Modo local-only

- Manifiestos 100% locales (`infra/k8s/bookinfo.yaml`).
- `imagePullPolicy: Never` en deployments para no hacer pull en runtime.

Si es la primera vez y faltan imágenes locales:

```powershell
./scripts/windows/preload-images.ps1 -PullIfMissing
```

## Requisitos

- Docker Desktop (Linux engine activo)
- kubectl
- kind

## Uso (Windows)

Desde la raíz del repo:

```powershell
./scripts/windows/setup.ps1
```

Validación:

```powershell
kubectl get pods -n bookinfo
kubectl get svc -n bookinfo
```

Exponer app:

```powershell
./scripts/windows/port-forward.ps1
```

URL:

- http://localhost:9080/productpage

## Cambiar versión de reviews (UI)

Para dejar una sola versión activa:

```powershell
./scripts/windows/switch-reviews.ps1 -Version v1
./scripts/windows/switch-reviews.ps1 -Version v2
./scripts/windows/switch-reviews.ps1 -Version v3
```

Señal visual esperada en la UI:

- `v1`: sin estrellas
- `v2`: estrellas oscuras
- `v3`: estrellas rojas

Limpieza opcional:

```powershell
kind delete cluster --name pf3882
```
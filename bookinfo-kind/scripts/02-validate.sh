#!/usr/bin/env bash
set -e

kubectl wait \
  -n bookinfo \
  --for=condition=Ready pod \
  --all \
  --timeout=180s

kubectl get pods -n bookinfo

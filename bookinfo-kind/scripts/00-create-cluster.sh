#!/usr/bin/env bash
set -e

if kind get clusters | grep -q "^bookinfo$"; then
  echo "Cluster already exists"
  exit 0
fi

kind create cluster --name bookinfo --config kind-config.yaml
kubectl cluster-info

#!/usr/bin/env bash
set -e

kubectl create namespace bookinfo --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -n bookinfo \
  -f https://raw.githubusercontent.com/istio/istio/master/samples/bookinfo/platform/kube/bookinfo.yaml

kubectl apply -n bookinfo \
  -f https://raw.githubusercontent.com/istio/istio/master/samples/bookinfo/platform/kube/bookinfo-versions.yaml

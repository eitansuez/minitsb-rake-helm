#!/usr/bin/env bash

tctl apply -f artifacts/tenant.yaml

kubectl apply --context t1 -f artifacts/t1-manifest.yaml

for cluster in c1 c2; do
  kubectl apply --context ${cluster} -f artifacts/workload-manifest.yaml
  kubectl apply --context ${cluster} -n bookinfo -f https://raw.githubusercontent.com/istio/istio/master/samples/bookinfo/platform/kube/bookinfo.yaml
  kubectl apply --context ${cluster} -n bookinfo -f https://raw.githubusercontent.com/istio/istio/master/samples/sleep/sleep.yaml
done

tctl apply -f artifacts/workspaces.yaml
tctl apply -f artifacts/groups.yaml
tctl apply -f artifacts/gateways.yaml

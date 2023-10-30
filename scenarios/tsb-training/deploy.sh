#!/usr/bin/env bash

tctl apply -f artifacts/tenant.yaml

vcluster connect t1
kubectl apply -f artifacts/t1-manifest.yaml

for cluster in c1 c2; do
  vcluster connect ${cluster}
  kubectl apply -f artifacts/workload-manifest.yaml
  kubectl apply -n bookinfo -f https://raw.githubusercontent.com/istio/istio/master/samples/bookinfo/platform/kube/bookinfo.yaml
  kubectl apply -n bookinfo -f https://raw.githubusercontent.com/istio/istio/master/samples/sleep/sleep.yaml
done

tctl apply -f artifacts/workspaces.yaml
tctl apply -f artifacts/groups.yaml
tctl apply -f artifacts/gateways.yaml

vcluster disconnect

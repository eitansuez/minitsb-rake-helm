#!/usr/bin/env bash

function wait_clusters_onboarded {
  for cluster in t1 c1 c2; do
    echo "Wait for cluster ${cluster} to be onboarded"
    while ! tctl experimental status cluster ${cluster} | grep "Cluster onboarded" &>/dev/null ; do
      sleep 5
      echo -n "."
    done
    echo "DONE"
  done
}

tctl apply -f artifacts/clusters.yaml
wait_clusters_onboarded

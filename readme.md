# Readme

This repository is derived from [minitsb-rake](https://github.com/eitansuez/minitsb-rake).
The difference is that instead of using the `tctl` CLI to install TSB, here we use Helm.

## Recipe

1. Provision the VM.  See instructions in the terraform subdirectory's [readme file](terraform/readme.md).

1. Ssh onto the VM

    ```shell
    gcloud compute ssh ubuntu@tsb-vm
    ```

1. Before proceeding, check on the status of `cloud-init` to make sure the VM setup is complete:

     ```shell
     cloud-init status
     ```

    The logs of the cloud-init activity are located in `/var/log/cloud-init-output.log`.

1. Kick off the installation of TSB with the command:

     ```shell
     rake
     ```

## Scenario convention

Under the `scenarios` directory, create a new directory named after your new scenario.

The contents of your scenario directory must include three files:

1. `topology.yaml`: a list of `clusters`.  For each cluster, at the very least supply a name.  Fields `region` and `zone` are optional, and are useful for specifying locality.  Designate the management plane cluster with `is_mp: true`.  Workload clusters are onboarded by default.  Can optionally specify not to onboard a workload cluster with `onboard_cluster: false`.  See existing scenarios for an example of a topology.

1. `deploy.sh`: a script that applies Kubernetes and TSB resources to build a scenario (deploy an application, configure ingress, etc..).  This script is often accompanied with Kubernetes and TSB yaml files that are applied by the script.  See existing scenarios for an example.

1. `info.sh`: a script that outputs any information you wish the user to have including sample commands to exercise or generate a load against a deployed application.

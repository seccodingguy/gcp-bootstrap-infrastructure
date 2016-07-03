#!/bin/bash

# Store base directory for starting point of script executions
BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && cd ../ && pwd )"

GCP_PROJECT=${1:-GCP-CD}
GCP_ZONE=${2:-europe-west1-b}
GCP_MACHINE_TYPE=${3:-n1-standard-2}
NUM_NODES=${4:-1}

validate_environment() {
  # Check pre-requisites for required command line tools

 printf "\nChecking pre-requisites for required tooling"

 command -v gcloud >/dev/null 2>&1 || { echo >&2 "Google Cloud SDK required - doesn't seem to be on your path.  Aborting."; exit 1; }
 command -v kubectl >/dev/null 2>&1 || { echo >&2 "Kubernetes commands required - doesn't seem to be on your path.  Aborting."; exit 1; }

 printf "\nAll pre-requisite software seem to be installed :)"
}

authorise_gcp() {
  gcloud auth login
  gcloud config set project $GCP_PROJECT
  gcloud config set compute/zone $GCP_ZONE

  printf "\nAbout to create a Container Cluster in the '$GCP_PROJECT' GCP project located in '$GCP_ZONE' with $NUM_NODES x '$GCP_MACHINE_TYPE' node(s)\n"
  read -rsp $'Press any key to continue...or Ctrl+C to exit\n' -n1 key
}

build_gcp_cluster() {
  gcloud container clusters create "cd-cluster" \
  --zone "$GCP_ZONE" \
  --machine-type "$GCP_MACHINE_TYPE" \
  --num-nodes "$NUM_NODES" \
  --network "default" \
  --username "admin"

  gcloud config set container/cluster cd-cluster
  gcloud container clusters get-credentials cd-cluster
}

build_jenkins_server() {
  printf "\nProvisioning Jenkins Service...\n"
  cd $BASE_DIR/kubernetes/jenkins-master
  kubectl create -f jenkins-service.yaml
  printf "Jenkins Service created\n"
  printf "Waiting for public Jenkins ingress point..."
  JENKINS_ADDRESS=''; while [[ "e$JENKINS_ADDRESS" == "e" ]]; do JENKINS_ADDRESS=`kubectl describe service/jenkins-ui 2>/dev/null | grep "LoadBalancer\ Ingress" | cut -f2`; printf "."; done;

  printf "\nConfiguring Jenkins pod properties...\n"
  initialise_jenkins_pod_properties
  printf "\nCompleted Jenkins pod property creation\n"

  cd $BASE_DIR/kubernetes/jenkins-master
  printf "\nProvisioning Jenkins Pod...\n"

  # Update Google Cloud Project environment variable
  cp jenkins-pod-template.yaml jenkins-pod.yaml
  sed -i.bak "s/GCP_PROJECT_DEFAULT_VALUE/$GCP_PROJECT/" jenkins-pod.yaml
  kubectl create -f jenkins-pod.yaml
  rm jenkins-pod.yaml
  rm jenkins-pod.yaml.bak

  printf "\nJenkins service up and running on $JENKINS_ADDRESS\n"
}

initialise_jenkins_pod_properties() {
  KUBERNETES_MASTER=$(kubectl cluster-info | grep "Kubernetes master" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')

  cd $BASE_DIR/kubernetes
  kubectl delete --ignore-not-found=true configmap cd-config
  kubectl create configmap cd-config \
          --from-literal=kubernetes.master=https://$KUBERNETES_MASTER \
          --from-literal=jenkins.master=$JENKINS_ADDRESS
}


_main() {

  validate_environment

  printf "\nProvisioning development environment...."

  # Authorise google cloud SDK
  authorise_gcp

  # Utilise terraform to provision the Google Cluster
  build_gcp_cluster

  # Push Go CD out on to the cluster
  build_jenkins_server

  printf "\nCompleted provisioning development environment!!\n\n"
}

_main
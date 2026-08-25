#!/usr/bin/env bash
# Create the local kind cluster and install the pieces the lab assumes.
# Idempotent enough to re-run, kind refuses to create a duplicate cluster
# and helm upgrade --install handles both first install and re-runs.
set -euo pipefail

cd "$(dirname "$0")"

if ! kind get clusters 2>/dev/null | grep -qx obs-lab; then
  kind create cluster --config kind-config.yaml
else
  echo "cluster obs-lab already exists, skipping create"
fi

kubectl config use-context kind-obs-lab

# metrics-server is not part of kind. Without it, kubectl top and the
# HPA have no resource metrics to work from. The kubelet-insecure-tls
# flag is needed because kind's kubelets use self-signed certs. Fine in
# this lab, not something to carry to a real cluster.
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ >/dev/null
helm repo update >/dev/null
helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  --set args="{--kubelet-insecure-tls}"

kubectl create namespace app --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

echo
echo "cluster ready. next steps:"
echo "  docker build -t demo-app:dev ../../app"
echo "  kind load docker-image demo-app:dev --name obs-lab"
echo "  kubectl apply -k ../../k8s/overlays/local"

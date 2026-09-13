#!/usr/bin/env bash
# Install (or upgrade) the observability stack from the values files in
# this directory. Works the same on kind and GKE, the values contain
# nothing cluster-specific.
set -euo pipefail

cd "$(dirname "$0")"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo update >/dev/null

helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --values kube-prometheus-stack/values.yaml

echo
echo "stack installed. Grafana:"
echo "  kubectl -n monitoring port-forward svc/kps-grafana 3000:80"
echo "  http://localhost:3000  (admin / admin)"

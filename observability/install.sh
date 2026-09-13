#!/usr/bin/env bash
# Install (or upgrade) the observability stack from the values files in
# this directory. Works the same on kind and GKE, the values contain
# nothing cluster-specific.
set -euo pipefail

cd "$(dirname "$0")"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null
helm repo update >/dev/null

helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --values kube-prometheus-stack/values.yaml

helm upgrade --install loki grafana/loki \
  --namespace monitoring \
  --values loki/values.yaml

helm upgrade --install promtail grafana/promtail \
  --namespace monitoring \
  --values loki/promtail-values.yaml

kubectl apply -f kube-prometheus-stack/servicemonitor.yaml
kubectl apply -f alerts/demo-app-rules.yaml
kubectl apply -k dashboards

echo
echo "stack installed. Grafana:"
echo "  kubectl -n monitoring port-forward svc/kps-grafana 3000:80"
echo "  http://localhost:3000  (admin / admin)"

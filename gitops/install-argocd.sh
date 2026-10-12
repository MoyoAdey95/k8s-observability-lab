#!/usr/bin/env bash
# Install (or upgrade) Argo CD from the values file next to this script.
# Deliberately not Terraform. README.md in this directory says why.
set -euo pipefail

cd "$(dirname "$0")"

helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo update >/dev/null

# Pinned for the same reason every chart in gitops/apps is pinned. An
# unpinned install gives whoever runs this next a different Argo CD from
# the one the evidence in docs/ was captured against.
helm upgrade --install argocd argo/argo-cd \
  --version 10.10.3 \
  --namespace argocd --create-namespace \
  --values values.yaml

kubectl -n argocd rollout status deploy/argocd-server --timeout=5m

echo
echo "argo cd installed. UI:"
echo "  kubectl -n argocd port-forward svc/argocd-server 8080:80"
echo "  http://localhost:8080  (user admin)"
echo
echo "admin password:"
echo "  kubectl -n argocd get secret argocd-initial-admin-secret \\"
echo "    -o jsonpath='{.data.password}' | base64 -d; echo"

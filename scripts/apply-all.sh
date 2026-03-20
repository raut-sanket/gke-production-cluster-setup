#!/usr/bin/env bash
set -euo pipefail

# Apply all manifests in order
echo "==> Applying namespaces..."
kubectl apply -f manifests/base/namespaces.yaml

echo "==> Applying resource quotas..."
kubectl apply -f manifests/base/resource-quotas.yaml

echo "==> Applying RBAC..."
kubectl apply -f manifests/rbac/

echo "==> Applying network policies..."
kubectl apply -f manifests/base/network-policies.yaml

echo "==> Applying applications..."
kubectl apply -f manifests/apps/

echo "==> Applying ingress..."
kubectl apply -f manifests/ingress/

echo "==> Applying monitoring rules..."
kubectl apply -f manifests/monitoring/

echo "==> Applying jobs..."
kubectl apply -f manifests/jobs/

echo "==> All manifests applied."
kubectl get pods -n production

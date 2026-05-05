#!/bin/bash
set -e

CLUSTER_NAME="k8s-lab"
echo "================================================"
echo "  Starting K3d cluster: ${CLUSTER_NAME}"
echo "================================================"

# Check if cluster already exists
if k3d cluster list | grep -q "^${CLUSTER_NAME}"; then
  STATUS=$(k3d cluster list | grep "^${CLUSTER_NAME}" | awk '{print $2}')
  echo "▶ Cluster '${CLUSTER_NAME}' exists (${STATUS})"
  
  if echo "${STATUS}" | grep -q "0/1"; then
    echo "  Restarting stopped cluster..."
    k3d cluster start ${CLUSTER_NAME}
  else
    echo "  Cluster is already running ✅"
  fi
else
  echo "▶ Creating new cluster '${CLUSTER_NAME}'..."
  k3d cluster create ${CLUSTER_NAME} \
    --servers 1 \
    --agents 2 \
    --port "8080:80@loadbalancer" \
    --port "8443:443@loadbalancer" \
    --wait
  echo "  ✅ Cluster created"
fi

# Merge kubeconfig
k3d kubeconfig merge ${CLUSTER_NAME} --kubeconfig-switch-context

echo ""
echo "▶ Cluster info:"
echo ""
kubectl get nodes -o wide
echo ""
echo "================================================"
echo "  ✅ Cluster ready! Try:"
echo ""
echo "     kubectl get nodes"
echo "     kubectl get pods -A"
echo "     k9s"
echo "================================================"

# Lab 01: Deploy Your First App
# ─────────────────────────────────────────────────────────────────────────────
#
# HOW TO USE THIS LAB:
#   Copy and paste each command block into your terminal one step at a time.
#   Do not run this file as a script.
#
# In this lab you will deploy a simple nginx web server, expose it as a
# ClusterIP Service, and access it via port-forward. You will also scale
# the deployment and observe how pods are distributed across agent nodes.
#
# What you will build:
#
#   ┌──────────────────────────────────────────────────────────┐
#   │  Namespace: lab01                                         │
#   │                                                          │
#   │  ┌─────────────────────────────────────────────────┐    │
#   │  │  Deployment: nginx  (replicas: 2 → 4)           │    │
#   │  │                                                  │    │
#   │  │   ┌──────────┐  ┌──────────┐                   │    │
#   │  │   │ nginx    │  │ nginx    │  (+ 2 more when   │    │
#   │  │   │ pod      │  │ pod      │   scaled)         │    │
#   │  │   │ agent-0  │  │ agent-1  │                   │    │
#   │  │   └──────────┘  └──────────┘                   │    │
#   │  └──────────────────┬──────────────────────────────┘    │
#   │                     │                                    │
#   │  ┌──────────────────▼──────────────────────────────┐    │
#   │  │  Service: nginx (ClusterIP)  port 80            │    │
#   │  └──────────────────┬──────────────────────────────┘    │
#   └─────────────────────│────────────────────────────────────┘
#                         │ kubectl port-forward
#                    localhost:8081
#
# Key concepts: Deployment, ReplicaSet, Pod, ClusterIP Service, port-forward

# ── Step 1: Verify your cluster is running ────────────────────────────────────
kubectl get nodes
# Expected: 1 server node + 2 agent nodes, all STATUS=Ready

# ── Step 2: Create a namespace for this lab ───────────────────────────────────
kubectl create namespace lab01

# ── Step 3: Deploy nginx ──────────────────────────────────────────────────────
kubectl apply -n lab01 -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  labels:
    app: nginx
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
YAML

# ── Step 4: Watch pods come up ────────────────────────────────────────────────
kubectl get pods -n lab01 -o wide
# Press Ctrl+C once both pods show STATUS=Running

# Notice pods are spread across agent-0 and agent-1 — the scheduler
# distributes them automatically for availability.

# ── Step 5: Create a ClusterIP Service ───────────────────────────────────────
kubectl expose deployment nginx -n lab01 --port=80 --type=ClusterIP

# ── Step 6: Inspect the Service ───────────────────────────────────────────────
kubectl get svc -n lab01
kubectl describe svc nginx -n lab01
# Note the ClusterIP — this is only reachable inside the cluster.
# The Endpoints list shows which pod IPs are receiving traffic.

# ── Step 7: Test with port-forward ───────────────────────────────────────────
# In one terminal:
kubectl port-forward svc/nginx 8081:80 -n lab01
# Open the PORTS tab in VS Code and visit the forwarded port 8081

# ── Step 8: Scale the deployment ─────────────────────────────────────────────
kubectl scale deployment nginx -n lab01 --replicas=4
kubectl get pods -n lab01
# Notice the scheduler spreads the new pods across both agent nodes

# ── Step 9: Clean up ─────────────────────────────────────────────────────────
kubectl delete namespace lab01


# ── Further Reading ───────────────────────────────────────────────────────────
# Pods:
#   https://kubernetes.io/docs/concepts/workloads/pods/
# Deployments:
#   https://kubernetes.io/docs/concepts/workloads/controllers/deployment/
# ReplicaSets:
#   https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/
# Services:
#   https://kubernetes.io/docs/concepts/services-networking/service/
# kubectl port-forward:
#   https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/

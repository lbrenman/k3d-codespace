# Lab 2: Ingress with Traefik
# ─────────────────────────────────────────────────────────────────────────────
# k3d includes Traefik as its default ingress controller — no extra install
# needed! This lab deploys two apps and routes to them via Ingress rules based
# on the URL path.
#
# What you will build:
#
#   Browser / curl
#        │
#        │ :8080 (Codespace port → k3d LoadBalancer)
#        ▼
#   ┌─────────────────────────────────────────────────────────┐
#   │  Traefik Ingress Controller  (kube-system namespace)    │
#   │                                                         │
#   │  Ingress rules:                                         │
#   │    /whoami  ──────────────────────────────────────────┐ │
#   │    /        ───────────────────────────────────────┐  │ │
#   └───────────────────────────────────────────────────────┘ │
#        │  Namespace: lab2                              │  │
#        │                                              │  │
#   ┌────▼─────────────────┐        ┌───────────────────▼──┐
#   │  Service: web        │        │  Service: whoami      │
#   │  (ClusterIP :80)     │        │  (ClusterIP :80)      │
#   └────────┬─────────────┘        └──────────┬────────────┘
#            │                                 │
#   ┌────────▼──────────┐           ┌──────────▼────────────┐
#   │  Pod: nginx       │           │  Pod: traefik/whoami  │
#   │  returns default  │           │  returns request info │
#   │  nginx page       │           │  (headers, IP, host)  │
#   └───────────────────┘           └───────────────────────┘
#
# Key concepts: Ingress, IngressController, path-based routing, ClusterIP Service

# ── Step 1: Create namespace ──────────────────────────────────────────────────
kubectl create namespace lab2

# ── Step 2: Deploy two apps ───────────────────────────────────────────────────
kubectl apply -n lab2 -f - <<YAML
# App 1 — "whoami" service
apiVersion: apps/v1
kind: Deployment
metadata:
  name: whoami
spec:
  replicas: 1
  selector:
    matchLabels:
      app: whoami
  template:
    metadata:
      labels:
        app: whoami
    spec:
      containers:
      - name: whoami
        image: traefik/whoami
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: whoami
spec:
  selector:
    app: whoami
  ports:
  - port: 80
---
# App 2 — simple nginx
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: web
        image: nginx:alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  selector:
    app: web
  ports:
  - port: 80
YAML

# ── Step 3: Create Ingress rules ──────────────────────────────────────────────
kubectl apply -n lab2 -f - <<YAML
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: lab2-ingress
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  rules:
  - http:
      paths:
      - path: /whoami
        pathType: Prefix
        backend:
          service:
            name: whoami
            port:
              number: 80
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web
            port:
              number: 80
YAML

# ── Step 4: Test it ───────────────────────────────────────────────────────────
# In your Codespace, open the PORTS tab → click port 8080 → visit:
#   /         → nginx default page
#   /whoami   → shows request headers, IP, hostname

# Or from the terminal:
curl http://localhost:8080/
curl http://localhost:8080/whoami

# ── Step 5: Inspect Traefik dashboard (optional) ──────────────────────────────
# The Traefik service only exposes ports 80 and 443 externally.
# The dashboard runs on port 9000 inside the container, so we port-forward
# directly to the pod rather than the service:
kubectl get svc traefik -n kube-system

kubectl port-forward -n kube-system \
  $(kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik -o name) \
  9080:9000
# Visit port 9080 in browser → /dashboard/
# NOTE: the trailing slash is required

# ── Step 6: Clean up ─────────────────────────────────────────────────────────
kubectl delete namespace lab2

# Lab 2: Ingress with Traefik
# ─────────────────────────────────────────────────────────────────────────────
# k3d includes Traefik as its default ingress controller — no extra install
# needed! This lab deploys two apps and routes to them via Ingress rules.
# Traffic enters through port 8080 on your Codespace (mapped to port 80 on
# the k3d load balancer).

# ── Step 1: Create namespace ──────────────────────────────────────────────────
kubectl create namespace lab2

# ── Step 2: Deploy two apps ───────────────────────────────────────────────────
kubectl apply -n lab2 -f - <<EOF
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
EOF

# ── Step 3: Create Ingress rules ──────────────────────────────────────────────
kubectl apply -n lab2 -f - <<EOF
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
EOF

# ── Step 4: Test it ───────────────────────────────────────────────────────────
# In your Codespace, open the PORTS tab → click port 8080 → visit:
#   /         → nginx default page
#   /whoami   → shows request headers, IP, hostname

# Or from the terminal:
curl http://localhost:8080/
curl http://localhost:8080/whoami

# ── Step 5: Inspect Traefik dashboard (optional) ──────────────────────────────
kubectl port-forward -n kube-system svc/traefik 9000:9000
# Visit port 9000 → /dashboard/

# ── Step 6: Clean up ─────────────────────────────────────────────────────────
kubectl delete namespace lab2

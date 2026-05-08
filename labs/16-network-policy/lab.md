# Lab 16: NetworkPolicy — Controlling Pod-to-Pod Traffic
# ─────────────────────────────────────────────────────────────────────────────
# By default, every pod in a Kubernetes cluster can reach every other pod —
# across namespaces, across nodes, without any restriction. This is convenient
# for development but wrong for production: a compromised pod can freely probe
# every database, internal service, and management endpoint in the cluster.
#
# NetworkPolicy lets you write firewall rules at the pod level, using the same
# label selectors you already know.
#
# HOW TO USE THIS LAB:
#   Copy and paste each command block into your terminal one step at a time.
#   Do not run this file as a script.
#
# ── How NetworkPolicy enforcement works in k3d ───────────────────────────────
# NetworkPolicy enforcement is a common source of confusion, so it's worth
# understanding exactly what's running in this cluster:
#
#   Flannel    — the default CNI plugin used by k3s/k3d for pod networking.
#                Flannel handles IP assignment and routing between pods.
#                Flannel itself does NOT enforce NetworkPolicy.
#
#   kube-router — a separate network policy controller bundled with k3s.
#                 It runs automatically alongside Flannel and enforces
#                 NetworkPolicy objects using iptables rules on each node.
#
# Result: k3d enforces NetworkPolicy out of the box. Policies you apply in
# this lab will produce real blocking behaviour — no extra setup needed.
#
# What you will build:
#
#   ┌──────────────────────────────────────────────────────────────────┐
#   │  Namespace: lab16                                                │
#   │                                                                  │
#   │  ┌───────────┐     allow     ┌───────────┐                      │
#   │  │  frontend │ ───────────► │  backend  │                      │
#   │  │  pod      │               │  pod      │                      │
#   │  └───────────┘               └─────┬─────┘                      │
#   │                                    │ allow                       │
#   │  ┌───────────┐                     ▼                            │
#   │  │  attacker │  ✗ blocked ┌───────────────┐                    │
#   │  │  pod      │ ──────────►│   database    │                    │
#   │  └───────────┘            │   pod         │                    │
#   │                           └───────────────┘                    │
#   └──────────────────────────────────────────────────────────────────┘
#
# Key concepts: NetworkPolicy, ingress rules, egress rules, podSelector,
#               namespaceSelector, deny-all baseline, kube-router, CNI plugins

# ── Step 1: Create namespace ──────────────────────────────────────────────────
kubectl create namespace lab16

# ── Step 2: Deploy pods and Services representing a 3-tier app ───────────────
# Services are created here alongside the pods so that DNS names like
# "database" and "backend" resolve immediately in subsequent steps.
kubectl apply -n lab16 -f - <<YAML
# Frontend — the only entry point for user traffic
apiVersion: v1
kind: Pod
metadata:
  name: frontend
  labels:
    app: frontend
    tier: frontend
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
  name: frontend
spec:
  selector:
    app: frontend
  ports:
  - port: 80
---
# Backend — processes requests from the frontend
apiVersion: v1
kind: Pod
metadata:
  name: backend
  labels:
    app: backend
    tier: backend
spec:
  containers:
  - name: api
    image: hashicorp/http-echo:latest
    args: ["-text=backend response", "-listen=:8080"]
    ports:
    - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: backend
spec:
  selector:
    app: backend
  ports:
  - port: 8080
---
# Database — should only accept connections from the backend
apiVersion: v1
kind: Pod
metadata:
  name: database
  labels:
    app: database
    tier: database
spec:
  containers:
  - name: db
    image: nginx:alpine   # Simulating a database with a simple HTTP server
    ports:
    - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: database
spec:
  selector:
    app: database
  ports:
  - port: 80
---
# Attacker — simulates a compromised pod trying to reach the database directly
apiVersion: v1
kind: Pod
metadata:
  name: attacker
  labels:
    app: attacker
spec:
  containers:
  - name: attacker
    image: busybox:latest
    command: ["/bin/sh", "-c", "sleep 3600"]
YAML

kubectl get pods -n lab16 -w
# Press Ctrl+C once all pods show Running

# ── Step 3: Verify default behaviour — everything can reach everything ────────
# Before any NetworkPolicy is applied, all pods can reach all other pods.
# This is Kubernetes' default "flat network" model.
# The attacker can freely reach the database — this is the problem we will fix.
kubectl exec attacker -n lab16 -- \
  wget -qO- --timeout=3 http://database 2>/dev/null \
  && echo "✓ Attacker reached database (no policy yet — expected)" \
  || echo "✗ Could not reach database"
# Expected: ✓ Attacker reached database

# ── Step 4: Apply a deny-all ingress baseline to the database ─────────────────
# The foundation of network security: start with "deny everything" and then
# explicitly allow only what is needed.
# An empty ingress list means: select this pod, allow zero ingress traffic.
kubectl apply -n lab16 -f - <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: database-deny-all
spec:
  podSelector:
    matchLabels:
      tier: database    # Apply to the database pod
  policyTypes:
  - Ingress             # Control incoming connections
  ingress: []           # Empty list = deny all ingress
YAML

kubectl get networkpolicy -n lab16
# Shows the policy exists

# kube-router enforces this immediately via iptables — the attacker is blocked.
kubectl exec attacker -n lab16 -- \
  wget -qO- --timeout=3 http://database 2>/dev/null \
  && echo "✗ Reached database (unexpected)" \
  || echo "✓ Blocked — deny-all policy is enforced"
# Expected: ✓ Blocked — deny-all policy is enforced

# ── Step 5: Allow backend → database traffic ──────────────────────────────────
# Add a specific allow rule on top of the deny-all baseline.
# Only pods labelled tier=backend can connect to the database on port 80.
kubectl apply -n lab16 -f - <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: database-allow-backend
spec:
  podSelector:
    matchLabels:
      tier: database          # This policy applies to the database pod
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: backend       # Only allow traffic from pods labelled tier=backend
    ports:
    - protocol: TCP
      port: 80
YAML

kubectl get networkpolicy -n lab16
# Both policies are listed. They are additive: deny-all + allow-backend
# means only backend traffic is permitted.

# Verify: backend can reach database, attacker still cannot
kubectl exec backend -n lab16 -- \
  wget -qO- --timeout=3 http://database 2>/dev/null \
  && echo "✓ backend → database: allowed" \
  || echo "✗ backend → database: blocked (unexpected)"

kubectl exec attacker -n lab16 -- \
  wget -qO- --timeout=3 http://database 2>/dev/null \
  && echo "✗ attacker → database: allowed (unexpected)" \
  || echo "✓ attacker → database: blocked"

# ── Step 6: Allow frontend → backend traffic ──────────────────────────────────
# Apply the same deny-all + targeted-allow pattern to the backend tier.
kubectl apply -n lab16 -f - <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-deny-all
spec:
  podSelector:
    matchLabels:
      tier: backend
  policyTypes:
  - Ingress
  ingress: []
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-allow-frontend
spec:
  podSelector:
    matchLabels:
      tier: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: frontend
    ports:
    - protocol: TCP
      port: 8080
YAML

# Verify: frontend can reach backend, attacker cannot
kubectl exec frontend -n lab16 -- \
  wget -qO- --timeout=3 http://backend:8080 2>/dev/null \
  && echo "✓ frontend → backend: allowed" \
  || echo "✗ frontend → backend: blocked (unexpected)"

kubectl exec attacker -n lab16 -- \
  wget -qO- --timeout=3 http://backend:8080 2>/dev/null \
  && echo "✗ attacker → backend: allowed (unexpected)" \
  || echo "✓ attacker → backend: blocked"

# ── Step 7: Inspect all NetworkPolicy objects ─────────────────────────────────
kubectl get networkpolicies -n lab16
# Four policies: two deny-alls, two allow-specific

kubectl describe networkpolicy database-allow-backend -n lab16
# Shows: pod selector, ingress rules, allowed source labels and ports

# ── Step 8: Restrict egress — prevent pods from calling the internet ──────────
# By default pods can make outbound connections anywhere, including the
# internet. This policy restricts the backend to only talk to the database
# and the cluster's DNS server. The DNS allowance (port 53) is essential —
# without it, wget http://database would fail because DNS is blocked.
kubectl apply -n lab16 -f - <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-egress
spec:
  podSelector:
    matchLabels:
      tier: backend
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          tier: database
    ports:
    - protocol: TCP
      port: 80
  - ports:                    # Always allow DNS (UDP and TCP port 53)
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
YAML

# Verify backend can still reach database (allowed by egress policy)
kubectl exec backend -n lab16 -- \
  wget -qO- --timeout=3 http://database 2>/dev/null \
  && echo "✓ backend → database: allowed" \
  || echo "✗ backend → database: blocked (check egress policy)"

# Verify backend cannot reach the internet (blocked by egress policy)
kubectl exec backend -n lab16 -- \
  wget -qO- --timeout=3 http://example.com 2>/dev/null \
  && echo "✗ backend → internet: allowed (unexpected)" \
  || echo "✓ backend → internet: blocked"

# ── Step 9: Namespace-scoped policies ─────────────────────────────────────────
# You can also restrict traffic between namespaces. This policy allows
# ingress into lab16 only from pods within lab16 itself, or from namespaces
# labelled environment=production — blocking probes from other lab namespaces.
kubectl apply -n lab16 -f - <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: namespace-isolation
spec:
  podSelector: {}              # Applies to ALL pods in the namespace
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector: {}          # Any pod in the same namespace
    - namespaceSelector:
        matchLabels:
          environment: production   # Or from a labelled namespace
YAML

kubectl get networkpolicies -n lab16
# All five policies listed

# ── Step 10: Policy summary — what is enforced ───────────────────────────────
# After all policies are applied, kube-router enforces these rules:
#
#   From           To           Port    Result
#   ─────────────────────────────────────────────────────────────────────
#   internet       frontend     80      ✓ allowed (no ingress policy on frontend)
#   frontend       backend      8080    ✓ allowed (backend-allow-frontend)
#   backend        database     80      ✓ allowed (database-allow-backend)
#   attacker       database     80      ✗ blocked (database-deny-all)
#   attacker       backend      8080    ✗ blocked (backend-deny-all)
#   backend        internet     any     ✗ blocked (backend-egress)

# ── Step 11: Clean up ────────────────────────────────────────────────────────
kubectl delete namespace lab16


# ── Further Reading ───────────────────────────────────────────────────────────
# NetworkPolicy:
#   https://kubernetes.io/docs/concepts/services-networking/network-policies/
# NetworkPolicy recipes (deny-all, allow-same-namespace, etc.):
#   https://github.com/ahmetb/kubernetes-network-policy-recipes
# k3s network policy support (kube-router):
#   https://www.suse.com/c/rancher_blog/k3s-network-policy/
# Choosing a CNI plugin:
#   https://kubernetes.io/docs/concepts/cluster-administration/networking/

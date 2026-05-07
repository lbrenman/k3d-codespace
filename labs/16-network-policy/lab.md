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
# ── Important: CNI requirement ───────────────────────────────────────────────
# NetworkPolicy objects are enforced by the cluster's CNI (Container Network
# Interface) plugin — not by Kubernetes itself. If the CNI doesn't support
# NetworkPolicy, the YAML applies without error but has no effect.
#
# k3d's default CNI is Flannel (via k3s), which does NOT enforce NetworkPolicy.
# This lab demonstrates the API and mental model. In the enforcement steps you
# will apply policies, verify the objects exist, and observe what WOULD be
# blocked. A note marks each place where a NetworkPolicy-capable CNI (Calico,
# Cilium, Weave) would enforce the rule.
#
# To use a NetworkPolicy-enforcing setup with k3d:
#   k3d cluster create k8s-lab \
#     --k3s-arg "--flannel-backend=none@server:*" \
#     --k3s-arg "--disable=traefik@server:*"
#   # Then install Calico or Cilium manually
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
#               namespaceSelector, deny-all baseline, CNI plugins

# ── Step 1: Create namespace ──────────────────────────────────────────────────
kubectl create namespace lab16

# ── Step 2: Deploy three pods representing a 3-tier app ──────────────────────
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

# Attacker can reach the database — this is the problem we will fix
kubectl exec attacker -n lab16 -- \
  wget -qO- --timeout=3 http://database.lab16.svc.cluster.local 2>/dev/null \
  && echo "SUCCESS: attacker reached database" \
  || echo "FAILED: could not reach database"
# Expected before policy: SUCCESS

# We need a Service for DNS to work — add simple ClusterIP services
kubectl expose pod database -n lab16 --port=80 --name=database
kubectl expose pod backend   -n lab16 --port=8080 --name=backend
kubectl expose pod frontend  -n lab16 --port=80 --name=frontend

# Confirm the attacker can freely reach the database
kubectl exec attacker -n lab16 -- \
  wget -qO- --timeout=3 http://database 2>/dev/null \
  && echo "✓ Attacker reached database (no policy yet — expected)" \
  || echo "✗ Could not reach database"

# ── Step 4: Apply a deny-all ingress baseline to the database ─────────────────
# The foundation of network security: start with "deny everything" and
# then explicitly allow only what is needed. An empty podSelector ({}) with
# no ingress rules means: select this pod, allow zero ingress traffic.
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
  - Ingress             # Block all incoming connections
  ingress: []           # Empty list = deny all ingress
YAML

kubectl get networkpolicy -n lab16
# Shows the policy exists

# In a cluster with a NetworkPolicy-capable CNI (Calico, Cilium, Weave),
# the attacker would now be blocked. With k3d's default Flannel CNI,
# the policy exists but is not enforced — the connection still succeeds.
kubectl exec attacker -n lab16 -- \
  wget -qO- --timeout=3 http://database 2>/dev/null \
  && echo "reached database (Flannel does not enforce NetworkPolicy)" \
  || echo "blocked — NetworkPolicy is being enforced (Calico/Cilium CNI)"

# ── Step 5: Allow backend → database traffic ──────────────────────────────────
# Now add a specific allow rule on top of the deny-all baseline.
# Only pods with tier=backend can connect to the database on port 80.
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

# ── Step 6: Allow frontend → backend traffic ──────────────────────────────────
# Apply the same pattern to the backend: deny all, allow only from frontend.
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

# ── Step 7: Inspect all NetworkPolicy objects ─────────────────────────────────
kubectl get networkpolicies -n lab16
# Four policies: two deny-alls, two allow-specific

kubectl describe networkpolicy database-allow-backend -n lab16
# Shows: pod selector, ingress rules, allowed source labels and ports

# ── Step 8: Restrict egress — prevent pods from calling the internet ──────────
# By default pods can make outbound connections to anywhere — including the
# internet. The following policy restricts the backend to only talk to the
# database, and to the cluster's DNS server (required for name resolution).
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

# ── Step 9: Namespace-scoped policies ─────────────────────────────────────────
# You can also restrict traffic between namespaces. This policy allows
# traffic into lab16 only from other pods in lab16 (or pods in namespaces
# labelled environment=production). This prevents other namespaces in the
# cluster from probing your services.
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

# ── Step 10: Policy summary — what is allowed ─────────────────────────────────
# After all policies are applied:
#
#   From           To           Port    Result
#   ─────────────────────────────────────────────────────────────────────
#   internet       frontend     80      ✓ allowed (no ingress policy on frontend)
#   frontend       backend      8080    ✓ allowed (backend-allow-frontend)
#   backend        database     80      ✓ allowed (database-allow-backend)
#   attacker       database     80      ✗ blocked (database-deny-all)
#   attacker       backend      8080    ✗ blocked (backend-deny-all)
#   backend        internet     any     ✗ blocked (backend-egress restricts to db + DNS)
#
# Note: With k3d/Flannel these policies are not enforced. In a production
# cluster with Calico or Cilium, all ✗ rows would result in connection refused.

# ── Step 11: Test with a NetworkPolicy-aware CNI (reference) ─────────────────
# If you are running this lab with a NetworkPolicy-enforcing CNI:
#
# This should succeed (allowed by policy):
kubectl exec frontend -n lab16 -- \
  wget -qO- --timeout=3 http://backend:8080 2>/dev/null \
  && echo "frontend → backend: allowed" \
  || echo "frontend → backend: blocked"
#
# This should be blocked (no policy allows it):
kubectl exec attacker -n lab16 -- \
  wget -qO- --timeout=3 http://database 2>/dev/null \
  && echo "attacker → database: allowed (CNI not enforcing)" \
  || echo "attacker → database: BLOCKED (policy enforced)"

# ── Step 12: Clean up ────────────────────────────────────────────────────────
kubectl delete namespace lab16


# ── Further Reading ───────────────────────────────────────────────────────────
# NetworkPolicy:
#   https://kubernetes.io/docs/concepts/services-networking/network-policies/
# NetworkPolicy recipes (deny-all, allow-same-namespace, etc.):
#   https://github.com/ahmetb/kubernetes-network-policy-recipes
# Choosing a CNI plugin:
#   https://kubernetes.io/docs/concepts/cluster-administration/networking/
# Calico NetworkPolicy documentation:
#   https://docs.tigera.io/calico/latest/network-policy/
# Cilium NetworkPolicy documentation:
#   https://docs.cilium.io/en/stable/network/kubernetes/policy/

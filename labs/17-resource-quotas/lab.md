# Lab 17: Resource Quotas & LimitRange — Namespace Governance
# ─────────────────────────────────────────────────────────────────────────────
# Lab 07 covered per-pod resource requests and limits. But in a shared cluster
# used by multiple teams, you also need to cap total namespace consumption.
# Without guardrails:
#   - One team can use all cluster CPU/memory, starving everyone else
#   - A pod without a resources: block gets scheduled with no guarantee
#     and can claim whatever is free on a node
#   - A runaway deployment can create unlimited pods
#
# Two tools address this:
#   ResourceQuota   — caps total consumption within a namespace
#   LimitRange      — sets default and maximum per-pod limits
#
# HOW TO USE THIS LAB:
#   Copy and paste each command block into your terminal one step at a time.
#   Do not run this file as a script.
#
# What you will build:
#
#   ┌──────────────────────────────────────────────────────────────────┐
#   │  Namespace: lab17                                                │
#   │                                                                  │
#   │  ResourceQuota: team-quota                                      │
#   │    cpu:     4 cores total across all pods                       │
#   │    memory:  2Gi total across all pods                           │
#   │    pods:    10 maximum pods                                      │
#   │    secrets: 5 maximum secrets                                   │
#   │                                                                  │
#   │  LimitRange: default-limits                                     │
#   │    default request:  cpu=100m,  memory=128Mi  (injected if unset)│
#   │    default limit:    cpu=500m,  memory=256Mi  (injected if unset)│
#   │    max limit:        cpu=2,     memory=1Gi    (hard ceiling)    │
#   │                                                                  │
#   └──────────────────────────────────────────────────────────────────┘
#
# Key concepts: ResourceQuota, LimitRange, default requests/limits,
#               quota enforcement, namespace governance

# ── Step 1: Create namespace ──────────────────────────────────────────────────
kubectl create namespace lab17

# ── Step 2: Create a ResourceQuota ───────────────────────────────────────────
# ResourceQuota caps the total resources that can be consumed across all pods
# and objects in the namespace. Once a quota is set, every pod MUST declare
# requests and limits — Kubernetes rejects pods without them.
kubectl apply -n lab17 -f - <<YAML
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-quota
spec:
  hard:
    # Compute resources — sum across all running pods
    requests.cpu: "4"          # Total CPU requested by all pods combined
    requests.memory: 2Gi       # Total memory requested by all pods combined
    limits.cpu: "8"            # Total CPU limit across all pods combined
    limits.memory: 4Gi         # Total memory limit across all pods combined
    # Object count limits
    pods: "10"                 # Maximum number of pods in this namespace
    secrets: "5"               # Maximum number of Secrets
    services: "5"              # Maximum number of Services
    persistentvolumeclaims: "4" # Maximum number of PVCs
YAML

kubectl describe resourcequota team-quota -n lab17
# Shows "Hard" (the cap) and "Used" (current consumption) for each resource

# ── Step 3: Observe quota enforcement — pod without resources is rejected ─────
# With a ResourceQuota active, every pod must declare requests and limits.
# Without them, the API server rejects the pod immediately.
kubectl run no-resources \
  --image=nginx:alpine \
  -n lab17
# Expected error:
#   Error from server (Forbidden): pods "no-resources" is forbidden:
#   failed quota: team-quota: must specify limits.cpu,limits.memory,
#   requests.cpu,requests.memory

# ── Step 4: Create a LimitRange ──────────────────────────────────────────────
# LimitRange solves the rejection problem: it injects default requests and
# limits into any pod that doesn't declare them. It also sets hard maximums
# so no single pod can claim more than its share.
kubectl apply -n lab17 -f - <<YAML
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
spec:
  limits:
  - type: Container
    default:                   # Injected as limit if the container doesn't set one
      cpu: 500m
      memory: 256Mi
    defaultRequest:            # Injected as request if the container doesn't set one
      cpu: 100m
      memory: 128Mi
    max:                       # Hard ceiling — requests above this are rejected
      cpu: "2"
      memory: 1Gi
    min:                       # Hard floor — requests below this are rejected
      cpu: 50m
      memory: 64Mi
YAML

kubectl describe limitrange default-limits -n lab17
# Shows default, defaultRequest, max, and min for containers

# ── Step 5: LimitRange injects defaults silently ──────────────────────────────
# Now a pod without explicit resources is accepted — LimitRange fills them in.
kubectl run auto-defaults \
  --image=nginx:alpine \
  -n lab17
kubectl get pod auto-defaults -n lab17
# Running — no rejection this time

# Inspect what Kubernetes injected
kubectl get pod auto-defaults -n lab17 -o jsonpath='{.spec.containers[0].resources}' | jq .
# Shows: limits.cpu=500m, limits.memory=256Mi, requests.cpu=100m, requests.memory=128Mi
# These came from the LimitRange, not from the pod spec.

kubectl delete pod auto-defaults -n lab17

# ── Step 6: Check current quota usage ────────────────────────────────────────
kubectl describe resourcequota team-quota -n lab17
# Used column now shows 0 (pod was deleted). Watch how it changes in next steps.

# ── Step 7: Deploy a workload that consumes quota ─────────────────────────────
kubectl apply -n lab17 -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        resources:
          requests:
            cpu: 200m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi
YAML

kubectl get pods -n lab17 -w
# Press Ctrl+C once all 3 pods are Running

# See the quota consumption update
kubectl describe resourcequota team-quota -n lab17
# Used: requests.cpu=600m (3 x 200m), requests.memory=384Mi (3 x 128Mi), pods=3/10

# ── Step 8: Hit the pod count limit ───────────────────────────────────────────
# Scale beyond the quota limit to observe the enforcement
kubectl scale deployment web -n lab17 --replicas=12
kubectl get pods -n lab17
# Only 10 pods will exist (the quota hard limit)

kubectl get replicaset -n lab17
kubectl describe replicaset -n lab17 -l app=web | grep -A5 "Conditions\|Warning"
# Events will show: "exceeded quota: team-quota, requested: pods=1, used: pods=10, limited: pods=10"

# Scale back down
kubectl scale deployment web -n lab17 --replicas=3

# ── Step 9: Attempt to exceed the memory limit ────────────────────────────────
# Try to deploy a pod requesting more memory than the LimitRange maximum
kubectl apply -n lab17 -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: memory-hog
spec:
  containers:
  - name: app
    image: nginx:alpine
    resources:
      requests:
        memory: 2Gi    # Exceeds LimitRange max of 1Gi
      limits:
        memory: 2Gi
YAML
# Expected error:
#   pods "memory-hog" is forbidden: maximum memory usage per Container is 1Gi,
#   but limit is 2Gi

# ── Step 10: Observe quota with multiple object types ─────────────────────────
# Create a few Secrets to approach the Secrets quota
kubectl create secret generic secret-1 --from-literal=key=val1 -n lab17
kubectl create secret generic secret-2 --from-literal=key=val2 -n lab17
kubectl create secret generic secret-3 --from-literal=key=val3 -n lab17

kubectl describe resourcequota team-quota -n lab17
# secrets: 3/5

# Try to exceed the quota
kubectl create secret generic secret-4 --from-literal=key=val4 -n lab17
kubectl create secret generic secret-5 --from-literal=key=val5 -n lab17
kubectl create secret generic secret-6 --from-literal=key=val6 -n lab17
# The last one will fail: "exceeded quota: team-quota, requested: secrets=1,
# used: secrets=5, limited: secrets=5"

# ── Step 11: Multi-team pattern ───────────────────────────────────────────────
# In a real cluster, each team gets its own namespace with its own quota.
# Here is a minimal example of two teams with different resource allocations:
kubectl create namespace team-alpha
kubectl create namespace team-beta

kubectl apply -f - <<YAML
apiVersion: v1
kind: ResourceQuota
metadata:
  name: alpha-quota
  namespace: team-alpha
spec:
  hard:
    requests.cpu: "8"
    requests.memory: 8Gi
    pods: "20"
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: beta-quota
  namespace: team-beta
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 2Gi
    pods: "5"
YAML

kubectl describe resourcequota -n team-alpha
kubectl describe resourcequota -n team-beta
# Each team has independent limits — one team cannot consume the other's allocation

kubectl delete namespace team-alpha team-beta

# ── Step 12: Quota + LimitRange — the full governance pattern ─────────────────
#
# The two objects work together:
#
#   LimitRange (per container)         ResourceQuota (per namespace)
#   ─────────────────────────          ─────────────────────────────
#   Sets default requests/limits  →   Allows pods to be accepted
#   Sets max per container         →   Caps total namespace usage
#   Enforced at admission time         Enforced at admission time
#
# Without LimitRange: every pod must declare resources explicitly
#                     (or the quota rejects it)
# Without ResourceQuota: teams can consume unlimited cluster resources
# With both: you get automatic defaults AND hard namespace caps

# ── Step 13: Clean up ────────────────────────────────────────────────────────
kubectl delete namespace lab17


# ── Further Reading ───────────────────────────────────────────────────────────
# Resource Quotas:
#   https://kubernetes.io/docs/concepts/policy/resource-quotas/
# Limit Ranges:
#   https://kubernetes.io/docs/concepts/policy/limit-range/
# Configure default memory requests and limits for a namespace:
#   https://kubernetes.io/docs/tasks/administer-cluster/manage-resources/memory-default-namespace/
# Configure default CPU requests and limits for a namespace:
#   https://kubernetes.io/docs/tasks/administer-cluster/manage-resources/cpu-default-namespace/

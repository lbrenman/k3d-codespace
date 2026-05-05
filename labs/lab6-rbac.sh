# Lab 6: RBAC — Roles, ServiceAccounts & Permissions
# ─────────────────────────────────────────────────────────────────────────────
# RBAC (Role-Based Access Control) is how Kubernetes controls who (or what)
# can do what to which resources. By default, pods have almost no permissions.
# RBAC lets you grant fine-grained access — for example, allowing a pod to
# list other pods, or a CI system to deploy to a specific namespace.
#
# HOW TO USE THIS LAB:
#   Copy and paste each command block into your terminal one step at a time.
#   Do not run this file as a script.
#
# The four RBAC building blocks:
#
#   ┌──────────────────────────────────────────────────────────────────┐
#   │                                                                  │
#   │  ServiceAccount — the identity of a pod (like a user account    │
#   │                   but for workloads, not humans)                │
#   │                                                                  │
#   │  Role            — a set of permissions within one namespace    │
#   │  ClusterRole     — a set of permissions across all namespaces   │
#   │                                                                  │
#   │  RoleBinding     — grants a Role to a ServiceAccount            │
#   │  ClusterRoleBinding — grants a ClusterRole to a ServiceAccount  │
#   │                                                                  │
#   │  Flow:                                                           │
#   │  ServiceAccount ──► RoleBinding ──► Role ──► permissions        │
#   │                                                                  │
#   └──────────────────────────────────────────────────────────────────┘
#
# What you will build:
#
#   ┌──────────────────────────────────────────────────────────────────┐
#   │  Namespace: lab6                                                 │
#   │                                                                  │
#   │  ServiceAccount: pod-reader-sa                                  │
#   │         │                                                        │
#   │         │ bound via RoleBinding                                  │
#   │         ▼                                                        │
#   │  Role: pod-reader                                               │
#   │    - get, list, watch pods                                      │
#   │    - get, list services                                         │
#   │                                                                  │
#   │  Pod: rbac-demo (runs as pod-reader-sa)                         │
#   │    ✅ can list pods in lab6                                      │
#   │    ❌ cannot list pods in other namespaces                       │
#   │    ❌ cannot create or delete pods                               │
#   └──────────────────────────────────────────────────────────────────┘
#
# Key concepts: ServiceAccount, Role, RoleBinding, ClusterRole,
#               ClusterRoleBinding, least privilege, kubectl auth can-i

# ── Step 1: Create namespace ──────────────────────────────────────────────────
kubectl create namespace lab6

# ── Step 2: Observe the default ServiceAccount ────────────────────────────────
# Every namespace gets a "default" ServiceAccount automatically.
# Every pod uses it unless you specify otherwise.
kubectl get serviceaccounts -n lab6
kubectl describe serviceaccount default -n lab6

# Check what the default SA can do — almost nothing by default
kubectl auth can-i list pods --as=system:serviceaccount:lab6:default -n lab6
# Expected: no

# ── Step 3: Create a custom ServiceAccount ────────────────────────────────────
kubectl create serviceaccount pod-reader-sa -n lab6
kubectl get serviceaccounts -n lab6

# ── Step 4: Create a Role with specific permissions ───────────────────────────
# This Role only grants read access to pods and services — nothing else.
# Principle of least privilege: grant only what is needed.
kubectl apply -n lab6 -f - <<YAML
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
rules:
- apiGroups: [""]          # "" means the core API group
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["services"]
  verbs: ["get", "list"]
YAML

kubectl describe role pod-reader -n lab6

# ── Step 5: Bind the Role to the ServiceAccount ───────────────────────────────
kubectl apply -n lab6 -f - <<YAML
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pod-reader-binding
subjects:
- kind: ServiceAccount
  name: pod-reader-sa
  namespace: lab6
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
YAML

kubectl describe rolebinding pod-reader-binding -n lab6

# ── Step 6: Verify permissions with kubectl auth can-i ────────────────────────
# This command lets you check permissions without actually running an action

# Should be allowed (granted in the Role)
kubectl auth can-i list pods \
  --as=system:serviceaccount:lab6:pod-reader-sa -n lab6
# Expected: yes

kubectl auth can-i get services \
  --as=system:serviceaccount:lab6:pod-reader-sa -n lab6
# Expected: yes

# Should be denied (not in the Role)
kubectl auth can-i delete pods \
  --as=system:serviceaccount:lab6:pod-reader-sa -n lab6
# Expected: no

kubectl auth can-i create deployments \
  --as=system:serviceaccount:lab6:pod-reader-sa -n lab6
# Expected: no

# Cross-namespace check — Role only applies within lab6
kubectl auth can-i list pods \
  --as=system:serviceaccount:lab6:pod-reader-sa -n kube-system
# Expected: no

# ── Step 7: Deploy a pod that uses the ServiceAccount ────────────────────────
# This pod runs kubectl inside the container using the mounted ServiceAccount
# token — demonstrating that pods can interact with the K8s API using RBAC.
kubectl apply -n lab6 -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: rbac-demo
spec:
  serviceAccountName: pod-reader-sa   # Use our custom SA, not default
  containers:
  - name: kubectl
    image: bitnami/kubectl:latest
    command:
    - /bin/sh
    - -c
    - |
      echo "=== Listing pods in lab6 (should work) ==="
      kubectl get pods -n lab6
      echo ""
      echo "=== Trying to list pods in kube-system (should fail) ==="
      kubectl get pods -n kube-system || echo "Permission denied as expected"
      echo ""
      echo "=== Trying to delete a pod (should fail) ==="
      kubectl delete pod rbac-demo -n lab6 || echo "Permission denied as expected"
      echo ""
      echo "=== Done ==="
      sleep 3600
YAML

kubectl get pod rbac-demo -n lab6 -w
# Press Ctrl+C once Running

# ── Step 8: Read the pod output ───────────────────────────────────────────────
kubectl logs rbac-demo -n lab6
# You should see:
#   ✅ pod list succeeds in lab6
#   ❌ pod list fails in kube-system
#   ❌ delete fails

# ── Step 9: ClusterRole and ClusterRoleBinding ────────────────────────────────
# A Role is namespace-scoped. A ClusterRole works across all namespaces.
# ClusterRoles are also used for non-namespaced resources like Nodes.

# Create a ClusterRole that can read nodes (nodes are cluster-scoped)
kubectl apply -f - <<YAML
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: node-reader
rules:
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["get", "list", "watch"]
YAML

# Bind it to the same ServiceAccount
kubectl apply -f - <<YAML
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: node-reader-binding
subjects:
- kind: ServiceAccount
  name: pod-reader-sa
  namespace: lab6
roleRef:
  kind: ClusterRole
  name: node-reader
  apiGroup: rbac.authorization.k8s.io
YAML

# Now the SA can list nodes
kubectl auth can-i list nodes \
  --as=system:serviceaccount:lab6:pod-reader-sa
# Expected: yes

# ── Step 10: View all RBAC resources in the namespace ────────────────────────
kubectl get roles,rolebindings -n lab6
kubectl get clusterroles,clusterrolebindings | grep node-reader

# ── Step 11: Clean up ────────────────────────────────────────────────────────
kubectl delete namespace lab6
kubectl delete clusterrole node-reader
kubectl delete clusterrolebinding node-reader-binding

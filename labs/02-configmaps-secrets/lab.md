# Lab 02: ConfigMaps, Secrets & Environment Variables
# ─────────────────────────────────────────────────────────────────────────────
#
# Learn how Kubernetes separates configuration from container images using
# ConfigMaps (non-sensitive config) and Secrets (sensitive data).
# This is a core 12-factor app principle — config lives outside the image.
#
# HOW TO USE THIS LAB:
#   Copy and paste each command block into your terminal one step at a time.
#   Do not run this file as a script.
#
# What you will build:
#
#   ┌──────────────────────────────────────────────────────────────┐
#   │  Namespace: lab02                                             │
#   │                                                              │
#   │  ┌─────────────────────┐   ┌──────────────────────────┐    │
#   │  │ ConfigMap: app-config│   │ Secret: app-secret        │    │
#   │  │                     │   │                           │    │
#   │  │ APP_ENV=production  │   │ DB_PASSWORD=***           │    │
#   │  │ LOG_LEVEL=info      │   │ API_KEY=***               │    │
#   │  │ welcome.txt (file)  │   │                           │    │
#   │  └──────┬──────────────┘   └─────────────┬─────────────┘    │
#   │         │  env vars + volume              │  env vars        │
#   │         └──────────────┬──────────────────┘                  │
#   │                        ▼                                     │
#   │         ┌──────────────────────────────┐                     │
#   │         │  Deployment: config-demo     │                     │
#   │         │  (busybox container)         │                     │
#   │         │                              │                     │
#   │         │  env: APP_ENV, LOG_LEVEL,    │                     │
#   │         │       DB_PASSWORD            │                     │
#   │         │  vol: /config/welcome.txt    │                     │
#   │         └──────────────────────────────┘                     │
#   └──────────────────────────────────────────────────────────────┘
#
# Key concepts: ConfigMap, Secret, env vars, volume mounts, base64 encoding

# ── Step 1: Create namespace ──────────────────────────────────────────────────
kubectl create namespace lab02

# ── Step 2: Create a ConfigMap ────────────────────────────────────────────────
kubectl apply -n lab02 -f - <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  APP_ENV: "production"
  LOG_LEVEL: "info"
  MAX_CONNECTIONS: "100"
  welcome.txt: |
    Welcome to the K8s lab!
    This message comes from a ConfigMap volume mount.
YAML

kubectl describe configmap app-config -n lab02

# ── Step 3: Create a Secret ───────────────────────────────────────────────────
# Secrets are base64-encoded (not encrypted by default, but access-controlled).
# Never store plaintext passwords in ConfigMaps — always use Secrets.
kubectl create secret generic app-secret \
  --from-literal=DB_PASSWORD=supersecret123 \
  --from-literal=API_KEY=myapikey456 \
  -n lab02

# Why base64? Kubernetes stores Secrets as JSON in etcd. Base64 lets arbitrary
# binary data (TLS keys, certificates, binary blobs) survive the JSON encoding.
# It is NOT security — anyone with kubectl get secret can decode it instantly.
# Real security comes from:
#   - RBAC: restrict which users/serviceaccounts can read Secrets
#   - Encryption at rest: enable etcd encryption in your cluster config
#   - External secret stores: tools like Sealed Secrets or HashiCorp Vault
#     store the real secret outside the cluster and inject it at runtime.

kubectl describe secret app-secret -n lab02
# Note: values are hidden in describe output. Decode one manually:
kubectl get secret app-secret -n lab02 -o jsonpath='{.data.DB_PASSWORD}' | base64 --decode
echo ""

# ── Step 4: Deploy an app that uses both ─────────────────────────────────────
kubectl apply -n lab02 -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: config-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: config-demo
  template:
    metadata:
      labels:
        app: config-demo
    spec:
      containers:
      - name: app
        image: busybox:latest
        command: ["sh", "-c", "while true; do echo ENV=\$APP_ENV LOG=\$LOG_LEVEL; cat /config/welcome.txt; sleep 10; done"]
        env:
        # Individual keys from ConfigMap
        - name: APP_ENV
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: APP_ENV
        - name: LOG_LEVEL
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: LOG_LEVEL
        # Individual keys from Secret
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: app-secret
              key: DB_PASSWORD
        volumeMounts:
        - name: config-volume
          mountPath: /config
      volumes:
      - name: config-volume
        configMap:
          name: app-config
          items:
          - key: welcome.txt
            path: welcome.txt
YAML

# ── Step 5: Inspect the running pod ──────────────────────────────────────────
POD=$(kubectl get pod -n lab02 -l app=config-demo -o jsonpath='{.items[0].metadata.name}')

# View env vars inside the pod
kubectl exec -n lab02 $POD -- env | grep -E "APP_ENV|LOG_LEVEL|DB_PASSWORD"

# View the mounted config file
kubectl exec -n lab02 $POD -- cat /config/welcome.txt

# View logs
kubectl logs -n lab02 $POD

# ── Step 6a: Update a volume-mounted file (live reload) ───────────────────────
# Volume-mounted ConfigMap files update automatically inside the pod — no
# restart needed. Kubernetes re-syncs them roughly every 60 seconds.

kubectl patch configmap app-config -n lab02 \
  --patch '{"data":{"welcome.txt":"Welcome to the K8s lab!\nThis line was UPDATED via kubectl patch.\n"}}'

# Run this command every 15 seconds until you see "UPDATED" in the output.
# It usually propagates within 60 seconds.
kubectl exec -n lab02 $POD -- cat /config/welcome.txt
# Initially: "Welcome to the K8s lab! / This message comes from a ConfigMap volume mount."
# After ~60s: "Welcome to the K8s lab! / This line was UPDATED via kubectl patch."

# ── Step 6b: Update an env var (requires pod restart) ─────────────────────────
# Environment variables are injected at pod startup and never updated in place.
# Even if you patch the ConfigMap, the running pod keeps the old value until
# it is restarted.

kubectl patch configmap app-config -n lab02 \
  --patch '{"data":{"LOG_LEVEL":"debug"}}'

# Confirm the ConfigMap now holds "debug"
kubectl get configmap app-config -n lab02 -o jsonpath='{.data.LOG_LEVEL}'
echo ""

# But the running pod still sees the OLD value — env vars are pod-bound
kubectl exec -n lab02 $POD -- env | grep LOG_LEVEL
# Expected: LOG_LEVEL=info   ← the old value; the patch has not taken effect

# Restart the pod to pick up the new value
kubectl rollout restart deployment/config-demo -n lab02
kubectl get pods -n lab02 -w
# Press Ctrl+C once the new pod shows Running

# Re-assign POD to the new pod name
POD=$(kubectl get pod -n lab02 -l app=config-demo -o jsonpath='{.items[0].metadata.name}')

# Now the env var reflects the updated value
kubectl exec -n lab02 $POD -- env | grep LOG_LEVEL
# Expected: LOG_LEVEL=debug

# ── Summary: how ConfigMap changes propagate ──────────────────────────────────
#
#   Update type           Propagation            How to verify
#   ──────────────────────────────────────────────────────────────────
#   Volume-mounted file   ~60s (automatic)       cat /config/welcome.txt
#   Environment variable  Never (pod-bound)      Requires rollout restart

# ── Step 7: Clean up ─────────────────────────────────────────────────────────
kubectl delete namespace lab02


# ── Further Reading ───────────────────────────────────────────────────────────
# ConfigMaps:
#   https://kubernetes.io/docs/concepts/configuration/configmap/
# Secrets:
#   https://kubernetes.io/docs/concepts/configuration/secret/
# Environment variables from ConfigMaps and Secrets:
#   https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/
# Encrypting Secret data at rest:
#   https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/
# 12-Factor App config principles:
#   https://12factor.net/config

# Lab 02: ConfigMaps, Secrets & Environment Variables
# ─────────────────────────────────────────────────────────────────────────────
# Learn how Kubernetes separates configuration from container images using
# ConfigMaps (non-sensitive config) and Secrets (sensitive data).
# This is a core 12-factor app principle — config lives outside the image.
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

# ── Step 6: Update ConfigMap and observe ─────────────────────────────────────
kubectl patch configmap app-config -n lab02 \
  --patch '{"data":{"LOG_LEVEL":"debug"}}'

# Check the env var — it still shows "info" even after the patch
# Env vars are injected at pod start and do NOT update live
kubectl exec -n lab02 $POD -- env | grep LOG_LEVEL
# Expected: LOG_LEVEL=info  (unchanged)

# The volume-mounted file DOES update automatically (~60s)
# Run this repeatedly until you see the change:
kubectl exec -n lab02 $POD -- cat /config/welcome.txt
# (keep running every 15s — after ~60s the content will refresh)

# Once you've observed the volume mount update, restart the pod
# to pick up the env var change:
kubectl rollout restart deployment/config-demo -n lab02
kubectl get pods -n lab02 -w
# Press Ctrl+C once the new pod shows Running

# Re-assign POD to the new pod name
POD=$(kubectl get pod -n lab02 -l app=config-demo -o jsonpath='{.items[0].metadata.name}')

# Now the env var reflects the updated ConfigMap value
kubectl exec -n lab02 $POD -- env | grep LOG_LEVEL
# Expected: LOG_LEVEL=debug

# ── Step 7: Clean up ─────────────────────────────────────────────────────────
kubectl delete namespace lab02


# ── Further Reading ───────────────────────────────────────────────────────────
# ConfigMaps:
#   https://kubernetes.io/docs/concepts/configuration/configmap/
# Secrets:
#   https://kubernetes.io/docs/concepts/configuration/secret/
# Environment variables from ConfigMaps and Secrets:
#   https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/
# 12-Factor App config principles:
#   https://12factor.net/config

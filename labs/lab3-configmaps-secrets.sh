# Lab 3: ConfigMaps, Secrets & Environment Variables
# ─────────────────────────────────────────────────────────────────────────────
# Learn how Kubernetes separates configuration from container images using
# ConfigMaps (non-sensitive config) and Secrets (sensitive data).

# ── Step 1: Create namespace ──────────────────────────────────────────────────
kubectl create namespace lab3

# ── Step 2: Create a ConfigMap ────────────────────────────────────────────────
kubectl apply -n lab3 -f - <<EOF
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
EOF

kubectl describe configmap app-config -n lab3

# ── Step 3: Create a Secret ───────────────────────────────────────────────────
# Secrets are base64-encoded (not encrypted by default, but access-controlled)
kubectl create secret generic app-secret \
  --from-literal=DB_PASSWORD=supersecret123 \
  --from-literal=API_KEY=myapikey456 \
  -n lab3

kubectl describe secret app-secret -n lab3
# Note: values are hidden. Decode one manually:
kubectl get secret app-secret -n lab3 -o jsonpath='{.data.DB_PASSWORD}' | base64 --decode
echo ""

# ── Step 4: Deploy an app that uses both ─────────────────────────────────────
kubectl apply -n lab3 -f - <<EOF
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
EOF

# ── Step 5: Inspect the running pod ──────────────────────────────────────────
POD=$(kubectl get pod -n lab3 -l app=config-demo -o jsonpath='{.items[0].metadata.name}')

# View env vars inside the pod
kubectl exec -n lab3 $POD -- env | grep -E "APP_ENV|LOG_LEVEL|DB_PASSWORD"

# View the mounted config file
kubectl exec -n lab3 $POD -- cat /config/welcome.txt

# View logs
kubectl logs -n lab3 $POD

# ── Step 6: Update ConfigMap and observe ─────────────────────────────────────
kubectl patch configmap app-config -n lab3 \
  --patch '{"data":{"LOG_LEVEL":"debug"}}'
# Note: env var changes require pod restart; volume mounts update automatically (~1 min)

# ── Step 7: Clean up ─────────────────────────────────────────────────────────
kubectl delete namespace lab3

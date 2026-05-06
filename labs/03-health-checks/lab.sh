# Lab 03: Health Checks & Self-Healing — Probes
# ─────────────────────────────────────────────────────────────────────────────
# Kubernetes uses three types of probes to monitor container health and decide
# when to restart a pod, stop sending it traffic, or delay starting it.
# You may have noticed these in Lab 05's products-api and users-api —
# this lab explores them in depth so you understand exactly what each one does.
#
# HOW TO USE THIS LAB:
#   Copy and paste each command block into your terminal one step at a time.
#   Do not run this file as a script.
#
# The three probe types:
#
#   ┌─────────────────────────────────────────────────────────────────┐
#   │                                                                 │
#   │  STARTUP PROBE                                                  │
#   │  "Is the app done initializing?"                                │
#   │  Runs first. Liveness and readiness are paused until it passes.│
#   │  Failure → container is killed and restarted.                  │
#   │  Use for: slow-starting apps (JVM warmup, DB migrations)       │
#   │                          │                                      │
#   │                          ▼ (once startup passes)               │
#   │  LIVENESS PROBE                                                 │
#   │  "Is the app still alive and not stuck?"                        │
#   │  Runs continuously for the life of the pod.                    │
#   │  Failure → container is killed and restarted.                  │
#   │  Use for: detecting deadlocks, infinite loops, hung processes   │
#   │                                                                 │
#   │  READINESS PROBE                                                │
#   │  "Is the app ready to receive traffic?"                         │
#   │  Runs continuously for the life of the pod.                    │
#   │  Failure → pod removed from Service endpoints (no traffic sent)│
#   │            Pod is NOT restarted — it stays alive, just idle.   │
#   │  Use for: waiting for cache warmup, downstream dependencies     │
#   │                                                                 │
#   └─────────────────────────────────────────────────────────────────┘
#
# Probe mechanisms (how the check is performed):
#   httpGet   — HTTP GET request, success if status 200-399
#   exec      — runs a command inside the container, success if exit code 0
#   tcpSocket — TCP connection attempt, success if port accepts connection
#
# Key concepts: livenessProbe, readinessProbe, startupProbe,
#               initialDelaySeconds, periodSeconds, failureThreshold,
#               RESTARTS counter, Service endpoints

# ── Step 1: Create namespace ──────────────────────────────────────────────────
kubectl create namespace lab03

# ════════════════════════════════════════════════════════════════════════════
# SECTION A: Liveness Probe — automatic restart on failure
# ════════════════════════════════════════════════════════════════════════════
#
# This pod creates a file on startup then deletes it after 30 seconds.
# The liveness probe checks for that file every 5 seconds.
# When the file disappears the probe fails and Kubernetes restarts the container.

# ── Step 2: Deploy a pod with a liveness probe ───────────────────────────────
kubectl apply -n lab03 -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: liveness-demo
spec:
  containers:
  - name: app
    image: busybox:latest
    command:
    - /bin/sh
    - -c
    - |
      touch /tmp/healthy
      echo "Pod started — health file created"
      sleep 30
      echo "Removing health file — liveness probe will now fail"
      rm /tmp/healthy
      sleep 600
    livenessProbe:
      exec:
        command: [cat, /tmp/healthy]
      initialDelaySeconds: 5    # Wait 5s after container starts before first check
      periodSeconds: 5           # Check every 5s
      failureThreshold: 3        # Restart after 3 consecutive failures (~15s)
YAML

# ── Step 3: Watch the liveness probe fail and trigger a restart ───────────────
kubectl get pod liveness-demo -n lab03 -w
# After ~45s you will see RESTARTS go from 0 → 1
# The pod keeps running — Kubernetes restarts just the container, not the pod
# Press Ctrl+C

# Inspect the events to see what happened
kubectl describe pod liveness-demo -n lab03
# Look for "Liveness probe failed" and "Killing" in the Events section

# ── Step 4: Clean up section A ───────────────────────────────────────────────
kubectl delete pod liveness-demo -n lab03

# ════════════════════════════════════════════════════════════════════════════
# SECTION B: Readiness Probe — traffic control without restart
# ════════════════════════════════════════════════════════════════════════════
#
# Two nginx pods sit behind a Service. We manually break the readiness probe
# on one pod and watch it drop out of the load balancer — while the other
# continues serving traffic. The container is never restarted.

# ── Step 5: Deploy two pods with a readiness probe ───────────────────────────
kubectl apply -n lab03 -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: readiness-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: readiness-demo
  template:
    metadata:
      labels:
        app: readiness-demo
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 3
          periodSeconds: 5
          failureThreshold: 2
---
apiVersion: v1
kind: Service
metadata:
  name: readiness-demo
spec:
  selector:
    app: readiness-demo
  ports:
  - port: 80
YAML

kubectl get pods -n lab03 -w
# Press Ctrl+C once both pods show READY 1/1

# ── Step 6: Confirm both pods are in the Service endpoints ────────────────────
kubectl get endpoints readiness-demo -n lab03
# Two IP addresses listed — both pods receiving traffic

# ── Step 7: Break the readiness probe on one pod ─────────────────────────────
POD1=$(kubectl get pods -n lab03 -l app=readiness-demo -o jsonpath='{.items[0].metadata.name}')
echo "Targeting: $POD1"

# Remove nginx's index page — the readiness probe GET / will now fail
kubectl exec -n lab03 $POD1 -- rm /usr/share/nginx/html/index.html

# ── Step 8: Watch the pod become unready ─────────────────────────────────────
kubectl get pods -n lab03 -w
# READY changes from 1/1 to 0/1 — RESTARTS stays at 0
# Press Ctrl+C

kubectl get endpoints readiness-demo -n lab03
# Only one IP now — unready pod is excluded from traffic

# ── Step 9: Restore the pod ───────────────────────────────────────────────────
kubectl exec -n lab03 $POD1 -- sh -c "echo 'restored' > /usr/share/nginx/html/index.html"

kubectl get pods -n lab03 -w
# READY returns to 1/1 — pod rejoins the load balancer
# Press Ctrl+C

kubectl get endpoints readiness-demo -n lab03
# Both IPs are back

# ── Step 10: Clean up section B ──────────────────────────────────────────────
kubectl delete deployment readiness-demo -n lab03
kubectl delete service readiness-demo -n lab03

# ════════════════════════════════════════════════════════════════════════════
# SECTION C: Startup Probe — protecting slow-starting containers
# ════════════════════════════════════════════════════════════════════════════
#
# Without a startup probe, a slow-starting app might fail its liveness probe
# before it has finished initializing — causing a restart loop that prevents
# it from ever running. The startup probe pauses liveness and readiness checks
# until the app signals it is ready.

# ── Step 11: Deploy a pod that takes 20 seconds to initialize ────────────────
kubectl apply -n lab03 -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: startup-demo
spec:
  containers:
  - name: app
    image: busybox:latest
    command:
    - /bin/sh
    - -c
    - |
      echo "Simulating slow startup — waiting 20 seconds..."
      sleep 20
      echo "Initialization complete"
      touch /tmp/ready
      sleep 600
    startupProbe:
      exec:
        command: [cat, /tmp/ready]
      initialDelaySeconds: 5
      periodSeconds: 5
      failureThreshold: 10    # 10 attempts x 5s = up to 50s allowed for startup
    livenessProbe:
      exec:
        command: [cat, /tmp/ready]
      periodSeconds: 10
      failureThreshold: 3
YAML

# ── Step 12: Watch startup probe succeed before liveness takes over ───────────
kubectl get pod startup-demo -n lab03 -w
# Pod stays in Running (not Ready) for ~20s while startup probe checks
# Once /tmp/ready exists startup succeeds and liveness begins
# RESTARTS should stay at 0 throughout
# Press Ctrl+C

kubectl describe pod startup-demo -n lab03
# Events show startup probe activity before liveness kicks in

# ── Step 13: Clean up section C ──────────────────────────────────────────────
kubectl delete pod startup-demo -n lab03

# ════════════════════════════════════════════════════════════════════════════
# SECTION D: Production pattern — all three probes together
# ════════════════════════════════════════════════════════════════════════════
#
# This is the same pattern used in Lab 4's products-api and users-api.
# Now that you understand each probe individually, you can see how they
# work together in a real deployment.

# ── Step 14: Deploy with all three probes ────────────────────────────────────
kubectl apply -n lab03 -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: production-pattern
spec:
  replicas: 2
  selector:
    matchLabels:
      app: production-pattern
  template:
    metadata:
      labels:
        app: production-pattern
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 50m
            memory: 32Mi
          limits:
            cpu: 200m
            memory: 64Mi
        startupProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 2
          periodSeconds: 3
          failureThreshold: 10    # Up to 30s for startup
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 3
          periodSeconds: 5
          failureThreshold: 2     # Remove from load balancer after 2 failures
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 10
          periodSeconds: 10
          failureThreshold: 3     # Restart after 3 consecutive failures
YAML

kubectl get pods -n lab03 -w
# Press Ctrl+C once both pods show READY 1/1

# Inspect the probe config on a running pod
kubectl describe pod -n lab03 -l app=production-pattern | grep -A8 "Startup\|Liveness\|Readiness"

# ── Step 15: Clean up ────────────────────────────────────────────────────────
kubectl delete namespace lab03

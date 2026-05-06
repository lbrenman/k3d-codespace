# Lab 08: Rolling Updates & Zero-Downtime Deploys
# ─────────────────────────────────────────────────────────────────────────────
# In production you need to update your application without dropping a single
# request. Kubernetes handles this with rolling updates — gradually replacing
# old pods with new ones while keeping the service continuously available.
# This lab shows you how it works, how to control it, and how to recover
# when a bad deployment reaches production.
#
# HOW TO USE THIS LAB:
#   Copy and paste each command block into your terminal one step at a time.
#   Do not run this file as a script.
#
# What you will build:
#
#   ┌──────────────────────────────────────────────────────────────────┐
#   │  Namespace: lab08                                                │
#   │                                                                  │
#   │  Deployment: web-app  (4 replicas)                              │
#   │                                                                  │
#   │  v1 (initial)     v2 (good update)     v3 (bad image)           │
#   │  ┌──┐┌──┐┌──┐┌──┐  rolling replace     ┌──┐┌──┐┌──┐┌──┐       │
#   │  │v1││v1││v1││v1│  ──────────────►     │v3││v3│ ✗  ✗          │
#   │  └──┘└──┘└──┘└──┘                      └──┘└──┘                │
#   │                                         rollback ◄──────────    │
#   │  maxSurge: 1        At most 1 extra pod during update           │
#   │  maxUnavailable: 1  At most 1 pod down at any time              │
#   │                                                                  │
#   └──────────────────────────────────────────────────────────────────┘
#
# Rolling update strategy explained:
#
#   maxSurge:       how many extra pods above desired count can exist during update
#   maxUnavailable: how many pods below desired count can be unavailable during update
#
#   With 4 replicas, maxSurge=1, maxUnavailable=1:
#     - Up to 5 pods exist at once (4 + 1 surge)
#     - At least 3 pods are always running (4 - 1 unavailable)
#     - Service never drops below 75% capacity during the update
#
# Key concepts: RollingUpdate strategy, maxSurge, maxUnavailable,
#               kubectl rollout status, kubectl rollout history,
#               kubectl rollout undo, revision annotations

# ── Step 1: Create namespace ──────────────────────────────────────────────────
kubectl create namespace lab08

# ── Step 2: Deploy v1 of the application ─────────────────────────────────────
# We use hashicorp/http-echo — a lightweight image that serves whatever text
# you pass via -text. Each version bakes the version string into the container
# args, so rollbacks are genuinely visible in the traffic stream.
kubectl apply -n lab08 -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
  annotations:
    kubernetes.io/change-cause: "Initial release v1.0.0"
spec:
  replicas: 4
  selector:
    matchLabels:
      app: web-app
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1           # Allow 1 extra pod during update
      maxUnavailable: 1     # Allow 1 pod to be unavailable during update
  template:
    metadata:
      labels:
        app: web-app
    spec:
      containers:
      - name: web
        image: hashicorp/http-echo:latest
        args:
        - "-text=Version 1 — v1.0.0"
        ports:
        - containerPort: 5678
        readinessProbe:
          httpGet:
            path: /
            port: 5678
          initialDelaySeconds: 3
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: web-svc
spec:
  selector:
    app: web-app
  ports:
  - port: 80
    targetPort: 5678
YAML

kubectl get pods -n lab08 -w
# Press Ctrl+C once all 4 pods show READY 1/1

# ── Step 3: Open a continuous traffic stream ──────────────────────────────────
# Open a NEW terminal tab and run this — it sends one request per second
# and prints the response. You will watch it stay live through the update.
kubectl run traffic \
  --image=busybox:latest \
  --restart=Never \
  -n lab08 \
  -- /bin/sh -c "while true; do wget -qO- http://web-svc.lab08.svc.cluster.local; sleep 1; done"

# Watch the traffic pod logs in that terminal:
kubectl logs traffic -n lab08 -f
# You should see "Version 1 — v1.0.0" responses continuously
# Keep this running throughout the lab

# ── Step 4: Perform a rolling update to v2 ───────────────────────────────────
# Update the deployment with a new image arg baking in v2
kubectl apply -n lab08 -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
  annotations:
    kubernetes.io/change-cause: "Feature release v2.0.0"
spec:
  replicas: 4
  selector:
    matchLabels:
      app: web-app
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 1
  template:
    metadata:
      labels:
        app: web-app
    spec:
      containers:
      - name: web
        image: hashicorp/http-echo:latest
        args:
        - "-text=Version 2 — v2.0.0"
        ports:
        - containerPort: 5678
        readinessProbe:
          httpGet:
            path: /
            port: 5678
          initialDelaySeconds: 3
          periodSeconds: 5
YAML

# ── Step 5: Watch the rolling update in real time ────────────────────────────
kubectl rollout status deployment/web-app -n lab08
# Shows progress then "successfully rolled out"

# Watch pods being replaced in another terminal:
kubectl get pods -n lab08 -w
# Old pods terminate while new ones start — never below 3 running at once
# Press Ctrl+C

# Check the traffic terminal — responses transition from v1 to v2
# with zero errors or gaps

# ── Step 6: Inspect rollout history ──────────────────────────────────────────
kubectl rollout history deployment/web-app -n lab08
# Shows revision 1 (v1) and revision 2 (v2) with change-cause annotations

kubectl rollout history deployment/web-app -n lab08 --revision=1
kubectl rollout history deployment/web-app -n lab08 --revision=2

# ── Step 7: Deploy a bad image (simulate a broken release) ───────────────────
kubectl set image deployment/web-app web=hashicorp/http-echo:this-tag-does-not-exist -n lab08
kubectl annotate deployment web-app \
  kubernetes.io/change-cause="Broken release v3.0.0 — bad image" \
  -n lab08 --overwrite

kubectl rollout status deployment/web-app -n lab08
# It will hang — new pods can't start (ImagePullBackOff)

kubectl get pods -n lab08
# New pods show ErrImagePull or ImagePullBackOff
# But old v2 pods are still running — maxUnavailable protects them

# Check the traffic terminal — responses are still coming from v2 pods!

# ── Step 8: Roll back to v2 ───────────────────────────────────────────────────
# Note: you may see a warning about last-applied-configuration being out of
# sync because Step 7 used kubectl set image (imperative) rather than
# kubectl apply (declarative). The warning is harmless — the rollback works.
kubectl rollout undo deployment/web-app -n lab08

kubectl rollout status deployment/web-app -n lab08

kubectl get pods -n lab08 -w
# Bad pods replaced with good v2 pods
# Press Ctrl+C

# Check the traffic terminal — back to "Version 2 — v2.0.0"

# ── Step 9: Roll back all the way to v1 ───────────────────────────────────────
kubectl rollout undo deployment/web-app -n lab08 --to-revision=1

kubectl rollout status deployment/web-app -n lab08

# Check the traffic terminal — now showing "Version 1 — v1.0.0" again
# This confirms the rollback is genuine — the version text is baked into
# the container args, not a ConfigMap, so it truly reflects the revision

# ── Step 10: Pause and resume a rollout ──────────────────────────────────────
# Pausing lets you do a canary-style partial rollout —
# update some pods and inspect before completing the rollout.

# Start an update to v2
kubectl apply -n lab08 -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
  annotations:
    kubernetes.io/change-cause: "Canary test v2.0.0"
spec:
  replicas: 4
  selector:
    matchLabels:
      app: web-app
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 1
  template:
    metadata:
      labels:
        app: web-app
    spec:
      containers:
      - name: web
        image: hashicorp/http-echo:latest
        args:
        - "-text=Version 2 — v2.0.0"
        ports:
        - containerPort: 5678
        readinessProbe:
          httpGet:
            path: /
            port: 5678
          initialDelaySeconds: 3
          periodSeconds: 5
YAML

# Pause immediately after triggering
kubectl rollout pause deployment/web-app -n lab08

kubectl get pods -n lab08
# Only some pods updated — rollout is frozen mid-way
# Traffic terminal shows a mix of v1 and v2 responses — that's the canary

# Inspect, then resume when satisfied
kubectl rollout resume deployment/web-app -n lab08
kubectl rollout status deployment/web-app -n lab08

# ── Step 11: View full rollout history ────────────────────────────────────────
kubectl rollout history deployment/web-app -n lab08
# All revisions with change-cause annotations

# ── Step 12: Clean up ────────────────────────────────────────────────────────
kubectl delete pod traffic -n lab08 --ignore-not-found
kubectl delete namespace lab08

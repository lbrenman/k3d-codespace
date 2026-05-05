# Lab 11: Rolling Updates & Zero-Downtime Deploys
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
#   │  Namespace: lab11                                                │
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
kubectl create namespace lab11

# ── Step 2: Deploy v1 of the application ─────────────────────────────────────
# We use nginx with a custom ConfigMap to show which version is running.
kubectl apply -n lab11 -f - <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: web-content
data:
  index.html: |
    <html><body>
    <h1>Version 1</h1>
    <p>App v1.0.0 — initial release</p>
    </body></html>
---
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
        image: nginx:1.24-alpine
        ports:
        - containerPort: 80
        volumeMounts:
        - name: content
          mountPath: /usr/share/nginx/html
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 3
          periodSeconds: 5
      volumes:
      - name: content
        configMap:
          name: web-content
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
YAML

kubectl get pods -n lab11 -w
# Press Ctrl+C once all 4 pods show READY 1/1

# ── Step 3: Open a continuous traffic stream ──────────────────────────────────
# Open a NEW terminal tab and run this — it sends one request per second
# and prints the response. You will watch it stay live through the update.
kubectl run traffic \
  --image=busybox:latest \
  --restart=Never \
  -n lab11 \
  -- /bin/sh -c "while true; do wget -qO- http://web-svc.lab11.svc.cluster.local; sleep 1; done"

# Watch the traffic pod logs in that terminal:
kubectl logs traffic -n lab11 -f
# You should see "Version 1" responses continuously
# Keep this running throughout the lab

# ── Step 4: Perform a rolling update to v2 ───────────────────────────────────
# Update the ConfigMap content and trigger a new rollout by updating the image
# (we bump the nginx patch version to force a new pod template hash)
kubectl apply -n lab11 -f - <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: web-content
data:
  index.html: |
    <html><body>
    <h1>Version 2</h1>
    <p>App v2.0.0 — new feature release</p>
    </body></html>
YAML

# Update the deployment image and record the change cause
kubectl set image deployment/web-app web=nginx:1.25-alpine -n lab11
kubectl annotate deployment web-app \
  kubernetes.io/change-cause="Feature release v2.0.0" \
  -n lab11 --overwrite

# ── Step 5: Watch the rolling update in real time ────────────────────────────
kubectl rollout status deployment/web-app -n lab11
# Shows: "Waiting for deployment to finish..." then "successfully rolled out"

# In another terminal watch pods being replaced one at a time:
kubectl get pods -n lab11 -w
# Old pods terminate while new ones start — never below 3 running at once
# Press Ctrl+C

# Check the traffic terminal — responses should transition from v1 to v2
# with zero errors or gaps

# ── Step 6: Inspect rollout history ──────────────────────────────────────────
kubectl rollout history deployment/web-app -n lab11
# Shows revision 1 (v1) and revision 2 (v2) with change-cause annotations

kubectl rollout history deployment/web-app -n lab11 --revision=1
kubectl rollout history deployment/web-app -n lab11 --revision=2
# Drill into each revision for full details

# ── Step 7: Deploy a bad image (simulate a broken release) ───────────────────
kubectl set image deployment/web-app web=nginx:this-tag-does-not-exist -n lab11
kubectl annotate deployment web-app \
  kubernetes.io/change-cause="Broken release v3.0.0 — bad image" \
  -n lab11 --overwrite

# Watch what happens
kubectl rollout status deployment/web-app -n lab11
# It will hang — new pods can't start (ImagePullBackOff)

kubectl get pods -n lab11
# New pods show ErrImagePull or ImagePullBackOff
# But old v2 pods are still running — maxUnavailable protects them

# Check the traffic terminal — responses are still coming from v2 pods!

# ── Step 8: Roll back to v2 ───────────────────────────────────────────────────
kubectl rollout undo deployment/web-app -n lab11

kubectl rollout status deployment/web-app -n lab11
# Rolls back to revision 2 immediately

kubectl get pods -n lab11 -w
# Bad pods are replaced with good v2 pods
# Press Ctrl+C

# Rollback to a specific revision (e.g. all the way back to v1)
kubectl rollout undo deployment/web-app -n lab11 --to-revision=1
kubectl rollout status deployment/web-app -n lab11

# ── Step 9: Pause and resume a rollout ───────────────────────────────────────
# Pausing lets you do a canary-style partial rollout —
# update some pods and inspect before completing the rollout.

# First get back to v2
kubectl set image deployment/web-app web=nginx:1.25-alpine -n lab11
kubectl annotate deployment web-app \
  kubernetes.io/change-cause="Back to v2.0.0" \
  -n lab11 --overwrite
kubectl rollout status deployment/web-app -n lab11

# Now start a new update but pause it immediately
kubectl set image deployment/web-app web=nginx:1.26-alpine -n lab11
kubectl rollout pause deployment/web-app -n lab11

kubectl get pods -n lab11
# Only some pods updated — rollout is frozen mid-way

# Inspect the partial rollout, then resume
kubectl rollout resume deployment/web-app -n lab11
kubectl rollout status deployment/web-app -n lab11

# ── Step 10: View full rollout history ────────────────────────────────────────
kubectl rollout history deployment/web-app -n lab11
# All revisions listed with change-cause annotations

# ── Step 11: Clean up ────────────────────────────────────────────────────────
kubectl delete pod traffic -n lab11 --ignore-not-found
kubectl delete namespace lab11

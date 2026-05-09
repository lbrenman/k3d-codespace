# Lab 14: Troubleshooting — Diagnosing Common Pod Failures
# ─────────────────────────────────────────────────────────────────────────────
# Every Kubernetes practitioner encounters failing pods. This lab deliberately
# creates the most common failure modes so you can learn to recognise and fix
# them. Each section introduces a broken pod, shows you how to diagnose it,
# and then shows you how to fix it.
#
# HOW TO USE THIS LAB:
#   Copy and paste each command block into your terminal one step at a time.
#   Do not run this file as a script.
#
# Failure modes covered:
#
#   ┌──────────────────────────────────────────────────────────────────┐
#   │                                                                  │
#   │  CrashLoopBackOff   — container starts but immediately exits    │
#   │  OOMKilled          — container exceeds memory limit            │
#   │  ImagePullBackOff   — image cannot be pulled                    │
#   │  Pending            — pod cannot be scheduled onto a node       │
#   │  CreateContainerConfigError — missing Secret or ConfigMap       │
#   │  Running but broken — pod is up but not serving correctly       │
#   │                                                                  │
#   └──────────────────────────────────────────────────────────────────┘
#
# The diagnostic toolkit:
#   kubectl get pods          — see STATUS and RESTARTS at a glance
#   kubectl describe pod      — full detail including Events section
#   kubectl logs              — stdout/stderr from the container
#   kubectl logs --previous   — logs from the previous (crashed) container
#   kubectl get events        — cluster-wide event stream
#
# Key concepts: pod lifecycle, exit codes, resource limits, scheduling

# ── Step 1: Create namespace ──────────────────────────────────────────────────
kubectl create namespace lab14

# ════════════════════════════════════════════════════════════════════════════
# SECTION A: CrashLoopBackOff
# ════════════════════════════════════════════════════════════════════════════
#
# A pod in CrashLoopBackOff starts, crashes immediately, and Kubernetes keeps
# restarting it with an exponential backoff (10s, 20s, 40s, 80s...).
# The key diagnostic is the exit code — it tells you WHY it crashed.
#
# Common exit codes:
#   0   — clean exit (not a crash, just finished)
#   1   — general error (check logs for details)
#   2   — misuse of shell command
#   127 — command not found
#   137 — killed by SIGKILL (usually OOMKilled)
#   139 — segmentation fault

# ── Step 2: Deploy a crashing pod ────────────────────────────────────────────
kubectl apply -n lab14 -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: crash-loop
spec:
  containers:
  - name: app
    image: busybox:latest
    command: ["/bin/sh", "-c", "echo 'Starting...'; sleep 2; exit 1"]
YAML

# ── Step 3: Diagnose CrashLoopBackOff ────────────────────────────────────────
kubectl get pod crash-loop -n lab14
# STATUS shows CrashLoopBackOff, RESTARTS keeps incrementing

# First — check the exit code and last state
# This tells you WHY it crashed (exit code 1 = general error)
kubectl describe pod crash-loop -n lab14
# Look for in the output:
#   Last State: Terminated
#   Exit Code: 1
#   Reason: Error

# Then — try to read the current container logs
kubectl logs crash-loop -n lab14
# This may return nothing if the pod is currently in backoff (waiting to restart)
# That is normal — use --previous instead

# Most useful — read logs from the PREVIOUS (crashed) container
# --previous shows the output from the last run before it crashed
kubectl logs crash-loop -n lab14 --previous
# Shows: "Starting..." — the last thing the container printed before exiting

# ── Step 4: Fix it ───────────────────────────────────────────────────────────
kubectl delete pod crash-loop -n lab14

kubectl apply -n lab14 -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: crash-loop
spec:
  containers:
  - name: app
    image: busybox:latest
    command: ["/bin/sh", "-c", "echo 'Starting...'; sleep 3600"]
YAML

kubectl get pod crash-loop -n lab14
# STATUS: Running, RESTARTS: 0

# ════════════════════════════════════════════════════════════════════════════
# SECTION B: OOMKilled
# ════════════════════════════════════════════════════════════════════════════
#
# OOMKilled (Out Of Memory Killed) happens when a container exceeds its
# memory limit. Kubernetes kills it immediately (exit code 137).
# It often manifests as CrashLoopBackOff with exit code 137.

# ── Step 5: Deploy a pod that exceeds its memory limit ───────────────────────
# We use Python to allocate a large byte array instantly — much more reliable
# than a shell loop for triggering OOMKill quickly and consistently.
kubectl apply -n lab14 -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: oom-demo
spec:
  containers:
  - name: app
    image: python:3-alpine
    command:
    - python3
    - -c
    - |
      print("Allocating memory...")
      # Allocate 50MB instantly — well over the 20Mi limit
      x = bytearray(50 * 1024 * 1024)
      print("Done — should have been killed by now")
    resources:
      limits:
        memory: 20Mi
YAML

# ── Step 6: Diagnose OOMKilled ───────────────────────────────────────────────
# OOMKill happens almost instantly — by the time you run the next command
# the pod may already show OOMKilled or CrashLoopBackOff
kubectl get pod oom-demo -n lab14
# If STATUS shows OOMKilled or CrashLoopBackOff with RESTARTS > 0, it worked

# Watch mode if you want to see it happen live (run immediately after Step 5):
kubectl get pod oom-demo -n lab14 -w
# Press Ctrl+C once you see OOMKilled or CrashLoopBackOff

kubectl describe pod oom-demo -n lab14
# Look for:
#   Last State: Terminated
#   Reason: OOMKilled
#   Exit Code: 137

kubectl logs oom-demo -n lab14 --previous
# May show "Allocating memory..." or may be empty/error — this is normal.
# OOMKill happens so abruptly that the kernel kills the process before it
# can flush its log buffer. The definitive proof is in kubectl describe, not logs.

# ── Step 7: Fix it — increase the memory limit ───────────────────────────────
kubectl delete pod oom-demo -n lab14

kubectl apply -n lab14 -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: oom-demo
spec:
  containers:
  - name: app
    image: busybox:latest
    command: ["/bin/sh", "-c", "echo 'Running fine'; sleep 3600"]
    resources:
      requests:
        memory: 32Mi
      limits:
        memory: 64Mi    # Reasonable limit
YAML

kubectl get pod oom-demo -n lab14
# STATUS: Running, RESTARTS: 0

# ════════════════════════════════════════════════════════════════════════════
# SECTION C: ImagePullBackOff / ErrImagePull
# ════════════════════════════════════════════════════════════════════════════
#
# ImagePullBackOff means Kubernetes cannot pull the container image.
# Common causes: typo in image name, wrong tag, private registry with no credentials.

# ── Step 8: Deploy a pod with a bad image ────────────────────────────────────
kubectl apply -n lab14 -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: bad-image
spec:
  containers:
  - name: app
    image: nginx:this-tag-does-not-exist
YAML

# ── Step 9: Diagnose ImagePullBackOff ────────────────────────────────────────
kubectl get pod bad-image -n lab14
# STATUS: ErrImagePull → then ImagePullBackOff

kubectl describe pod bad-image -n lab14
# Look in Events section for:
#   Failed to pull image: ... manifest unknown
#   or: ... not found
#   or: ... unauthorized

# ── Step 10: Fix it — use a valid image tag ───────────────────────────────────
kubectl delete pod bad-image -n lab14

kubectl apply -n lab14 -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: bad-image
spec:
  containers:
  - name: app
    image: nginx:alpine    # Valid tag
YAML

kubectl get pod bad-image -n lab14
# STATUS: Running

# ════════════════════════════════════════════════════════════════════════════
# SECTION D: Pending — scheduling failures
# ════════════════════════════════════════════════════════════════════════════
#
# A Pending pod means the scheduler cannot find a node to place it on.
# Common causes: requesting more resources than any node has available,
# or using a nodeSelector that doesn't match any node.

# ── Step 11: Deploy a pod requesting too many resources ──────────────────────
kubectl apply -n lab14 -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: too-greedy
spec:
  containers:
  - name: app
    image: nginx:alpine
    resources:
      requests:
        memory: 999Gi    # No node has this much memory
        cpu: 999
YAML

# ── Step 12: Diagnose Pending ────────────────────────────────────────────────
kubectl get pod too-greedy -n lab14
# STATUS: Pending — stays Pending indefinitely

kubectl describe pod too-greedy -n lab14
# Look in Events section for:
#   0/3 nodes are available: insufficient memory, insufficient cpu

# Check what resources the nodes actually have
# Note: kubectl top requires the metrics-server (pre-installed in k3d).
# If this errors, use the fallback command below instead.
kubectl top nodes 2>/dev/null || \
  kubectl describe nodes | grep -A8 "Allocated resources"

kubectl describe nodes | grep -A5 "Allocated resources"

# ── Step 13: Fix it — use reasonable resource requests ───────────────────────
kubectl delete pod too-greedy -n lab14

kubectl apply -n lab14 -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: too-greedy
spec:
  containers:
  - name: app
    image: nginx:alpine
    resources:
      requests:
        memory: 64Mi
        cpu: 100m
YAML

kubectl get pod too-greedy -n lab14
# STATUS: Running

# ════════════════════════════════════════════════════════════════════════════
# SECTION E: CreateContainerConfigError — missing Secret or ConfigMap
# ════════════════════════════════════════════════════════════════════════════
#
# This error means the pod spec references a Secret or ConfigMap that
# doesn't exist. You saw this in the Microservices lab when manifests were
# applied out of order.

# ── Step 14: Deploy a pod referencing a missing Secret ───────────────────────
kubectl apply -n lab14 -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: missing-secret
spec:
  containers:
  - name: app
    image: nginx:alpine
    env:
    - name: API_KEY
      valueFrom:
        secretKeyRef:
          name: my-secret       # This Secret does not exist
          key: API_KEY
YAML

# ── Step 15: Diagnose CreateContainerConfigError ─────────────────────────────
kubectl get pod missing-secret -n lab14
# STATUS: Pending or CreateContainerConfigError

kubectl describe pod missing-secret -n lab14
# Look in Events section for:
#   secret "my-secret" not found

# ── Step 16: Fix it — create the missing Secret ──────────────────────────────
kubectl create secret generic my-secret \
  --from-literal=API_KEY=abc123 \
  -n lab14

kubectl get pod missing-secret -n lab14
# Kubernetes automatically retries — STATUS changes to Running within seconds

# ════════════════════════════════════════════════════════════════════════════
# SECTION F: Running but not working — wrong port or command
# ════════════════════════════════════════════════════════════════════════════

# ── Step 17: Deploy a Service pointing to the wrong port ─────────────────────
kubectl apply -n lab14 -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wrong-port
spec:
  replicas: 1
  selector:
    matchLabels:
      app: wrong-port
  template:
    metadata:
      labels:
        app: wrong-port
    spec:
      containers:
      - name: app
        image: nginx:alpine
        ports:
        - containerPort: 80      # nginx listens on 80
---
apiVersion: v1
kind: Service
metadata:
  name: wrong-port-svc
spec:
  selector:
    app: wrong-port
  ports:
  - port: 80
    targetPort: 9999             # Wrong — nginx is not on 9999
YAML

kubectl get pods -n lab14 -w
# Press Ctrl+C once pod shows Running

# ── Step 18: Diagnose the broken service ─────────────────────────────────────
# Pod appears healthy — STATUS Running, RESTARTS 0
# But requests to the service fail

# Delete previous test pod if it exists (safe to re-run this step)
kubectl delete pod test -n lab14 --ignore-not-found
kubectl run test --image=busybox:latest --restart=Never -n lab14 \
  -- wget -qO- --timeout=5 http://wrong-port-svc.lab14.svc.cluster.local
kubectl logs test -n lab14
# Error: connection refused — service reaches the pod but wrong port

# Check what the service is actually targeting
kubectl describe svc wrong-port-svc -n lab14
# Look at: TargetPort — it shows 9999 but nginx listens on 80

# Check what port the container actually exposes
kubectl get pods -n lab14 -l app=wrong-port
# Copy the pod name from above, then:
kubectl describe pod -n lab14 -l app=wrong-port
# Look for the "Ports:" line under the container section — it shows 80/TCP

# ── Step 19: Fix the service targetPort ──────────────────────────────────────
kubectl patch svc wrong-port-svc -n lab14 \
  --patch '{"spec":{"ports":[{"port":80,"targetPort":80}]}}'

# Delete previous test2 pod if it exists (safe to re-run this step)
kubectl delete pod test2 -n lab14 --ignore-not-found
kubectl run test2 --image=busybox:latest --restart=Never -n lab14 \
  -- wget -qO- http://wrong-port-svc.lab14.svc.cluster.local
kubectl logs test2 -n lab14
# Now returns nginx welcome page HTML

# ── Step 20: Quick reference — diagnostic commands ───────────────────────────
# These are the commands to reach for first when something is wrong:
#
# See all pod statuses at a glance:
kubectl get pods -n lab14
#
# Full detail on a failing pod (always check Events section at bottom):
# kubectl describe pod <pod-name> -n <namespace>
#
# Current container logs:
# kubectl logs <pod-name> -n <namespace>
#
# Previous container logs (after a crash):
# kubectl logs <pod-name> -n <namespace> --previous
#
# All recent cluster events sorted by time:
kubectl get events -n lab14 --sort-by='.lastTimestamp'
#
# Watch events live:
# kubectl get events -n lab14 -w

# ── Step 21: Clean up ────────────────────────────────────────────────────────
kubectl delete namespace lab14

# ── Further Reading ───────────────────────────────────────────────────────────
# Pod lifecycle:
#   https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/
# Debugging pods:
#   https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/
# Debugging services:
#   https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/
# Application introspection and debugging:
#   https://kubernetes.io/docs/tasks/debug/debug-application/

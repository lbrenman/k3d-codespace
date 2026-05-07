# Lab 13: Exploring Pod Filesystems & Log Files
# ─────────────────────────────────────────────────────────────────────────────
# Kubernetes provides several ways to access what's happening inside a running
# container — its filesystem, log files, and stdout/stderr streams. This lab
# covers the full toolkit for investigating a pod's internals, which is
# essential for debugging real applications in production.
#
# HOW TO USE THIS LAB:
#   Copy and paste each command block into your terminal one step at a time.
#   Do not run this file as a script.
#
# Two types of logs in Kubernetes:
#
#   ┌─────────────────────────────────────────────────────────────────┐
#   │                                                                 │
#   │  stdout/stderr logs                                             │
#   │  Written by the app to standard output/error.                  │
#   │  Captured by Kubernetes automatically.                         │
#   │  Accessed via: kubectl logs                                    │
#   │  Survive container restarts (previous logs accessible too)     │
#   │                                                                 │
#   │  File-based logs                                                │
#   │  Written by the app to files inside the container filesystem.  │
#   │  NOT captured by Kubernetes automatically.                     │
#   │  Accessed via: kubectl exec + standard Unix tools              │
#   │  Lost when the container restarts (unless on a PVC)            │
#   │                                                                 │
#   └─────────────────────────────────────────────────────────────────┘
#
# What you will build:
#
#   ┌──────────────────────────────────────────────────────────────────┐
#   │  Namespace: lab13                                                │
#   │                                                                  │
#   │  Pod: log-demo                                                  │
#   │    container: app                                               │
#   │      writes to stdout   → kubectl logs                         │
#   │      writes to /logs/app.log  → kubectl exec + cat/tail        │
#   │      writes to /logs/error.log                                  │
#   │                                                                  │
#   │  Pod: nginx-demo (nginx web server)                             │
#   │    /var/log/nginx/access.log → /dev/stdout (symlink)           │
#   │    /var/log/nginx/error.log  → /dev/stderr (symlink)           │
#   │    logs accessed via: kubectl logs (not kubectl exec)          │
#   │                                                                  │
#   └──────────────────────────────────────────────────────────────────┘
#
# Key concepts: kubectl logs, kubectl exec, kubectl cp,
#               ephemeral containers, log rotation, stdout vs file logs

# ── Step 1: Create namespace ──────────────────────────────────────────────────
kubectl create namespace lab13

# ════════════════════════════════════════════════════════════════════════════
# SECTION A: stdout/stderr logs with kubectl logs
# ════════════════════════════════════════════════════════════════════════════

# ── Step 2: Deploy a pod that writes to stdout and to log files ───────────────
kubectl apply -n lab13 -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: log-demo
  labels:
    app: log-demo
spec:
  containers:
  - name: app
    image: busybox:latest
    command:
    - /bin/sh
    - -c
    - |
      mkdir -p /logs
      echo "App started at \$(date)" | tee /logs/app.log
      counter=0
      while true; do
        counter=\$((counter + 1))
        timestamp=\$(date '+%Y-%m-%d %H:%M:%S')

        # Write to stdout (captured by kubectl logs)
        echo "[\$timestamp] INFO  Request #\$counter processed"

        # Write to file (not captured by kubectl logs)
        echo "[\$timestamp] INFO  Request #\$counter processed" >> /logs/app.log

        # Occasionally write an error to both stderr and error log
        if [ \$((counter % 5)) -eq 0 ]; then
          echo "[\$timestamp] ERROR Simulated error on request #\$counter" >&2
          echo "[\$timestamp] ERROR Simulated error on request #\$counter" >> /logs/error.log
        fi

        sleep 2
      done
    volumeMounts:
    - name: log-storage
      mountPath: /logs
  volumes:
  - name: log-storage
    emptyDir: {}
YAML

kubectl get pod log-demo -n lab13 -w
# Press Ctrl+C once the pod shows Running

# ── Step 3: View stdout logs with kubectl logs ────────────────────────────────
# Basic log view
kubectl logs log-demo -n lab13

# Stream logs live (like tail -f)
kubectl logs log-demo -n lab13 -f
# Press Ctrl+C to stop streaming

# Show only the last 10 lines
kubectl logs log-demo -n lab13 --tail=10

# Show logs with timestamps added by Kubernetes
kubectl logs log-demo -n lab13 --timestamps=true

# Show logs from the last 30 seconds
kubectl logs log-demo -n lab13 --since=30s

# ── Step 4: View file-based logs with kubectl exec ────────────────────────────
# kubectl exec runs a command inside the container — like SSH but for K8s pods

# List the log directory
kubectl exec log-demo -n lab13 -- ls -la /logs/

# View the full app log file
kubectl exec log-demo -n lab13 -- cat /logs/app.log

# View just the last 20 lines (tail)
kubectl exec log-demo -n lab13 -- tail -20 /logs/app.log

# Stream the log file live (like tail -f for file-based logs)
kubectl exec log-demo -n lab13 -- tail -f /logs/app.log
# Press Ctrl+C to stop

# View only error log entries
kubectl exec log-demo -n lab13 -- cat /logs/error.log

# Search for specific patterns with grep
# ERROR entries are written to error.log, INFO entries to app.log
kubectl exec log-demo -n lab13 -- grep "ERROR" /logs/error.log
kubectl exec log-demo -n lab13 -- grep "INFO" /logs/app.log | tail -5

# Count lines in the log file
kubectl exec log-demo -n lab13 -- wc -l /logs/app.log

# ── Step 5: Open an interactive shell inside the container ────────────────────
# For deeper investigation, open a full shell session
kubectl exec -it log-demo -n lab13 -- /bin/sh

# Once inside the container, try:
#   ls -la /logs/
#   cat /logs/app.log
#   tail -f /logs/app.log
#   find / -name "*.log" 2>/dev/null
#   df -h              (disk usage)
#   ps aux             (running processes)
#   env                (environment variables)
#   exit               (leave the shell)

# ── Step 6: Copy log files out of the container ───────────────────────────────
# kubectl cp lets you copy files between your local machine and a container

# Copy a single log file to your current directory
kubectl cp lab13/log-demo:/logs/app.log ./app.log
ls -la ./app.log
cat ./app.log

# Copy the entire logs directory
kubectl cp lab13/log-demo:/logs ./pod-logs/
ls -la ./pod-logs/

# You can also copy files INTO a container (useful for injecting config)
echo "injected content" > /tmp/test-inject.txt
kubectl cp /tmp/test-inject.txt lab13/log-demo:/logs/injected.txt
kubectl exec log-demo -n lab13 -- cat /logs/injected.txt

# Clean up local copies
rm -f ./app.log
rm -rf ./pod-logs/

# ════════════════════════════════════════════════════════════════════════════
# SECTION B: Exploring a real application's log files (nginx)
# ════════════════════════════════════════════════════════════════════════════

# ── Step 7: Deploy nginx and generate some traffic ────────────────────────────
kubectl apply -n lab13 -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: nginx-demo
  labels:
    app: nginx-demo
spec:
  containers:
  - name: nginx
    image: nginx:alpine
    ports:
    - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-svc
spec:
  selector:
    app: nginx-demo
  ports:
  - port: 80
YAML

kubectl get pod nginx-demo -n lab13 -w
# Press Ctrl+C once Running

# Generate some HTTP traffic to create log entries
kubectl run curl-client \
  --image=curlimages/curl:latest \
  --restart=Never \
  -n lab13 \
  -- /bin/sh -c "
    for i in \$(seq 1 10); do
      curl -s http://nginx-svc.lab13.svc.cluster.local/ > /dev/null
      curl -s http://nginx-svc.lab13.svc.cluster.local/notfound > /dev/null
    done
    echo 'Done generating traffic'
  "

kubectl get pod curl-client -n lab13 -w
# Press Ctrl+C once Completed

# Verify the traffic pod finished successfully and generated log entries
kubectl logs curl-client -n lab13
# Should show: "Done generating traffic"

# Confirm traffic was generated before proceeding
kubectl logs nginx-demo -n lab13 | grep "GET" | wc -l
# Should show at least 20 lines (10 x 200 + 10 x 404 requests)
# If it shows 0, wait a few seconds and run again

# ── Step 8: Explore nginx logs ───────────────────────────────────────────────
# The official nginx Docker image symlinks its log files to stdout/stderr:
#   /var/log/nginx/access.log → /dev/stdout
#   /var/log/nginx/error.log  → /dev/stderr
#
# This means kubectl exec -- cat /var/log/nginx/access.log returns nothing.
# The log data flows through stdout and is captured by Kubernetes instead.
# This is the recommended container pattern: always log to stdout.

# Verify the symlinks
kubectl exec nginx-demo -n lab13 -- ls -la /var/log/nginx/
# You will see: access.log -> /dev/stdout  and  error.log -> /dev/stderr

# View all nginx output via kubectl logs (access + error combined)
kubectl logs nginx-demo -n lab13

# Show only the last 20 lines
kubectl logs nginx-demo -n lab13 --tail=20

# Filter for 200 responses only
kubectl logs nginx-demo -n lab13 | grep '"GET / HTTP'

# Filter for 404 responses only
kubectl logs nginx-demo -n lab13 | grep " 404 "

# Count requests by HTTP status code
kubectl logs nginx-demo -n lab13 | awk '{print $9}' | sort | uniq -c | sort -rn
# Shows: count of 200s, 404s, and startup notice lines

# Stream nginx logs live
kubectl logs nginx-demo -n lab13 -f
# Press Ctrl+C to stop

# ── Step 9: Key takeaway — stdout vs file logs ────────────────────────────────
# nginx shows the modern container logging pattern: log to stdout so
# Kubernetes captures it automatically and kubectl logs works out of the box.
#
# Compare this to the log-demo pod from Section A which writes BOTH to
# stdout AND to files — you can see both approaches side by side:

# stdout logs (via kubectl logs):
kubectl logs log-demo -n lab13 --tail=5

# file-based logs (via kubectl exec):
kubectl exec log-demo -n lab13 -- tail -5 /logs/app.log

# Both show the same content — the key difference is:
#   stdout logs → always accessible via kubectl logs, survive pod restarts
#   file logs   → require kubectl exec to access, lost on container restart
#                 unless stored on a PVC

# ── Step 10: View logs from a previous container restart ──────────────────────
# If a container has restarted, you can view the previous container's logs

kubectl logs log-demo -n lab13 -p 2>/dev/null || \
  echo "No previous container logs (pod has not restarted yet)"

# To see how many times a pod has restarted:
kubectl get pod log-demo -n lab13
# Check the RESTARTS column

# ── Step 11: View logs from multi-container pods ──────────────────────────────
# If a pod has multiple containers, specify which one with -c
kubectl apply -n lab13 -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: multi-container
spec:
  containers:
  - name: main-app
    image: busybox:latest
    command: [sh, -c, "while true; do echo 'main-app log entry'; sleep 3; done"]
  - name: sidecar
    image: busybox:latest
    command: [sh, -c, "while true; do echo 'sidecar log entry'; sleep 5; done"]
YAML

kubectl get pod multi-container -n lab13 -w
# Press Ctrl+C once Running

# View logs from a specific container
kubectl logs multi-container -n lab13 -c main-app
kubectl logs multi-container -n lab13 -c sidecar

# Stream logs from ALL containers at once
kubectl logs multi-container -n lab13 --all-containers=true -f
# Each line is prefixed with the container name
# Press Ctrl+C to stop

# ── Step 12: Clean up ────────────────────────────────────────────────────────
kubectl delete namespace lab13

# ── Further Reading ───────────────────────────────────────────────────────────
# kubectl logs reference:
#   https://kubernetes.io/docs/reference/kubectl/generated/kubectl_logs/
# kubectl exec reference:
#   https://kubernetes.io/docs/reference/kubectl/generated/kubectl_exec/
# kubectl cp reference:
#   https://kubernetes.io/docs/reference/kubectl/generated/kubectl_cp/
# Logging architecture in Kubernetes:
#   https://kubernetes.io/docs/concepts/cluster-administration/logging/
# 12-Factor App: Treat logs as event streams:
#   https://12factor.net/logs

# Lab 07: Resource Limits & Autoscaling (HPA)
# ─────────────────────────────────────────────────────────────────────────────
#
# Kubernetes can automatically scale your application up and down based on
# real-time CPU or memory usage using the Horizontal Pod Autoscaler (HPA).
# But before HPA can work, pods must declare their resource requests and limits
# so the scheduler and autoscaler know what they're working with.
#
# HOW TO USE THIS LAB:
#   Copy and paste each command block into your terminal one step at a time.
#   Do not run this file as a script.
#
# What you will build:
#
#   ┌──────────────────────────────────────────────────────────────────┐
#   │  Namespace: lab07                                                 │
#   │                                                                  │
#   │  ┌─────────────────────────────────────────────────────────┐    │
#   │  │  HPA: php-apache-hpa                                    │    │
#   │  │  min replicas: 1   max replicas: 10                     │    │
#   │  │  target CPU utilization: 50%                            │    │
#   │  │         │                                               │    │
#   │  │         │ watches metrics & scales                      │    │
#   │  │         ▼                                               │    │
#   │  │  Deployment: php-apache                                 │    │
#   │  │    1 pod at idle ──► up to 10 pods under load          │    │
#   │  │    resources:                                           │    │
#   │  │      requests: cpu=200m, memory=64Mi                   │    │
#   │  │      limits:   cpu=500m, memory=128Mi                  │    │
#   │  └──────────────────────────────────────────────────────── ┘    │
#   │                          │                                       │
#   │  ┌───────────────────────▼─────────────────────────────────┐    │
#   │  │  Service: php-apache (ClusterIP :80)                    │    │
#   │  └─────────────────────────────────────────────────────────┘    │
#   │                          ▲                                       │
#   │  ┌───────────────────────┴─────────────────────────────────┐    │
#   │  │  Pod: load-generator                                    │    │
#   │  │  Continuous HTTP requests → drives CPU up               │    │
#   │  └─────────────────────────────────────────────────────────┘    │
#   └──────────────────────────────────────────────────────────────────┘
#
# Resource requests vs limits explained:
#
#   requests: the minimum guaranteed resources for a pod
#             Used by the scheduler to decide which node to place the pod on.
#             CPU unit: 1 = 1 core, 500m = 0.5 core, 200m = 0.2 core
#             Memory unit: Mi = mebibytes, Gi = gibibytes
#
#   limits:   the maximum a pod is allowed to consume
#             CPU over limit → throttled (slowed, not killed)
#             Memory over limit → OOMKilled (container restarted)
#
#   HPA uses requests as its baseline for percentage calculations:
#     If request = 200m and current usage = 150m → utilization = 75%
#     At target 50%, HPA would scale up to bring utilization down
#
# Key concepts: resource requests, resource limits, HPA, metrics-server,
#               CPU throttling, horizontal vs vertical scaling

# ── Step 1: Create namespace ──────────────────────────────────────────────────
kubectl create namespace lab07

# ── Step 2: Deploy a CPU-intensive app with resource limits ───────────────────
# php-apache is the standard load test image used in the official K8s HPA docs.
kubectl apply -n lab07 -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: php-apache
spec:
  replicas: 1
  selector:
    matchLabels:
      app: php-apache
  template:
    metadata:
      labels:
        app: php-apache
    spec:
      containers:
      - name: php-apache
        image: registry.k8s.io/hpa-example
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 200m
            memory: 64Mi
          limits:
            cpu: 500m
            memory: 128Mi
---
apiVersion: v1
kind: Service
metadata:
  name: php-apache
spec:
  selector:
    app: php-apache
  ports:
  - port: 80
YAML

kubectl get pods -n lab07 -w
# Press Ctrl+C once the pod shows Running

# ── Step 3: Check resource usage at idle ──────────────────────────────────────
kubectl top pods -n lab07
# At idle the pod should use very little CPU relative to its 200m request

kubectl top nodes
# Shows per-node usage across the whole cluster

# ── Step 4: Create the Horizontal Pod Autoscaler ─────────────────────────────
# When average CPU across all pods exceeds 50% of the request (200m = 100m),
# HPA adds pods. When it drops back down, HPA removes them (with a cooldown).
kubectl apply -n lab07 -f - <<YAML
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: php-apache-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: php-apache
  minReplicas: 1
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
YAML

# Inspect the HPA — TARGETS will show <unknown> briefly until metrics arrive
kubectl get hpa -n lab07
kubectl describe hpa php-apache-hpa -n lab07

# ── Step 5: Generate load in a separate terminal ──────────────────────────────
# Open a NEW terminal tab and run this command there.
# Keep it running while you observe scaling in your main terminal.
kubectl run load-generator \
  --image=busybox:latest \
  --restart=Never \
  -n lab07 \
  -- /bin/sh -c "while true; do wget -q -O- http://php-apache.lab07.svc.cluster.local; done"

# ── Step 6: Watch the autoscaler respond ─────────────────────────────────────
# Back in your main terminal. Takes ~60-90 seconds to start scaling.
kubectl get hpa -n lab07 -w
# Watch TARGETS rise above 50% and REPLICAS increase automatically
# Press Ctrl+C

# Also watch pods in another terminal:
kubectl get pods -n lab07 -w

# Check live resource usage:
kubectl top pods -n lab07

# ── Step 7: Stop the load and watch scale-down ────────────────────────────────
# In the load-generator terminal press Ctrl+C, then delete the pod:
kubectl delete pod load-generator -n lab07

# Watch HPA scale back down — takes several minutes by design.
# Kubernetes is deliberately conservative about scale-down to avoid flapping.
kubectl get hpa -n lab07 -w
# REPLICAS will gradually return to 1
# Press Ctrl+C

# ── Step 8: Observe HPA without resource requests ────────────────────────────
# This demonstrates why resource requests are mandatory for HPA to work.
kubectl apply -n lab07 -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: no-requests
spec:
  replicas: 1
  selector:
    matchLabels:
      app: no-requests
  template:
    metadata:
      labels:
        app: no-requests
    spec:
      containers:
      - name: app
        image: nginx:alpine
        # No resources block — no requests or limits defined
YAML

kubectl autoscale deployment no-requests \
  --cpu-percent=50 --min=1 --max=5 \
  -n lab07

kubectl get hpa -n lab07
# The no-requests HPA will permanently show <unknown> for TARGETS
# and will never scale — there is no baseline to calculate a percentage from

# ── Step 9: Clean up ─────────────────────────────────────────────────────────
kubectl delete namespace lab07


# ── Further Reading ───────────────────────────────────────────────────────────
# Resource requests and limits:
#   https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/
# Horizontal Pod Autoscaling:
#   https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/
# HPA walkthrough (official tutorial):
#   https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/
# Metrics Server:
#   https://github.com/kubernetes-sigs/metrics-server

# Lab 05: PersistentVolumeClaims — Deploying Gitea + PostgreSQL
# ─────────────────────────────────────────────────────────────────────────────
# Gitea is a lightweight self-hosted Git service — like a private GitHub.
# This lab deploys Gitea backed by PostgreSQL, teaching PersistentVolumeClaims
# (PVCs) in a practical context. PVCs are how Kubernetes reserves durable
# storage that survives pod restarts — you'll use them again in every lab that
# runs a database.
#
# HOW TO USE THIS LAB:
#   Copy and paste each command block into your terminal one step at a time.
#   Do not run this file as a script.
#
# What you will build:
#
#   Browser
#     │
#     │ :8080 (Codespace → k3d LoadBalancer → Traefik Ingress)
#     ▼
#   ┌──────────────────────────────────────────────────────────────────┐
#   │  Namespace: lab05                                                │
#   │                                                                  │
#   │  ┌─────────────────────────────────────────────────────────┐    │
#   │  │  Deployment: gitea                                      │    │
#   │  │  image: gitea/gitea:latest                              │    │
#   │  │  env: GITEA__database__* (from Secret)                  │    │
#   │  │                          │                              │    │
#   │  │  PVC: gitea-pvc ─────────┘ /data (repos, config)       │    │
#   │  │       (1Gi)                                             │    │
#   │  └──────────────────┬──────────────────────────────────────┘    │
#   │                     │ Service: gitea-svc :3000                  │
#   │                     │                                           │
#   │  ┌──────────────────▼──────────────────────────────────────┐    │
#   │  │  Deployment: postgres                                   │    │
#   │  │  image: postgres:16-alpine                              │    │
#   │  │  env: POSTGRES_* (from Secret)                          │    │
#   │  │                          │                              │    │
#   │  │  PVC: postgres-pvc ──────┘ /var/lib/postgresql/data     │    │
#   │  │       (2Gi)                                             │    │
#   │  └─────────────────────────────────────────────────────────┘    │
#   │                     │ Service: postgres-svc :5432               │
#   └──────────────────────────────────────────────────────────────────┘
#
# Key concepts: PersistentVolumeClaim, PersistentVolume, StorageClass,
#               late binding, Secret, multi-container app,
#               service discovery by DNS name, Ingress

# ── Step 1: Create namespace ──────────────────────────────────────────────────
kubectl create namespace lab05

# ── Step 2: Create a Secret for database credentials ─────────────────────────
kubectl create secret generic gitea-db-secret \
  --from-literal=POSTGRES_DB=gitea \
  --from-literal=POSTGRES_USER=gitea \
  --from-literal=POSTGRES_PASSWORD=gitea_password \
  -n lab05

# ── Step 3: Create PersistentVolumeClaims ────────────────────────────────────
# A PVC is a request for storage. You declare how much space you need and what
# access mode you require; Kubernetes finds (or provisions) a matching
# PersistentVolume and binds the two together.
#
# Access modes:
#   ReadWriteOnce  — mounted read/write by a single node (most common for DBs)
#   ReadOnlyMany   — mounted read-only by many nodes simultaneously
#   ReadWriteMany  — mounted read/write by many nodes (requires special storage)
#
# Without PVCs, all Gitea repos and PostgreSQL data would be lost on pod restart.
kubectl apply -n lab05 -f - <<YAML
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-pvc
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 2Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: gitea-pvc
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 1Gi
YAML

kubectl get pvc -n lab05
# STATUS will show Pending — this is expected and intentional.
#
# Why Pending? k3d uses the local-path StorageClass which provisions storage
# *lazily* (WaitForFirstConsumer / late binding). It waits until a pod is
# actually scheduled to a node before creating the directory on that node's
# filesystem. The PVC transitions to Bound once its first pod starts.
# This is normal behaviour, not an error.

# ── Step 4: Deploy PostgreSQL ─────────────────────────────────────────────────
kubectl apply -n lab05 -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:16-alpine
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_DB
          valueFrom:
            secretKeyRef:
              name: gitea-db-secret
              key: POSTGRES_DB
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: gitea-db-secret
              key: POSTGRES_USER
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: gitea-db-secret
              key: POSTGRES_PASSWORD
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
        volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
        readinessProbe:
          exec:
            command: [pg_isready, -U, gitea]
          initialDelaySeconds: 10
          periodSeconds: 5
      volumes:
      - name: postgres-data
        persistentVolumeClaim:
          claimName: postgres-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: postgres-svc
spec:
  selector:
    app: postgres
  ports:
  - port: 5432
YAML

kubectl get pods -n lab05 -w
# Press Ctrl+C once postgres pod shows READY 1/1

# Check that the PVC is now Bound (the postgres pod triggered late binding)
kubectl get pvc -n lab05
# postgres-pvc should now show Bound

# ── Step 5: Deploy Gitea ──────────────────────────────────────────────────────
# Gitea uses environment variables prefixed with GITEA__ for configuration.
# The double underscore (__) separates the section from the key.
# GITEA__database__DB_TYPE=postgres tells Gitea to use PostgreSQL.
#
# Notice that GITEA__database__HOST is set to "postgres-svc:5432" — the Service
# name. Kubernetes DNS resolves this to the postgres pod's ClusterIP automatically.
# This is service discovery: pods find each other by Service name, not IP address.
kubectl apply -n lab05 -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gitea
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gitea
  template:
    metadata:
      labels:
        app: gitea
    spec:
      containers:
      - name: gitea
        image: gitea/gitea:latest
        ports:
        - containerPort: 3000
        - containerPort: 22
        env:
        - name: GITEA__database__DB_TYPE
          value: postgres
        - name: GITEA__database__HOST
          value: postgres-svc:5432
        - name: GITEA__database__NAME
          valueFrom:
            secretKeyRef:
              name: gitea-db-secret
              key: POSTGRES_DB
        - name: GITEA__database__USER
          valueFrom:
            secretKeyRef:
              name: gitea-db-secret
              key: POSTGRES_USER
        - name: GITEA__database__PASSWD
          valueFrom:
            secretKeyRef:
              name: gitea-db-secret
              key: POSTGRES_PASSWORD
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
        volumeMounts:
        - name: gitea-data
          mountPath: /data
        readinessProbe:
          httpGet:
            path: /
            port: 3000
          initialDelaySeconds: 15
          periodSeconds: 10
          failureThreshold: 6
      volumes:
      - name: gitea-data
        persistentVolumeClaim:
          claimName: gitea-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: gitea-svc
spec:
  selector:
    app: gitea
  ports:
  - name: web
    port: 3000
    targetPort: 3000
  - name: ssh
    port: 22
    targetPort: 22
YAML

kubectl get pods -n lab05 -w
# Press Ctrl+C once gitea pod shows READY 1/1

# ── Step 6: Create an Ingress for Gitea ───────────────────────────────────────
# Unlike port-forward, the Ingress routes through the k3d LoadBalancer on
# port 8080 and correctly forwards the Host header — no redirect issues.
kubectl apply -n lab05 -f - <<YAML
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: gitea-ingress
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: gitea-svc
            port:
              number: 3000
YAML

# ── Step 7: Access Gitea ──────────────────────────────────────────────────────
# Open port 8080 in your browser via the PORTS tab in VS Code.
# You will see the Gitea first-run installer page.
#
# Important: The "Database Settings" section is pre-filled from the environment
# variables injected via the Secret. Do NOT change these values — just scroll
# past the database section.
#
# Fill in the "Administrator Account Settings" section:
#   Site title:        My Gitea
#   Admin username:    gitadmin
#   Admin password:    (choose one, at least 8 characters)
#   Admin email:       admin@example.com
#
# Click "Install Gitea". After install you will land on the Gitea dashboard —
# a fully working private Git server running in your Kubernetes cluster.

# ── Step 8: Create a repository to test persistence ───────────────────────────
# In the Gitea UI:
#   1. Click the + icon → New Repository
#   2. Name it "test-repo", add a description, initialise with README
#   3. Click Create Repository
# You should see a working Git repository page with a README.

# ── Step 9: Verify persistence ────────────────────────────────────────────────
# Delete the Gitea pod — Kubernetes will recreate it using the same PVC.
# The Ingress continues routing traffic through the Service automatically —
# no port-forward restart needed.
kubectl delete pod -n lab05 -l app=gitea

kubectl get pods -n lab05 -w
# Press Ctrl+C once the new pod shows READY 1/1

# Refresh the browser — your Gitea instance and the test-repo you created
# should still be there, confirming data survived the pod restart via the PVC.

# ── Step 10: Inspect the PVCs ─────────────────────────────────────────────────
kubectl get pvc -n lab05
# Both show Bound

kubectl describe pvc gitea-pvc -n lab05
# Shows StorageClass, volume name, capacity, and access mode

# See the actual PersistentVolume that was provisioned (one per PVC)
kubectl get pv
# Each PV shows which PVC it is bound to (CLAIM column)

# ── Step 11: Connect to PostgreSQL directly ───────────────────────────────────
PG_POD=$(kubectl get pod -n lab05 -l app=postgres -o jsonpath='{.items[0].metadata.name}')

kubectl exec -it $PG_POD -n lab05 -- \
  psql -U gitea -d gitea -c "\dt"
# Lists all Gitea database tables created during setup

# ── Step 12: Clean up ────────────────────────────────────────────────────────
kubectl delete namespace lab05
# Deletes all resources including PVCs and their underlying PersistentVolumes

# ── Further Reading ───────────────────────────────────────────────────────────
# Persistent Volumes:
#   https://kubernetes.io/docs/concepts/storage/persistent-volumes/
# PersistentVolumeClaims:
#   https://kubernetes.io/docs/concepts/storage/persistent-volumes/#persistentvolumeclaims
# StorageClasses:
#   https://kubernetes.io/docs/concepts/storage/storage-classes/
# Gitea documentation:
#   https://docs.gitea.com/

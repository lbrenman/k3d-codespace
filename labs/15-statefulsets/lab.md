# Lab 15: StatefulSets — Running Databases Correctly
# ─────────────────────────────────────────────────────────────────────────────
# Every previous lab that deployed PostgreSQL used a Deployment. This works in
# a single-replica lab environment but is incorrect for production databases.
# Databases need stable network identities, stable hostnames, and ordered
# startup/shutdown — exactly what StatefulSets provide.
#
# HOW TO USE THIS LAB:
#   Copy and paste each command block into your terminal one step at a time.
#   Do not run this file as a script.
#
# Deployment vs StatefulSet — why it matters for databases:
#
#   ┌─────────────────────────────────────────────────────────────────────┐
#   │  Deployment (wrong for databases)                                   │
#   │                                                                     │
#   │  Pod names are random:  postgres-7d8f9-abc                         │
#   │                         postgres-7d8f9-xyz  (different each time)  │
#   │  No guaranteed startup order — replicas start in any sequence      │
#   │  All replicas share one PVC, or each gets a random one             │
#   │  No stable DNS name for individual pods                            │
#   │                                                                     │
#   ├─────────────────────────────────────────────────────────────────────┤
#   │  StatefulSet (correct for databases)                                │
#   │                                                                     │
#   │  Pod names are stable: postgres-0                                  │
#   │                        postgres-1  (always these names)            │
#   │                        postgres-2                                  │
#   │  Ordered startup: 0 must be Ready before 1 starts                 │
#   │  Ordered shutdown: 2 terminates before 1, 1 before 0              │
#   │  Each pod gets its own PVC via volumeClaimTemplates                │
#   │  Each pod has a stable DNS name: postgres-0.postgres-svc           │
#   └─────────────────────────────────────────────────────────────────────┘
#
# What you will build:
#
#   ┌──────────────────────────────────────────────────────────────────┐
#   │  Namespace: lab15                                                │
#   │                                                                  │
#   │  Headless Service: postgres-svc (clusterIP: None)               │
#   │    └─ enables per-pod DNS: postgres-0.postgres-svc              │
#   │                            postgres-1.postgres-svc              │
#   │                                                                  │
#   │  StatefulSet: postgres (3 replicas)                             │
#   │    postgres-0  ──► PVC: data-postgres-0  (auto-created)         │
#   │    postgres-1  ──► PVC: data-postgres-1  (auto-created)         │
#   │    postgres-2  ──► PVC: data-postgres-2  (auto-created)         │
#   │                                                                  │
#   │  Each pod has a stable hostname and its own dedicated storage.   │
#   └──────────────────────────────────────────────────────────────────┘
#
# Key concepts: StatefulSet, Headless Service, volumeClaimTemplates,
#               stable network identity, ordered startup/shutdown,
#               per-pod DNS names

# ── Step 1: Create namespace ──────────────────────────────────────────────────
kubectl create namespace lab15

# ── Step 2: Understand why a Headless Service is required ────────────────────
# A normal ClusterIP Service load-balances across all pods — you can't address
# a specific pod. A Headless Service (clusterIP: None) does NOT load-balance;
# instead it publishes DNS A records for each individual pod:
#
#   postgres-svc          → does not resolve (no ClusterIP)
#   postgres-0.postgres-svc → resolves to the IP of pod postgres-0
#   postgres-1.postgres-svc → resolves to the IP of pod postgres-1
#
# This lets primary/replica database setups route writes to postgres-0 and
# reads to the replicas by name, not by luck of load-balancing.
kubectl apply -n lab15 -f - <<YAML
apiVersion: v1
kind: Service
metadata:
  name: postgres-svc
spec:
  clusterIP: None       # Headless — no load balancing, enables per-pod DNS
  selector:
    app: postgres
  ports:
  - port: 5432
YAML

# ── Step 3: Create a Secret for the database password ────────────────────────
kubectl create secret generic postgres-secret \
  --from-literal=POSTGRES_PASSWORD=stateful_pass \
  --from-literal=POSTGRES_USER=pguser \
  --from-literal=POSTGRES_DB=appdb \
  -n lab15

# ── Step 4: Deploy the StatefulSet ───────────────────────────────────────────
# Key differences from a Deployment:
#   serviceName: must match the Headless Service — used to build pod DNS names
#   volumeClaimTemplates: each pod gets its own PVC (not a shared one)
#   podManagementPolicy: Ordered = 0 starts first, parallel is also available
kubectl apply -n lab15 -f - <<YAML
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  serviceName: postgres-svc        # Must match the Headless Service name
  replicas: 3
  selector:
    matchLabels:
      app: postgres
  podManagementPolicy: OrderedReady  # Start postgres-0, wait for Ready, then postgres-1, etc.
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
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: POSTGRES_PASSWORD
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: POSTGRES_USER
        - name: POSTGRES_DB
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: POSTGRES_DB
        # PGDATA must be a subdirectory of the mount point because postgres
        # refuses to initialise into a directory it did not create itself.
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
        readinessProbe:
          exec:
            command: [pg_isready, -U, pguser, -d, appdb]
          initialDelaySeconds: 10
          periodSeconds: 5
  volumeClaimTemplates:             # One PVC created automatically per pod
  - metadata:
      name: data
    spec:
      accessModes: [ReadWriteOnce]
      resources:
        requests:
          storage: 1Gi
YAML

# ── Step 5: Watch ordered startup ────────────────────────────────────────────
kubectl get pods -n lab15 -w
# You will see:
#   postgres-0   Pending → ContainerCreating → Running → Ready 1/1
#   postgres-1   (does not start until postgres-0 is Ready)
#   postgres-2   (does not start until postgres-1 is Ready)
#
# This ordering is crucial for databases where the primary must initialise
# before replicas can connect to it.
# Press Ctrl+C once all three pods show READY 1/1

# ── Step 6: Inspect the stable pod names and DNS ─────────────────────────────
kubectl get pods -n lab15 -o wide
# Pod names are always postgres-0, postgres-1, postgres-2 — never random hashes

# Verify per-pod DNS resolution from inside the cluster
kubectl run dns-test \
  --image=busybox:latest \
  --restart=Never \
  -n lab15 \
  -- /bin/sh -c "
    echo '=== Resolving individual pod hostnames ==='
    nslookup postgres-0.postgres-svc.lab15.svc.cluster.local
    nslookup postgres-1.postgres-svc.lab15.svc.cluster.local
    echo '=== The headless service itself has no A record ==='
    nslookup postgres-svc.lab15.svc.cluster.local || echo 'No ClusterIP — expected'
  "
kubectl logs dns-test -n lab15
# postgres-0 and postgres-1 resolve to pod IPs
# postgres-svc does not resolve to a single IP — it returns per-pod addresses
kubectl delete pod dns-test -n lab15

# ── Step 7: Inspect the auto-created PVCs ────────────────────────────────────
kubectl get pvc -n lab15
# Three PVCs created automatically — one per pod:
#   data-postgres-0   Bound
#   data-postgres-1   Bound
#   data-postgres-2   Bound
#
# Compare this to a Deployment where you'd define one PVC and all pods
# share it (which corrupts the database).

kubectl describe pvc data-postgres-0 -n lab15
# Shows the PVC is bound to this specific pod's storage

# ── Step 8: Write data to postgres-0 and verify isolation ─────────────────────
# Connect to postgres-0 and create a table
kubectl exec -it postgres-0 -n lab15 -- \
  psql -U pguser -d appdb -c "
    CREATE TABLE IF NOT EXISTS messages (id SERIAL PRIMARY KEY, body TEXT);
    INSERT INTO messages (body) VALUES ('written to postgres-0');
    SELECT * FROM messages;
  "
# Output: 1 row with "written to postgres-0"

# Connect to postgres-1 — it has its own separate database, no replication here
kubectl exec -it postgres-1 -n lab15 -- \
  psql -U pguser -d appdb -c "SELECT * FROM messages;" 2>/dev/null || \
  kubectl exec -it postgres-1 -n lab15 -- \
  psql -U pguser -d appdb -c "\dt"
# messages table does not exist on postgres-1 — each pod has independent storage
# Real replication (streaming replication, Patroni, etc.) is configured at the
# application layer, not by Kubernetes. Kubernetes only provides the stable
# identity and storage that replication needs to work.

# ── Step 9: Delete a pod and watch it come back with the same identity ────────
kubectl delete pod postgres-1 -n lab15

kubectl get pods -n lab15 -w
# postgres-1 is recreated with the SAME name postgres-1
# Press Ctrl+C once it is Running again

# The PVC data-postgres-1 was NOT deleted — the new postgres-1 pod
# reattaches to the same storage automatically
kubectl get pvc -n lab15
# All three PVCs still Bound

# ── Step 10: Scale the StatefulSet ───────────────────────────────────────────
# Scale up — new pod starts AFTER existing pods are Ready
kubectl scale statefulset postgres -n lab15 --replicas=4
kubectl get pods -n lab15 -w
# postgres-3 starts after postgres-2 is Ready
# Press Ctrl+C

# A new PVC is created automatically for postgres-3
kubectl get pvc -n lab15
# data-postgres-3 is now Bound

# Scale down — pods terminate in REVERSE order (3, then 2, ...)
kubectl scale statefulset postgres -n lab15 --replicas=2
kubectl get pods -n lab15 -w
# postgres-3 and postgres-2 terminate (highest ordinal first)
# Press Ctrl+C once only postgres-0 and postgres-1 remain

# Note: scaling down does NOT delete the PVCs — data is preserved
kubectl get pvc -n lab15
# data-postgres-2 and data-postgres-3 still exist (orphaned but not deleted)
# This is intentional: Kubernetes does not auto-delete storage on scale-down.
# You must delete orphaned PVCs manually if you no longer need them.

# ── Step 11: Understand when to use StatefulSet vs Deployment ─────────────────
#
# Use a StatefulSet when ALL of these are true:
#   ✓ Pods need stable, predictable network names (postgres-0.svc)
#   ✓ Pods need their own dedicated persistent storage
#   ✓ Pods have a meaningful startup/shutdown order
#
# Examples: PostgreSQL, MySQL, MongoDB, Kafka, Zookeeper, Elasticsearch
#
# Use a Deployment when:
#   ✓ All replicas are identical and interchangeable
#   ✓ Any pod can handle any request (stateless)
#   ✓ Shared or no persistent storage
#
# Examples: web servers, API services, caches (Redis without persistence)

# ── Step 12: Clean up ────────────────────────────────────────────────────────
kubectl delete namespace lab15
# PVCs and their underlying PersistentVolumes are deleted with the namespace


# ── Further Reading ───────────────────────────────────────────────────────────
# StatefulSets:
#   https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/
# StatefulSet basics tutorial:
#   https://kubernetes.io/docs/tutorials/stateful-application/basic-stateful-set/
# Running a replicated stateful application:
#   https://kubernetes.io/docs/tasks/run-application/run-replicated-stateful-application/
# Headless Services:
#   https://kubernetes.io/docs/concepts/services-networking/service/#headless-services

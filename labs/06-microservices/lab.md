# Lab 06: Microservices — Two APIs Sharing a PostgreSQL Database
# ─────────────────────────────────────────────────────────────────────────────
# This lab deploys a realistic multi-service application: two Node.js/Express
# REST APIs (Products and Users) that share a single PostgreSQL database.
# The images are built locally and loaded into k3d so no registry is needed.
#
# HOW TO USE THIS LAB:
#   Copy and paste each command block into your terminal one step at a time.
#   Do not run this file as a script.
#   Run all commands from the labs/06-microservices/ directory.
#
# What you will build:
#
#   Browser / curl
#        │
#        │ :8080 (Codespace port → k3d LoadBalancer → Traefik Ingress)
#        ▼
#   ┌──────────────────────────────────────────────────────────────────┐
#   │  Namespace: microservices                                        │
#   │                                                                  │
#   │  Ingress                                                         │
#   │    /products ──────────────────────────────────────────────┐    │
#   │    /users ─────────────────────────────────────────────┐   │    │
#   │                                                        │   │    │
#   │  ┌─────────────────────┐   ┌─────────────────────┐    │   │    │
#   │  │ Deployment:         │   │ Deployment:         │    │   │    │
#   │  │ users-api (x2)  ◄──┘   │ products-api (x2) ◄─┘        │    │
#   │  │ port 3002           │   │ port 3001           │         │    │
#   │  └──────────┬──────────┘   └──────────┬──────────┘         │    │
#   │             └──────────────┬───────────┘                    │    │
#   │                            │ shared DATABASE_URL             │    │
#   │                            ▼                                 │    │
#   │         ┌──────────────────────────────────┐                 │    │
#   │         │ Deployment: postgres              │                 │    │
#   │         │ port 5432                         │                 │    │
#   │         │ PVC: postgres-pvc (1Gi)           │                 │    │
#   │         └──────────────────────────────────┘                 │    │
#   └──────────────────────────────────────────────────────────────┘
#
# Key concepts: multi-service app, shared database, service discovery,
#               Secret reuse across deployments, Ingress path routing,
#               apply order dependencies, image loading into k3d

# ── Step 1: Create namespace and Navigate to the lab directory ────────────────────────────────────
kubectl create namespace microservices

cd labs/06-microservices

# ── Step 2: Build and load the API images into k3d ───────────────────────────
# k3d runs Kubernetes inside Docker. Images built locally are not automatically
# available inside the cluster — they must be explicitly imported.
docker build -t products-api:latest ./products-api
docker build -t users-api:latest ./users-api

k3d image import products-api:latest users-api:latest -c k8s-lab
# Expected: INFO[...] Successfully imported images into 1 cluster(s)
#
# This copies the images into the k3d nodes so imagePullPolicy: IfNotPresent
# finds them locally without needing a registry.

# ── Step 3: Apply manifests in order ─────────────────────────────────────────
# Order matters: the API deployments reference the postgres-secret defined
# in postgres.yaml. Applying the API manifests first would cause the pods to
# be rejected because the Secret doesn't exist yet.
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/postgres.yaml

# Wait for PostgreSQL to be ready before deploying the APIs.
# The APIs will crash on startup if the database is not yet accepting connections.
kubectl rollout status deployment/postgres -n microservices
# Expected: deployment "postgres" successfully rolled out

kubectl apply -f k8s/products-api.yaml
kubectl apply -f k8s/users-api.yaml
kubectl apply -f k8s/ingress.yaml

# ── Step 4: Verify all pods are running ───────────────────────────────────────
kubectl get pods -n microservices -w
# Press Ctrl+C once all 5 pods show READY 1/1:
#   1 x postgres
#   2 x products-api
#   2 x users-api
#
# If any API pod shows CrashLoopBackOff, postgres may still be initialising.
# Check logs: kubectl logs -n microservices -l app=products-api
# Then retry: kubectl rollout restart deployment/products-api -n microservices

# ── Step 5: Check services and ingress ────────────────────────────────────────
kubectl get svc -n microservices
# Expected: postgres-svc (:5432), products-svc (:80), users-svc (:80)

kubectl get ingress -n microservices
# Expected: microservices-ingress routing /products and /users

# ── Step 6: Test the Products API ────────────────────────────────────────────
# The API requires an x-api-key header. The key is "changeme" (set in the Secret).
# Open port 8080 via the PORTS tab in VS Code, or test from the terminal:

# List all products (5 are pre-seeded by the init SQL)
curl -s -H "x-api-key: changeme" http://localhost:8080/products | jq .
# Expected: {"data":[...],"pagination":{"total":5,...}}

# Get a single product by ID
curl -s -H "x-api-key: changeme" http://localhost:8080/products/1 | jq .

# Create a new product
curl -s -X POST \
  -H "x-api-key: changeme" \
  -H "Content-Type: application/json" \
  -d '{"name":"Monitor","price":299.99,"category":"Electronics","stock":10,"sku":"ELEC-MN-006"}' \
  http://localhost:8080/products | jq .
# Expected: {"data":{..."id":6...}}

# Update a product
curl -s -X PUT \
  -H "x-api-key: changeme" \
  -H "Content-Type: application/json" \
  -d '{"stock": 35}' \
  http://localhost:8080/products/1 | jq .

# Delete the product you just created
curl -s -X DELETE \
  -H "x-api-key: changeme" \
  http://localhost:8080/products/6
# Expected: HTTP 204 No Content (no response body)

# ── Step 7: Test the Users API ────────────────────────────────────────────────
# List all users (5 are pre-seeded)
curl -s -H "x-api-key: changeme" http://localhost:8080/users | jq .

# Get a single user
curl -s -H "x-api-key: changeme" http://localhost:8080/users/1 | jq .

# Create a new user
curl -s -X POST \
  -H "x-api-key: changeme" \
  -H "Content-Type: application/json" \
  -d '{"name":"Frank Muller","email":"frank@example.com","role":"customer"}' \
  http://localhost:8080/users | jq .

# ── Step 8: Test health endpoints (no auth required) ──────────────────────────
curl -s http://localhost:8080/products/health | jq .
# Expected: {"status":"ok","service":"products-api","version":"1.0.0",...}

curl -s http://localhost:8080/users/health | jq .
# Expected: {"status":"ok","service":"users-api","version":"1.0.0",...}

# ── Step 9: Test authentication ───────────────────────────────────────────────
# Missing API key → 401
curl -s http://localhost:8080/products | jq .
# Expected: {"error":"Unauthorized — invalid or missing x-api-key header"}

# Wrong API key → 401
curl -s -H "x-api-key: wrongkey" http://localhost:8080/products | jq .
# Expected: {"error":"Unauthorized — invalid or missing x-api-key header"}

# ── Step 10: Explore the Swagger UI ──────────────────────────────────────────
# Both APIs expose interactive documentation at /api-docs.
# Port-forward each API directly (bypassing the Ingress) to browse the full UI:
kubectl port-forward svc/products-svc 3001:80 -n microservices
# Open port 3001 in the PORTS tab → navigate to /api-docs
# Press Ctrl+C when done

kubectl port-forward svc/users-svc 3002:80 -n microservices
# Open port 3002 in the PORTS tab → navigate to /api-docs
# Press Ctrl+C when done

# ── Step 11: Inspect service discovery ───────────────────────────────────────
# The APIs connect to postgres using the Service DNS name "postgres-svc:5432".
# Kubernetes resolves this to the postgres pod's ClusterIP automatically.
# Inspect the DATABASE_URL that was injected via the Secret:
kubectl get secret postgres-secret -n microservices \
  -o jsonpath='{.data.DATABASE_URL}' | base64 --decode
echo ""
# Expected: postgresql://api_user:api_pass@postgres-svc:5432/shared_db
#
# The hostname "postgres-svc" works because a Service of that name exists in
# the same namespace. This is Kubernetes service discovery — pods find each
# other by Service name, never by IP address.

# ── Step 12: Connect to PostgreSQL directly ───────────────────────────────────
PG_POD=$(kubectl get pod -n microservices -l app=postgres \
  -o jsonpath='{.items[0].metadata.name}')

kubectl exec -it $PG_POD -n microservices -- \
  psql -U api_user -d shared_db

# Once inside psql:
#   \dt                              -- list tables (products, users)
#   SELECT * FROM products;          -- view all products
#   SELECT * FROM users;             -- view all users
#   \q                               -- quit psql

# ── Step 13: Verify both APIs write to the same database ─────────────────────
# Create a product via the API
curl -s -X POST \
  -H "x-api-key: changeme" \
  -H "Content-Type: application/json" \
  -d '{"name":"Test Item","price":9.99,"sku":"TEST-001"}' \
  http://localhost:8080/products | jq .id

# Confirm it landed in the shared database
kubectl exec -it $PG_POD -n microservices -- \
  psql -U api_user -d shared_db -c "SELECT id, name FROM products ORDER BY id DESC LIMIT 3;"
# The test item appears — created by the API, visible directly in postgres.

# ── Step 14: Scale an API deployment ─────────────────────────────────────────
# The APIs are stateless — they can be scaled freely. The shared database
# handles concurrent connections from all replicas.
kubectl scale deployment products-api -n microservices --replicas=4
kubectl get pods -n microservices -w
# Press Ctrl+C once all 4 products-api pods are Running

# Scale back down
kubectl scale deployment products-api -n microservices --replicas=2

# ── Step 15: Rotate the API key ───────────────────────────────────────────────
# Update the Secret and restart the pods to pick up the new value.
# The --dry-run=client -o yaml | kubectl apply pattern is idempotent —
# it works whether the Secret already exists or not.
kubectl create secret generic products-api-secret \
  --from-literal=API_KEY=mynewkey \
  -n microservices \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic users-api-secret \
  --from-literal=API_KEY=mynewkey \
  -n microservices \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl rollout restart deployment/products-api deployment/users-api -n microservices
kubectl rollout status deployment/products-api -n microservices

# Test with the new key
curl -s -H "x-api-key: mynewkey" http://localhost:8080/products | jq .data[0].name
# Expected: "Wireless Headphones"

# Restore the original key
kubectl create secret generic products-api-secret \
  --from-literal=API_KEY=changeme \
  -n microservices \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic users-api-secret \
  --from-literal=API_KEY=changeme \
  -n microservices \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl rollout restart deployment/products-api deployment/users-api -n microservices

# ── Step 16: Clean up ────────────────────────────────────────────────────────
kubectl delete namespace microservices
# This deletes all resources including the PVC and its data.


# ── Further Reading ───────────────────────────────────────────────────────────
# Services and DNS:
#   https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/
# Connecting applications with Services:
#   https://kubernetes.io/docs/tutorials/services/connect-applications-service/
# ConfigMaps and Secrets as environment variables:
#   https://kubernetes.io/docs/tasks/inject-data-application/distribute-credentials-secure/

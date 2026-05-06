# Lab 05: Microservices with Postgres

Two Node.js/Express REST APIs sharing a single PostgreSQL database, deployable
via Docker Compose or Kubernetes.

## What You Will Build

```
  Browser / curl
       │
       │ :8080 (Codespace → k3d LoadBalancer)  OR  :3001/:3002 (Docker Compose)
       ▼
  ┌─────────────────────────────────────────────────────────────┐
  │  Traefik Ingress  (K8s only)                                │
  │  /products  ──────────────────────────────────────────────┐ │
  │  /users     ───────────────────────────────────────────┐  │ │
  └────────────────────────────────────────────────────────────┘ │
       │  Namespace: microservices                         │  │
       │                                                   │  │
  ┌────▼──────────────────────┐     ┌─────────────────────▼──┐
  │  Service: products-svc    │     │  Service: users-svc     │
  │  (ClusterIP :80)          │     │  (ClusterIP :80)        │
  └────────────┬──────────────┘     └──────────┬─────────────┘
               │                               │
  ┌────────────▼──────────────┐     ┌──────────▼─────────────┐
  │  Deployment: products-api │     │  Deployment: users-api  │
  │  2 replicas  port 3001    │     │  2 replicas  port 3002  │
  │  Node.js / Express        │     │  Node.js / Express      │
  │  GET/POST/PUT/DELETE      │     │  GET/POST/PUT/DELETE    │
  │  /products                │     │  /users                 │
  └────────────┬──────────────┘     └──────────┬─────────────┘
               │                               │
               └───────────────┬───────────────┘
                               │ DATABASE_URL (shared)
                               ▼
              ┌────────────────────────────────────┐
              │  Deployment: postgres               │
              │  Service: postgres-svc :5432        │
              │                                    │
              │  ┌─────────────┐ ┌──────────────┐  │
              │  │  products   │ │    users     │  │
              │  │   table     │ │    table     │  │
              │  └─────────────┘ └──────────────┘  │
              │                                    │
              │  PersistentVolumeClaim (1Gi)        │
              └────────────────────────────────────┘
```

Both APIs are protected by an API key (`x-api-key` header). Auth is handled
in middleware — not in the database layer — so both services share the DB
without sharing credentials logic.

## Quick Start — Docker Compose

```bash
cd labs/05-microservices

# Start everything (postgres + both APIs)
docker compose up --build

# Verify
curl http://localhost:3001/health
curl http://localhost:3002/health

# Call the APIs (API key required)
curl -H "x-api-key: changeme" http://localhost:3001/products
curl -H "x-api-key: changeme" http://localhost:3002/users
```

Swagger docs:
- Products: http://localhost:3001/api-docs
- Users:    http://localhost:3002/api-docs

## Quick Start — Kubernetes (k3d)

### 1. Build images and import into the k3d cluster

```bash
cd labs/05-microservices

docker build -t products-api:latest ./products-api
docker build -t users-api:latest    ./users-api

k3d image import products-api:latest users-api:latest -c k8s-lab
```

### 2. Apply manifests

Apply the files **one at a time in this order** — the API deployments reference a
Secret defined in `postgres.yaml`, so that must exist before the APIs are created.
Using `kubectl apply -f k8s/` applies all files at once with no guaranteed order
and will cause the API pods to fail with `CreateContainerConfigError`.

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/postgres.yaml
kubectl apply -f k8s/products-api.yaml
kubectl apply -f k8s/users-api.yaml
kubectl apply -f k8s/ingress.yaml
```

### 3. Wait for pods to be ready

```bash
kubectl get pods -n microservices -w
# Press Ctrl+C once all pods show Running
```

### 4. Test via Ingress on port 8080

```bash
curl -H "x-api-key: changeme" http://localhost:8080/products
curl -H "x-api-key: changeme" http://localhost:8080/users
```

Or port-forward individual services:
```bash
kubectl port-forward svc/products-svc 3001:80 -n microservices
kubectl port-forward svc/users-svc    3002:80 -n microservices
```

## API Endpoints

### Products API (port 3001)

| Method | Path          | Auth | Description           |
|--------|---------------|------|-----------------------|
| GET    | /health       | No   | Health check          |
| GET    | /api-docs     | No   | Swagger UI            |
| GET    | /products     | Yes  | List products (paged) |
| POST   | /products     | Yes  | Create product        |
| GET    | /products/:id | Yes  | Get product by ID     |
| PUT    | /products/:id | Yes  | Update product        |
| DELETE | /products/:id | Yes  | Delete product        |

### Users API (port 3002)

| Method | Path       | Auth | Description        |
|--------|------------|------|--------------------|
| GET    | /health    | No   | Health check       |
| GET    | /api-docs  | No   | Swagger UI         |
| GET    | /users     | Yes  | List users (paged) |
| POST   | /users     | Yes  | Create user        |
| GET    | /users/:id | Yes  | Get user by ID     |
| PUT    | /users/:id | Yes  | Update user        |
| DELETE | /users/:id | Yes  | Delete user        |

## Authentication

Both APIs use an `x-api-key` header. Default key is `changeme`.

```bash
curl -H "x-api-key: changeme" http://localhost:3001/products
```

Set `AUTH_MODE=none` in environment to disable auth (dev only).

## Pagination

All list endpoints support `?page=1&limit=10`:

```json
{
  "data": [...],
  "pagination": {
    "total": 8, "page": 1, "limit": 10,
    "totalPages": 1, "hasNext": false, "hasPrev": false
  }
}
```

## Environment Variables

| Variable               | Default                                                   | Description             |
|------------------------|-----------------------------------------------------------|-------------------------|
| `PORT`                 | 3001 / 3002                                               | API listen port         |
| `AUTH_MODE`            | `apikey`                                                  | `apikey` or `none`      |
| `API_KEY`              | `changeme`                                                | API key value           |
| `DATABASE_URL`         | `postgresql://api_user:api_pass@localhost:5432/shared_db` | Postgres connection URL |
| `RATE_LIMIT_WINDOW_MS` | `60000`                                                   | Rate limit window (ms)  |
| `RATE_LIMIT_MAX`       | `100`                                                     | Max requests per window |

## Project Structure

```
05-microservices/
├── docker-compose.yml
├── init-db/
│   └── 01-init.sql         ← creates tables + seeds data on first start
├── k8s/
│   ├── namespace.yaml
│   ├── postgres.yaml        ← Deployment, Service, PVC, ConfigMap
│   ├── products-api.yaml    ← Deployment, Service, Secret (2 replicas)
│   ├── users-api.yaml       ← Deployment, Service, Secret (2 replicas)
│   └── ingress.yaml         ← Traefik routes /products and /users
├── products-api/
│   ├── Dockerfile
│   ├── openapi.yaml
│   └── src/
│       ├── app.js
│       ├── index.js
│       ├── routes/          ← health, products
│       ├── controllers/     ← products
│       ├── middleware/      ← auth, pagination
│       ├── db/              ← client.js, schema.sql
│       └── data/            ← seed.js
└── users-api/
    ├── Dockerfile
    ├── openapi.yaml
    └── src/
        ├── app.js
        ├── index.js
        ├── routes/          ← health, users
        ├── controllers/     ← users
        ├── middleware/      ← auth, pagination
        ├── db/              ← client.js, schema.sql
        └── data/            ← seed.js
```
## Cleanup

**Docker Compose:**
```bash
docker compose down -v
```
The `-v` flag removes the postgres volume so the database is fully reset on next `up`.

**Kubernetes:**
```bash
kubectl delete namespace microservices
```
This removes all resources in the namespace — Deployments, Services, Secrets, the PersistentVolumeClaim, and the Postgres data volume.

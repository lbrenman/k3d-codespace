# Microservices Lab — Products & Users APIs

Two Node.js/Express REST APIs sharing a single PostgreSQL database, deployable via Docker Compose or Kubernetes (k3d).

## Architecture

```
                    ┌─────────────────────────────────┐
                    │         Shared PostgreSQL        │
                    │  ┌─────────────┐ ┌───────────┐  │
                    │  │  products   │ │   users   │  │
                    │  │   table     │ │   table   │  │
                    │  └─────────────┘ └───────────┘  │
                    └────────────┬────────────┬────────┘
                                 │            │
              ┌──────────────────┘            └──────────────────┐
              │                                                   │
   ┌──────────▼──────────┐                         ┌─────────────▼──────┐
   │    products-api      │                         │     users-api       │
   │    port 3001         │                         │     port 3002       │
   │  GET/POST/PUT/DELETE │                         │  GET/POST/PUT/DELETE│
   │    /products         │                         │      /users         │
   └─────────────────────┘                         └────────────────────┘
```

## Quick Start — Docker Compose

```bash
# Start everything (postgres + both APIs)
docker compose up --build

# Verify
curl http://localhost:3001/health
curl http://localhost:3002/health

# Call an API (API key required)
curl -H "x-api-key: changeme" http://localhost:3001/products
curl -H "x-api-key: changeme" http://localhost:3002/users
```

Swagger docs:
- Products: http://localhost:3001/api-docs
- Users:    http://localhost:3002/api-docs

## Quick Start — Kubernetes (k3d)

### 1. Build images into the k3d cluster registry

```bash
# Build images
docker build -t products-api:latest ./products-api
docker build -t users-api:latest    ./users-api

# Import into k3d (no registry needed)
k3d image import products-api:latest -c k8s-lab
k3d image import users-api:latest    -c k8s-lab
```

### 2. Apply manifests

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

### 4. Test via Ingress (port 8080 → k3d LoadBalancer)

```bash
curl http://localhost:8080/health          # 404 (no root route via ingress)
curl http://localhost:8080/products/health # ← note: path prefix is /products
curl -H "x-api-key: changeme" http://localhost:8080/products
curl -H "x-api-key: changeme" http://localhost:8080/users
```

> **Tip:** You can also port-forward individual services:
> ```bash
> kubectl port-forward svc/products-svc 3001:80 -n microservices
> kubectl port-forward svc/users-svc    3002:80 -n microservices
> ```

## API Endpoints

### Products API (port 3001)

| Method | Path           | Auth | Description           |
|--------|----------------|------|-----------------------|
| GET    | /health        | No   | Health check          |
| GET    | /api-docs      | No   | Swagger UI            |
| GET    | /products      | Yes  | List products (paged) |
| POST   | /products      | Yes  | Create product        |
| GET    | /products/:id  | Yes  | Get product by ID     |
| PUT    | /products/:id  | Yes  | Update product        |
| DELETE | /products/:id  | Yes  | Delete product        |

### Users API (port 3002)

| Method | Path        | Auth | Description        |
|--------|-------------|------|--------------------|
| GET    | /health     | No   | Health check       |
| GET    | /api-docs   | No   | Swagger UI         |
| GET    | /users      | Yes  | List users (paged) |
| POST   | /users      | Yes  | Create user        |
| GET    | /users/:id  | Yes  | Get user by ID     |
| PUT    | /users/:id  | Yes  | Update user        |
| DELETE | /users/:id  | Yes  | Delete user        |

## Authentication

Both APIs use an `x-api-key` header. Default key is `changeme`.

```bash
curl -H "x-api-key: changeme" http://localhost:3001/products
```

Set `AUTH_MODE=none` in the environment to disable auth (dev only).

## Pagination

All list endpoints support `?page=1&limit=10`. Response envelope:

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

| Variable               | Default                                           | Description              |
|------------------------|---------------------------------------------------|--------------------------|
| `PORT`                 | 3001 / 3002                                       | API listen port          |
| `AUTH_MODE`            | `apikey`                                          | `apikey` or `none`       |
| `API_KEY`              | `changeme`                                        | API key value            |
| `DATABASE_URL`         | `postgresql://api_user:api_pass@localhost:5432/shared_db` | Postgres URL |
| `RATE_LIMIT_WINDOW_MS` | `60000`                                           | Rate limit window (ms)   |
| `RATE_LIMIT_MAX`       | `100`                                             | Max requests per window  |

## Project Structure

```
microservices-lab/
├── docker-compose.yml          # Full stack — postgres + both APIs
├── init-db/
│   └── 01-init.sql             # Creates tables + seeds data on first start
├── k8s/
│   ├── namespace.yaml
│   ├── postgres.yaml           # Postgres Deployment + Service + PVC + ConfigMap
│   ├── products-api.yaml       # Products Deployment + Service + Secret
│   ├── users-api.yaml          # Users Deployment + Service + Secret
│   └── ingress.yaml            # Traefik Ingress routing /products and /users
├── products-api/
│   ├── Dockerfile
│   ├── openapi.yaml
│   ├── .env.example
│   └── src/
│       ├── index.js
│       ├── app.js
│       ├── routes/             # health, products
│       ├── controllers/        # products
│       ├── middleware/         # auth, pagination
│       ├── db/                 # client.js, schema.sql
│       └── data/               # seed.js
└── users-api/
    ├── Dockerfile
    ├── openapi.yaml
    ├── .env.example
    └── src/
        ├── index.js
        ├── app.js
        ├── routes/             # health, users
        ├── controllers/        # users
        ├── middleware/         # auth, pagination
        ├── db/                 # client.js, schema.sql
        └── data/               # seed.js
```

# K3d Kubernetes Learning Environment

A GitHub Codespace-based Kubernetes learning environment using **k3d** — fast, lightweight, and built for teaching.

## What's Included

| Tool | Purpose |
|------|---------|
| **k3d** | Runs a multi-node K8s cluster in Docker |
| **kubectl** | K8s CLI (with aliases pre-configured) |
| **helm** | Package manager for K8s |
| **k9s** | Terminal UI dashboard for the cluster |
| **stern** | Multi-pod log tailing |
| **kubectx/kubens** | Fast context and namespace switching |
| **Traefik** | Built-in ingress controller (via k3d) |

## Cluster Layout

```
k3d cluster: k8s-lab
├── server-0   (control plane)
├── agent-0    (worker node)
└── agent-1    (worker node)

Port mappings (Codespace → cluster):
  8080 → LoadBalancer :80   (HTTP ingress)
  8443 → LoadBalancer :443  (HTTPS ingress)
```

## Quick Start

The cluster starts automatically when the Codespace launches.

```bash
# Check cluster health
kubectl get nodes
kubectl get pods -A

# Launch terminal UI
k9s
```

## Helpful Aliases

| Alias | Command |
|-------|---------|
| `k` | `kubectl` |
| `kgp` | `kubectl get pods` |
| `kgs` | `kubectl get svc` |
| `kgd` | `kubectl get deployments` |
| `kga` | `kubectl get all` |
| `kaf` | `kubectl apply -f` |
| `kdf` | `kubectl delete -f` |
| `kl` | `kubectl logs` |
| `kns` | `kubens` (switch namespace) |
| `kctx` | `kubectx` (switch context) |

## Labs

Work through the labs in order. Each builds on concepts from the previous one.

### Lab 1 — First Deployment (`labs/lab1-first-deployment.sh`)
Deploy nginx, create a Service, port-forward and test, scale the deployment.

### Lab 2 — Ingress with Traefik (`labs/lab2-ingress-traefik.sh`)
Deploy two apps, route traffic by path using Traefik Ingress, access via Codespace port 8080, explore the Traefik dashboard.

### Lab 3 — ConfigMaps & Secrets (`labs/lab3-configmaps-secrets.sh`)
Create a ConfigMap and Secret, consume both in a Deployment via env vars and volume mounts, update config and observe behavior.

### Lab 4 — Microservices with Postgres (`labs/lab4-microservices/`)
A realistic multi-service project: two Node.js/Express REST APIs (Products and Users) sharing a single PostgreSQL database. Deployable via Docker Compose or Kubernetes. Covers Deployments, Services, Secrets, PersistentVolumeClaims, and Traefik Ingress routing across multiple services.

> **Prerequisites for Lab 4:** Build the Docker images and import them into the cluster before applying K8s manifests — see `labs/lab4-microservices/README.md` for full instructions.

## Cluster Management

```bash
# List clusters
k3d cluster list

# Stop cluster (preserves state)
k3d cluster stop k8s-lab

# Start cluster again
k3d cluster start k8s-lab

# Delete and recreate from scratch
k3d cluster delete k8s-lab
bash .devcontainer/scripts/start-cluster.sh
```

## Port Forwarding Tips

Codespace port forwarding works out of the box for:
- `kubectl port-forward` — any pod or service port
- The k3d load balancer ports **8080** and **8443** — for ingress traffic

In VS Code, open the **PORTS** tab to see forwarded ports and their public URLs.

## Troubleshooting

**Cluster not running after Codespace restart?**
```bash
bash .devcontainer/scripts/start-cluster.sh
```

**kubectl: connection refused?**
```bash
k3d kubeconfig merge k8s-lab --kubeconfig-switch-context
kubectl config use-context k3d-k8s-lab
```

**Pod stuck in Pending?**
```bash
kubectl describe pod <pod-name> -n <namespace>
# Look at the Events section at the bottom
```

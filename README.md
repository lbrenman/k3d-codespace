# K3d Kubernetes Learning Environment

A GitHub Codespace-based Kubernetes learning environment using **k3d** — fast, lightweight, and built for teaching.

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/lbrenman/k3d-codespace)

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

## Understanding Servers and Agents

A Kubernetes cluster is made up of nodes with two distinct roles:

**Server (Control Plane)**
The server node is the brain of the cluster. It runs the core Kubernetes system
components — the API server (what kubectl talks to), the scheduler (decides which
node runs which pod), and the controller manager (maintains desired state). All
cluster decisions are made here. You generally don't run your own application
workloads on the server.

**Agents (Worker Nodes)**
Agent nodes are the muscle. They register with the server and wait for
instructions. When you deploy an app, the scheduler assigns pods to agent nodes,
which then pull the container image and run it. All your actual application
workloads run here.

**Why two agents?**
It mirrors a realistic production setup where you'd never run everything on one
machine. With two agents you can observe how Kubernetes distributes pods across
nodes, see what happens when you scale a deployment (pods spread across both
agents), and explore scheduling behavior. With only one agent, all pods would
always land in the same place — hiding a lot of interesting behavior.

```
┌─────────────────────────────────────────────────────────┐
│                    k3d cluster: k8s-lab                  │
│                                                          │
│  ┌─────────────────────────────────┐                    │
│  │  server-0  (control plane)      │                    │
│  │  ┌──────────┐  ┌─────────────┐  │                    │
│  │  │ API      │  │ Scheduler / │  │                    │
│  │  │ Server   │  │ Controllers │  │                    │
│  │  └──────────┘  └─────────────┘  │                    │
│  └─────────────────────────────────┘                    │
│                                                          │
│  ┌──────────────────┐  ┌──────────────────┐             │
│  │  agent-0         │  │  agent-1         │             │
│  │  (worker node)   │  │  (worker node)   │             │
│  │  runs your pods  │  │  runs your pods  │             │
│  └──────────────────┘  └──────────────────┘             │
│                                                          │
│  ┌──────────────────────────────────────────┐           │
│  │  LoadBalancer  :8080 → :80               │           │
│  │                :8443 → :443              │           │
│  └──────────────────────────────────────────┘           │
└─────────────────────────────────────────────────────────┘
```

Verify this yourself after the cluster starts:
```bash
kubectl get nodes
# NAME                    STATUS   ROLES           AGE
# k3d-k8s-lab-server-0   Ready    control-plane   1m
# k3d-k8s-lab-agent-0    Ready    <none>          1m
# k3d-k8s-lab-agent-1    Ready    <none>          1m
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

Each lab uses its own Kubernetes namespace (`lab1`, `lab2`, etc.), so all labs
can run simultaneously without any conflicts. The cleanup command at the end of
each lab is optional — skip it if you want to keep multiple labs running at the
same time. A standard Codespace (2 cores, 8GB RAM) handles all labs comfortably.

Check resource usage across all running labs at any time:
```bash
kubectl top nodes
kubectl top pods -A
```

### Lab 1 — First Deployment (`labs/lab1-first-deployment.sh`)
Deploy nginx, create a ClusterIP Service, port-forward and test, scale the deployment.

### Lab 2 — Ingress with Traefik (`labs/lab2-ingress-traefik.sh`)
Deploy two apps, route traffic by path using Traefik Ingress, access via Codespace port 8080, explore the Traefik dashboard.

### Lab 3 — ConfigMaps & Secrets (`labs/lab3-configmaps-secrets.sh`)
Create a ConfigMap and Secret, consume both in a Deployment via env vars and volume mounts, update config and observe behavior.

### Lab 4 — Microservices with Postgres (`labs/lab4-microservices/`)
A realistic multi-service project: two Node.js/Express REST APIs (Products and Users) sharing a single PostgreSQL database. Deployable via Docker Compose or Kubernetes. Covers Deployments, Services, Secrets, PersistentVolumeClaims, and Traefik Ingress routing across multiple services.

> **Prerequisites for Lab 4:** Apply manifests one file at a time in order — see `labs/lab4-microservices/README.md` for full instructions.

### Lab 5 — Helm Charts: Prometheus & Grafana (`labs/lab5-helm/lab5-helm-charts.sh`)
Learn Helm — the Kubernetes package manager. Install the kube-prometheus-stack chart to deploy a full Prometheus + Grafana monitoring stack, customize it with a `values.yaml` file and `--set` flags, upgrade the release, roll back to a previous revision, and inspect the underlying chart templates.

### Lab 6 — RBAC (`labs/lab6-rbac.sh`)
Learn how Kubernetes controls access using Role-Based Access Control. Create ServiceAccounts, Roles, and RoleBindings to grant fine-grained permissions to pods. Verify permissions with `kubectl auth can-i`, observe a pod interacting with the K8s API using its ServiceAccount token, and understand the difference between namespace-scoped Roles and cluster-wide ClusterRoles.

### Lab 7 — Jobs & CronJobs (`labs/lab7-jobs.sh`)
Explore Kubernetes batch workloads. Run a one-off Job to completion, process work in parallel with multiple pod completions, schedule recurring tasks with a CronJob, manually trigger a CronJob run, suspend and resume a schedule, and observe automatic retry behavior when a Job fails.

### Lab 8 — Resource Limits & Autoscaling (`labs/lab8-autoscaling.sh`)
Learn how to set CPU and memory requests and limits on pods, then use the Horizontal Pod Autoscaler (HPA) to automatically scale a deployment up and down based on live CPU usage. Includes a load generator to trigger real scaling events and a demonstration of why resource requests are required for HPA to function.

### Lab 9 — Health Checks & Self-Healing (`labs/lab9-probes.sh`)
Deep dive into Kubernetes probes — liveness, readiness, and startup. Observe a liveness failure trigger an automatic restart, a readiness failure remove a pod from the load balancer without restarting it, and a startup probe protect a slow-starting container from premature liveness checks. Ends with the full production pattern used in Lab 4.

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

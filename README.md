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

Work through the labs in order — each one builds on concepts from the previous.
All labs use their own Kubernetes namespace so they can run simultaneously
without conflict. A standard Codespace (2 cores, 8GB RAM) handles all labs
comfortably at once. Cleanup at the end of each lab is optional.

Check resource usage across all running labs at any time:
```bash
kubectl top nodes
kubectl top pods -A
```

| # | Folder | Topic | Rationale |
|---|--------|-------|-----------|
| 01 | `01-first-deployment/` | First Deployment | Core primitives first — pods, services, scaling |
| 02 | `02-configmaps-secrets/` | ConfigMaps & Secrets | App configuration before building anything real |
| 03 | `03-health-checks/` | Health Checks & Probes | Foundational — every real app needs them |
| 04 | `04-ingress-traefik/` | Ingress with Traefik | Exposing apps — natural next step |
| 05 | `05-microservices/` | Microservices + Postgres | Real multi-service API using everything so far |
| 06 | `06-gitea/` | Gitea + PostgreSQL | Real web app with persistent storage |
| 07 | `07-autoscaling/` | Resource Limits & Autoscaling | Tune and scale apps already running |
| 08 | `08-rolling-updates/` | Rolling Updates & Rollback | Production deploy patterns |
| 09 | `09-helm/` | Helm + Prometheus/Grafana | Package management and monitoring |
| 10 | `10-jobs-cronjobs/` | Jobs & CronJobs | Batch workloads — a distinct pattern |
| 11 | `11-rbac/` | RBAC | Access control — ops/security topic |
| 12 | `12-k9s/` | k9s | Terminal UI — work faster with the cluster |
| 13 | `13-pod-filesystem/` | Pod Filesystems & Logs | Find and read log files inside containers |
| 14 | `14-troubleshooting/` | Troubleshooting | Diagnose and fix the most common pod failures |

### Lab 01 — First Deployment (`labs/01-first-deployment/lab.md`)
Deploy nginx, create a ClusterIP Service, port-forward and test, scale the deployment. Introduces pods, ReplicaSets, Deployments, and Services.

### Lab 02 — ConfigMaps & Secrets (`labs/02-configmaps-secrets/lab.md`)
Create a ConfigMap and Secret, consume both in a Deployment via env vars and volume mounts, update config and observe the difference in behavior between the two.

### Lab 03 — Health Checks & Probes (`labs/03-health-checks/lab.md`)
Deep dive into liveness, readiness, and startup probes. Observe a liveness failure trigger a restart, a readiness failure remove a pod from the load balancer without restarting it, and a startup probe protect a slow-starting container.

### Lab 04 — Ingress with Traefik (`labs/04-ingress-traefik/lab.md`)
Deploy two apps and route traffic by URL path using Traefik Ingress. Access via Codespace port 8080 and explore the Traefik dashboard.

### Lab 05 — Microservices + Postgres (`labs/05-microservices/`)
A realistic multi-service project: two Node.js/Express REST APIs (Products and Users) sharing a PostgreSQL database. Deployable via Docker Compose or Kubernetes. See `labs/05-microservices/README.md` for full instructions.

> **Note:** Apply K8s manifests one file at a time in order — the API deployments depend on a Secret defined in `postgres.yaml`.

### Lab 06 — Gitea + PostgreSQL (`labs/06-gitea/lab.md`)
Deploy Gitea — a lightweight self-hosted Git server — backed by PostgreSQL. Introduces PersistentVolumeClaims in a practical context and demonstrates that data (repositories, config) survives pod restarts. Access via Traefik Ingress on port 8080.

### Lab 07 — Resource Limits & Autoscaling (`labs/07-autoscaling/lab.md`)
Set CPU and memory requests and limits on pods, then use the Horizontal Pod Autoscaler (HPA) to scale automatically based on live CPU usage. Includes a load generator to trigger real scaling events.

### Lab 08 — Rolling Updates & Rollback (`labs/08-rolling-updates/lab.md`)
Deploy a 4-replica app, stream live traffic through it, perform a rolling update, simulate a broken release, and roll back — all while the service stays up. Also covers pausing rollouts for canary-style deploys.

### Lab 09 — Helm + Prometheus/Grafana (`labs/09-helm/lab.md`)
Learn Helm — the Kubernetes package manager. Install the kube-prometheus-stack chart, customize it with a `values.yaml` and `--set` flags, upgrade, roll back, and inspect chart templates.

> **Note:** Run from inside `labs/09-helm/` — the lab creates a `values.yaml` file in the current directory.

### Lab 10 — Jobs & CronJobs (`labs/10-jobs-cronjobs/lab.md`)
Run a one-off Job to completion, process work in parallel, schedule recurring tasks with a CronJob, manually trigger runs, suspend and resume schedules, and observe retry behavior on failure.

### Lab 11 — RBAC (`labs/11-rbac/lab.md`)
Control access using Role-Based Access Control. Create ServiceAccounts, Roles, and RoleBindings, verify permissions with `kubectl auth can-i`, and observe a pod interacting with the K8s API using its ServiceAccount token.

### Lab 12 — k9s (`labs/12-k9s/lab.md`)
Learn k9s — the terminal UI for Kubernetes. Navigate resources, stream logs, exec into containers, port-forward, edit resources live, and view cluster-wide resource usage, all without typing kubectl commands.

### Lab 13 — Pod Filesystems & Logs (`labs/13-pod-filesystem/lab.md`)
Learn how to find and read log files inside running containers. Covers three patterns: stdout logging (the Kubernetes-native approach), log files on the container filesystem accessed via kubectl exec and kubectl cp, and the sidecar pattern for streaming app log files to stdout via a shared volume.

### Lab 14 — Troubleshooting (`labs/14-troubleshooting/lab.md`)
Deliberately break pods in six different ways and learn to diagnose and fix each one: CrashLoopBackOff, OOMKilled, ImagePullBackOff, Pending (scheduling failure), CreateContainerConfigError (missing Secret), and a running-but-broken service with the wrong targetPort.


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

### Cluster issues

**Cluster not running after Codespace restart?**
```bash
bash .devcontainer/scripts/start-cluster.sh
```

**kubectl: connection refused?**
```bash
k3d kubeconfig merge k8s-lab --kubeconfig-switch-context
kubectl config use-context k3d-k8s-lab
```

**TLS certificate error when running `kubectl logs` or `kubectl exec`?**

This happens when the Codespace restarts and node IPs change but the cluster certificates are not updated. Symptoms look like:
```
x509: certificate is valid for 172.18.0.3, not 172.18.0.2
```
Fix — delete and recreate the cluster entirely:
```bash
k3d cluster delete k8s-lab
bash .devcontainer/scripts/start-cluster.sh
```

**Cluster nodes show NotReady after restart?**
```bash
# Wait ~60s then check again
kubectl get nodes
# If still NotReady, recreate the cluster:
k3d cluster delete k8s-lab
bash .devcontainer/scripts/start-cluster.sh
```

---

### Pod issues

**Pod stuck in Pending?**
```bash
kubectl describe pod <pod-name> -n <namespace>
# Look at the Events section — common causes:
#   "insufficient cpu/memory" → resource requests too high
#   "no nodes available"      → cluster not running
```

**Pod in CrashLoopBackOff?**
```bash
# Check exit code and last state
kubectl describe pod <pod-name> -n <namespace>

# Read logs from the previous (crashed) container
kubectl logs <pod-name> -n <namespace> --previous
```

**Pod in ImagePullBackOff?**
```bash
kubectl describe pod <pod-name> -n <namespace>
# Look in Events for the specific pull error — usually a typo in the image tag
```

**CreateContainerConfigError?**
```bash
kubectl describe pod <pod-name> -n <namespace>
# Usually means a referenced Secret or ConfigMap doesn't exist yet
# Check: kubectl get secrets -n <namespace>
#        kubectl get configmaps -n <namespace>
```

**Pod running but not responding?**
```bash
# Check if the Service targetPort matches the container port
kubectl describe svc <service-name> -n <namespace>
kubectl describe pod <pod-name> -n <namespace> | grep -A5 "Ports:"
```

---

### Port forwarding issues

**`kubectl port-forward` stops working after a pod restarts?**

Port-forward binds to a specific pod. When the pod is deleted and recreated, the connection drops. Restart the port-forward:
```bash
kubectl port-forward svc/<service-name> <local-port>:<service-port> -n <namespace>
```

**Visiting `localhost:<port>` in browser gives "site can't be reached"?**

In a Codespace, `localhost` in your local browser doesn't reach the Codespace. Use the forwarded URL from the **PORTS** tab in VS Code instead — it looks like:
```
https://<your-codespace-name>-<port>.app.github.dev
```

**Port 8080 shows the wrong app?**

Multiple labs use the k3d LoadBalancer on port 8080 via Ingress. If two labs are running simultaneously with conflicting `/` path rules, traffic goes to whichever was deployed first. Either clean up the other lab's Ingress or use `kubectl port-forward` with a different port number for one of them.

---

### Helm issues

**`helm install` fails partway through / was interrupted?**
```bash
# Remove the partial release and retry
helm uninstall <release-name> -n <namespace>
helm install ...
```

**`helm install` hangs with `--wait`?**
```bash
# Open a second terminal and check pod status
kubectl get pods -n <namespace> -w
# If pods are stuck, describe them to find the cause
kubectl describe pod <pod-name> -n <namespace>
```

---

### General diagnostic commands

```bash
# See everything in a namespace at a glance
kubectl get all -n <namespace>

# Full detail on any resource (always check Events at the bottom)
kubectl describe <resource-type> <name> -n <namespace>

# All events in a namespace sorted by time
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# Check resource usage across all pods
kubectl top pods -A --sort-by=cpu
kubectl top nodes

# Check cluster component health
kubectl get nodes
kubectl get pods -n kube-system
```
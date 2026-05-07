# Lab 12: k9s — Terminal UI for Kubernetes
# ─────────────────────────────────────────────────────────────────────────────
# k9s is a terminal-based UI that sits on top of kubectl and makes navigating
# a Kubernetes cluster much faster. Instead of typing long kubectl commands,
# you navigate with keyboard shortcuts, drill into resources, view logs, exec
# into containers, and manage workloads — all without leaving your terminal.
#
# HOW TO USE THIS LAB:
#   This lab is different from the others — most of it is interactive inside
#   k9s itself rather than copy-pasting commands. Follow the steps sequentially
#   and use the keyboard shortcuts shown at the top of the k9s screen.
#
# What you will learn:
#
#   ┌──────────────────────────────────────────────────────────────────┐
#   │  k9s navigation model                                           │
#   │                                                                  │
#   │  : (colon)  → command mode — type a resource name to jump to it │
#   │  /          → filter/search within the current view             │
#   │  enter      → drill into a resource                             │
#   │  esc        → go back / exit current view                       │
#   │  l          → view logs for selected pod                        │
#   │  s          → shell (exec) into selected container              │
#   │  d          → describe selected resource                        │
#   │  e          → edit selected resource (opens in $EDITOR)         │
#   │  ctrl-d     → delete selected resource                          │
#   │  ctrl-k     → kill (force delete) selected resource             │
#   │  ?          → help — show all shortcuts for current view        │
#   └──────────────────────────────────────────────────────────────────┘
#
# Key concepts: k9s navigation, resource views, log streaming,
#               exec into containers, port-forward from k9s, filtering

# ── Step 1: Deploy some workloads to explore ──────────────────────────────────
# We need a few running resources to make the lab interesting.
# This deploys two apps across two namespaces.
kubectl create namespace lab12

kubectl apply -n lab12 -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 50m
            memory: 32Mi
---
apiVersion: v1
kind: Service
metadata:
  name: web-svc
spec:
  selector:
    app: web
  ports:
  - port: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
      - name: api
        image: hashicorp/http-echo:latest
        args: ["-text=Hello from the API"]
        ports:
        - containerPort: 5678
        resources:
          requests:
            cpu: 50m
            memory: 32Mi
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  ENV: production
  VERSION: "1.0.0"
---
apiVersion: v1
kind: Secret
metadata:
  name: app-secret
type: Opaque
stringData:
  API_KEY: supersecret123
YAML

kubectl get pods -n lab12 -w
# Press Ctrl+C once all pods show READY 1/1

# ── Step 2: Launch k9s ───────────────────────────────────────────────────────
k9s
# k9s opens to the Pods view of your default namespace.
# The header shows the current context and namespace.
# The footer shows available keyboard shortcuts for the current view.

# ── Step 3: Navigate namespaces ──────────────────────────────────────────────
# When k9s is open:
#
# Press 0       → show pods in ALL namespaces
# Press :ns     → jump to the Namespaces view
#                 Use arrow keys to select lab12, press enter to set it
# Press :pods   → jump back to Pods view (now filtered to lab12)

# ── Step 4: Explore pods ──────────────────────────────────────────────────────
# In the Pods view:
#
# Arrow keys    → move between pods
# enter         → drill into a pod (shows its containers)
# d             → describe the selected pod (same as kubectl describe)
# l             → stream logs from the selected pod
#                 Press esc to stop log streaming
# s             → open a shell inside the container
#                 Try: ls /usr/share/nginx/html
#                 Type exit to close the shell
# ctrl-d        → delete the selected pod (Kubernetes will recreate it)

# ── Step 5: Filter pods ───────────────────────────────────────────────────────
# In the Pods view:
#
# Press /       → enter filter mode
# Type "web"    → only pods with "web" in their name are shown
# Press esc     → clear the filter

# ── Step 6: Navigate to other resource types ─────────────────────────────────
# Press : (colon) to enter command mode, then type a resource name:
#
# :deploy       → Deployments view
#                 Press enter on a deployment to see its pods
# :svc          → Services view
# :cm           → ConfigMaps view
#                 Press enter on app-config to see its data
# :secret       → Secrets view
#                 Press x on app-secret to decode and view secret values
# :pvc          → PersistentVolumeClaims view
# :ing          → Ingress view
# :nodes        → Nodes view — shows CPU/memory usage per node
# :events       → Events view — same as kubectl get events, live updating

# ── Step 7: Port-forward from k9s ─────────────────────────────────────────────
# k9s can manage port-forwards without you having to type kubectl commands.
#
# Navigate to Pods view (:pods)
# Select one of the web pods
# Press shift-f       → opens port-forward dialog
# Enter local port:   8090
# Enter container port: 80
# Press enter to start the port-forward
#
# Open the PORTS tab in VS Code — port 8090 will appear.
# Click the globe icon to open it in your browser.
# Press esc in k9s to stop the port-forward when done.

# ── Step 8: View resource usage ───────────────────────────────────────────────
# Navigate to Nodes view:
# :nodes
# You will see CPU and memory usage per node, updated live.
#
# Navigate to Pods view with resource columns:
# :pods
# Press ctrl-e       → toggle resource usage columns (CPU/MEM)
# You can see which pods are consuming the most resources at a glance.

# ── Step 9: Edit a resource live ──────────────────────────────────────────────
# Navigate to Deployments view:
# :deploy
# Select the "web" deployment
# Press e            → opens the deployment YAML in your editor
# Change replicas from 3 to 1
# Save and close the editor
# k9s applies the change immediately — watch the pods in :pods

# ── Step 10: View logs across multiple pods ───────────────────────────────────
# Navigate to Deployments view:
# :deploy
# Select the "web" deployment
# Press l            → streams logs from ALL pods in the deployment at once
#                      Each line is prefixed with the pod name
# Press esc to stop

# ── Step 11: Use the pulses view ─────────────────────────────────────────────
# :pulses           → shows a live dashboard of cluster activity
#                     CPU, memory, pod counts, and events all in one view
#
# :xray deploy lab12 → X-Ray view — shows a tree of deployment → replicaset
#                      → pods, with health indicators for each level

# ── Step 12: Useful k9s command reference ─────────────────────────────────────
# Here are the most useful commands to remember after the lab:
#
# Launch with a specific namespace:
#   k9s -n lab12
#
# Launch focused on a specific resource:
#   k9s --command pods
#
# Common resource aliases in k9s:
#   :pods  :deploy  :svc  :ing  :cm  :secret  :pvc  :nodes  :events
#   :ns    :sa      :rb   :cr   :hpa :job     :cj   :ep
#
# Universal shortcuts:
#   ?        help for current view
#   :q       quit k9s
#   ctrl-c   also quits

# ── Step 13: Clean up ────────────────────────────────────────────────────────
# You can delete the namespace from inside k9s:
#   :ns → select lab12 → ctrl-d
#
# Or from the terminal after exiting k9s (press :q):
kubectl delete namespace lab12

# ── Further Reading ───────────────────────────────────────────────────────────
# k9s documentation:
#   https://k9scli.io/
# k9s GitHub:
#   https://github.com/derailed/k9s
# k9s keyboard shortcuts cheatsheet:
#   https://k9scli.io/topics/commands/

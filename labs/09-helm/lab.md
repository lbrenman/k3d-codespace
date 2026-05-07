# Lab 09: Helm Charts — Prometheus & Grafana
# ─────────────────────────────────────────────────────────────────────────────
# Helm is the package manager for Kubernetes. Instead of writing and managing
# individual YAML manifests, Helm bundles them into a "chart" — a versioned,
# configurable package you can install, upgrade, and rollback with a single
# command.
#
# HOW TO USE THIS LAB:
#   Copy and paste each command block into your terminal one step at a time.
#   Do not run this file as a script. Read the comments before each command
#   so you understand what it does before running it.
#
# What you will build:
#
#   ┌──────────────────────────────────────────────────────────────────┐
#   │  Namespace: monitoring                                           │
#   │                                                                  │
#   │  ┌─────────────────────────────────────────────────────────┐    │
#   │  │  Helm Release: kube-prometheus-stack                    │    │
#   │  │                                                         │    │
#   │  │  ┌──────────────┐  ┌────────────┐  ┌───────────────┐  │    │
#   │  │  │  Prometheus  │  │  Grafana   │  │ Alertmanager  │  │    │
#   │  │  │  metrics DB  │  │ dashboards │  │ alert routing │  │    │
#   │  │  │  port 9090   │  │ port 3000  │  │  port 9093    │  │    │
#   │  │  └──────┬───────┘  └─────┬──────┘  └───────────────┘  │    │
#   │  └─────────│────────────────│─────────────────────────────┘    │
#   └────────────│────────────────│──────────────────────────────────┘
#                │                │
#       port-forward           port-forward
#         9090                   3000
#                │                │
#           Prometheus         Grafana
#             UI               UI (admin / prom-operator)
#
# Key concepts: helm install, helm upgrade, helm rollback, helm uninstall,
#               values.yaml, --set, helm history, helm list

# ── Step 1: Navigate to the lab folder ───────────────────────────────────────
cd labs/09-helm

# ── Step 2: Verify helm is installed ─────────────────────────────────────────
helm version
# Should show v3.x

# ── Step 3: Create a namespace ───────────────────────────────────────────────
kubectl create namespace monitoring

# ── Step 4: Add the Prometheus community Helm repository ─────────────────────
# A Helm repo is like an app store — you add it once and can install any
# chart from it. This repo contains the kube-prometheus-stack chart.
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm repo list

# ── Step 5: Explore the chart before installing ───────────────────────────────
# See all available charts in the repo
helm search repo prometheus-community

# Show the default values — this tells you what you can customize
helm show values prometheus-community/kube-prometheus-stack | head -100

# ── Step 6: Create a custom values file ──────────────────────────────────────
# Paste this entire block into your terminal at once.
# It creates a values.yaml file in the current lab folder.
# Helm will merge these values on top of the chart defaults —
# you only need to specify the things you want to change.
cat > values.yaml << 'YAML'
# Custom values for kube-prometheus-stack
# Only values we want to override are listed here.
# Everything else uses chart defaults.

grafana:
  # Set a known admin password (default is randomly generated)
  adminPassword: "prom-operator"

  # Reduce resource requests to fit comfortably in a Codespace
  resources:
    requests:
      cpu: 100m
      memory: 128Mi

prometheus:
  prometheusSpec:
    # Reduce retention to save disk space in the lab
    retention: 6h

    resources:
      requests:
        cpu: 100m
        memory: 256Mi

alertmanager:
  alertmanagerSpec:
    resources:
      requests:
        cpu: 50m
        memory: 64Mi
YAML

# Confirm it was created
cat values.yaml

# ── Step 7: Install the chart ────────────────────────────────────────────────
# helm install <release-name> <chart> [flags]
# --wait means helm will not return until all pods are Running
# --timeout sets how long to wait before giving up
helm install monitoring \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values values.yaml \
  --wait \
  --timeout 5m

# ── Step 8: Inspect what Helm deployed ───────────────────────────────────────
# List all Helm releases across namespaces
helm list -n monitoring

# See the full revision history of this release
helm history monitoring -n monitoring

# List all Kubernetes resources Helm created
kubectl get all -n monitoring

# ── Step 9: Access Prometheus UI ─────────────────────────────────────────────
# Run this in a terminal, then open port 9090 in your browser
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090
# Try in the UI:
#   Status → Targets   — shows all scrape targets and their health (up/down)
#   Query → type "up" and click Execute — shows 1 for each healthy target
#            (Note: the old "Graph" tab was renamed to "Query" in Prometheus 3.0)
# Press Ctrl+C to stop port-forward when done

# ── Step 10: Access Grafana UI ────────────────────────────────────────────────
# Run this in a terminal, then open port 3000 in your browser
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
# Login: admin / prom-operator
# Explore: Dashboards → Browse → Kubernetes / Compute Resources
# Press Ctrl+C to stop port-forward when done

# ── Step 11: Upgrade the release with new values ──────────────────────────────
# helm upgrade applies a new configuration to an existing release.
# --set lets you override individual values inline without editing values.yaml.
# Both --values and --set can be combined — --set takes precedence.
helm upgrade monitoring \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values values.yaml \
  --set prometheus.prometheusSpec.retention=12h \
  --set grafana.replicas=2

# Watch the upgrade roll out
kubectl get pods -n monitoring -w
# Press Ctrl+C once pods are Running

# Revision 2 should now appear
helm history monitoring -n monitoring

# ── Step 12: Inspect the values currently in use ──────────────────────────────
# Show only the values you overrode
helm get values monitoring -n monitoring

# Show ALL values including chart defaults
helm get values monitoring -n monitoring --all

# ── Step 13: Roll back to revision 1 ─────────────────────────────────────────
# Rollback re-deploys the exact configuration from a previous revision
helm rollback monitoring 1 -n monitoring

# Revision 3 will appear with description "Rollback to 1"
helm history monitoring -n monitoring

kubectl get pods -n monitoring -w
# Press Ctrl+C once pods stabilize

# ── Step 14: Inspect the chart templates (optional) ───────────────────────────
# Pull the chart locally so you can see the raw YAML templates Helm uses
helm pull prometheus-community/kube-prometheus-stack --untar --untardir /tmp/charts
ls /tmp/charts/kube-prometheus-stack/templates/ | head -20

# See exactly what YAML Helm would generate with your values (dry run)
helm template monitoring \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values values.yaml | head -100

# ── Step 15: Clean up ────────────────────────────────────────────────────────
helm uninstall monitoring -n monitoring
kubectl delete namespace monitoring


# ── Further Reading ───────────────────────────────────────────────────────────
# Helm documentation:
#   https://helm.sh/docs/
# Helm chart repository (Artifact Hub):
#   https://artifacthub.io/
# kube-prometheus-stack chart:
#   https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack
# Prometheus documentation:
#   https://prometheus.io/docs/introduction/overview/
# Grafana documentation:
#   https://grafana.com/docs/grafana/latest/

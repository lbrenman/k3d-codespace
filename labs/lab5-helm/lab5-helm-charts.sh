# Lab 5: Helm Charts — Prometheus & Grafana
# ─────────────────────────────────────────────────────────────────────────────
# Helm is the package manager for Kubernetes. Instead of writing and managing
# individual YAML manifests, Helm bundles them into a "chart" — a versioned,
# configurable package you can install, upgrade, and rollback with a single
# command.
#
# In this lab you will:
#   - Add a Helm chart repository
#   - Install the kube-prometheus-stack chart (Prometheus + Grafana + Alertmanager)
#   - Customize the deployment using values.yaml and --set flags
#   - Upgrade a release with new values
#   - Roll back to a previous release version
#   - Uninstall the release
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
#             UI               UI (admin/prom-operator)
#
# Key concepts: helm install, helm upgrade, helm rollback, helm uninstall,
#               values.yaml, --set, helm history, helm list

# ── Step 1: Verify helm is installed ─────────────────────────────────────────
helm version
# Should show v3.x

# ── Step 2: Create a namespace ───────────────────────────────────────────────
kubectl create namespace monitoring

# ── Step 3: Add the Prometheus community Helm repository ─────────────────────
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
# helm repo list shows all your configured repos
helm repo list

# ── Step 4: Explore the chart before installing ───────────────────────────────
# See all available charts in the repo
helm search repo prometheus-community

# Show the default values for the chart — this is how you know what to customize
helm show values prometheus-community/kube-prometheus-stack | head -100

# ── Step 5: Create a custom values file ──────────────────────────────────────
# Rather than overriding everything, we only specify what we want to change.
# Helm merges our values on top of the chart defaults.

cat > labs/lab5-helm/values.yaml << 'YAML'
# Custom values for kube-prometheus-stack
# Only values we want to override are listed here.
# Everything else uses chart defaults.

grafana:
  # Set a known admin password (default is random)
  adminPassword: "prom-operator"

  # Reduce resource requests for Codespace environment
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

echo "✅ values.yaml created"

# ── Step 6: Install the chart ────────────────────────────────────────────────
# helm install <release-name> <chart> --namespace <ns> --values <file>
helm install monitoring \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values labs/lab5-helm/values.yaml \
  --wait \
  --timeout 5m

# ── Step 7: Inspect what Helm deployed ───────────────────────────────────────
# List all Helm releases
helm list -n monitoring

# See the full history of this release
helm history monitoring -n monitoring

# List everything Kubernetes created
kubectl get all -n monitoring

# ── Step 8: Access Prometheus UI ─────────────────────────────────────────────
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090
# Visit port 9090 in browser
# Try: Status → Targets (shows what Prometheus is scraping)
# Try: Graph → query "up" to see all healthy targets
# Press Ctrl+C to stop

# ── Step 9: Access Grafana UI ─────────────────────────────────────────────────
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
# Visit port 3000 in browser
# Login: admin / prom-operator
# Explore: Dashboards → Browse → Kubernetes / Compute Resources
# Press Ctrl+C to stop

# ── Step 10: Upgrade the release with new values ──────────────────────────────
# Simulate a config change — increase Prometheus retention and add a replica to Grafana
# You can override individual values with --set without editing values.yaml

helm upgrade monitoring \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values labs/lab5-helm/values.yaml \
  --set prometheus.prometheusSpec.retention=12h \
  --set grafana.replicas=2

# Watch the upgrade roll out
kubectl get pods -n monitoring -w
# Press Ctrl+C once pods are Running

# Check history — revision 2 should now appear
helm history monitoring -n monitoring

# ── Step 11: Inspect the current values in use ────────────────────────────────
# See the merged values for the current release (your overrides + chart defaults)
helm get values monitoring -n monitoring

# See ALL values including chart defaults
helm get values monitoring -n monitoring --all

# ── Step 12: Roll back to revision 1 ─────────────────────────────────────────
helm rollback monitoring 1 -n monitoring

# Confirm rollback
helm history monitoring -n monitoring
# Revision 3 will show DEPLOYED with description "Rollback to 1"

kubectl get pods -n monitoring -w
# Press Ctrl+C once pods stabilize

# ── Step 13: Explore what the chart actually contains ────────────────────────
# Pull the chart locally to inspect the templates
helm pull prometheus-community/kube-prometheus-stack --untar --untardir /tmp/charts
ls /tmp/charts/kube-prometheus-stack/templates/ | head -20
# These are the raw YAML templates that Helm renders with your values

# See exactly what YAML Helm would generate (without installing)
helm template monitoring \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values labs/lab5-helm/values.yaml | head -100

# ── Step 14: Clean up ────────────────────────────────────────────────────────
helm uninstall monitoring -n monitoring
kubectl delete namespace monitoring

#!/bin/bash
set -e

echo "================================================"
echo "  Installing K3d Kubernetes Learning Environment"
echo "================================================"

# ── k3d ──────────────────────────────────────────────────────────────────────
echo ""
echo "▶ Installing k3d..."
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
echo "  ✅ k3d $(k3d version | head -1 | awk '{print $3}') installed"

# ── kubectx + kubens ─────────────────────────────────────────────────────────
echo ""
echo "▶ Installing kubectx and kubens..."
sudo git clone https://github.com/ahmetb/kubectx /opt/kubectx --quiet
sudo ln -sf /opt/kubectx/kubectx /usr/local/bin/kubectx
sudo ln -sf /opt/kubectx/kubens /usr/local/bin/kubens
echo "  ✅ kubectx and kubens installed"

# ── k9s (terminal UI for Kubernetes) ─────────────────────────────────────────
echo ""
echo "▶ Installing k9s..."
K9S_VERSION=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | grep tag_name | cut -d'"' -f4)
curl -sL "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_amd64.tar.gz" | \
  sudo tar xz -C /usr/local/bin k9s
echo "  ✅ k9s ${K9S_VERSION} installed"

# ── Stern (multi-pod log tail) ────────────────────────────────────────────────
echo ""
echo "▶ Installing stern (log tailing)..."
STERN_VERSION=$(curl -s https://api.github.com/repos/stern/stern/releases/latest | grep tag_name | cut -d'"' -f4)
curl -sL "https://github.com/stern/stern/releases/download/${STERN_VERSION}/stern_linux_amd64.tar.gz" | \
  sudo tar xz -C /usr/local/bin stern
echo "  ✅ stern ${STERN_VERSION} installed"

# ── kubectl aliases ───────────────────────────────────────────────────────────
echo ""
echo "▶ Setting up kubectl aliases and shell completion..."

cat >> ~/.bashrc << 'EOF'

# ── Kubernetes shortcuts ──────────────────────────────────────────────────────
alias k="kubectl"
alias kgp="kubectl get pods"
alias kgs="kubectl get svc"
alias kgd="kubectl get deployments"
alias kgn="kubectl get nodes"
alias kga="kubectl get all"
alias kdp="kubectl describe pod"
alias kds="kubectl describe svc"
alias kl="kubectl logs"
alias kaf="kubectl apply -f"
alias kdf="kubectl delete -f"
alias kns="kubens"
alias kctx="kubectx"

# kubectl autocomplete
source <(kubectl completion bash)
complete -F __start_kubectl k
EOF

echo "  ✅ Aliases and completion configured"

# ── .kube dir ─────────────────────────────────────────────────────────────────
mkdir -p ~/.kube

echo ""
echo "================================================"
echo "  ✅ Installation complete!"
echo "     The cluster will start automatically."
echo "================================================"

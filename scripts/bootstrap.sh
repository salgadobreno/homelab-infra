#!/usr/bin/env bash
# Installs this repo's toolchain. Re-runnable; no root required.
#
# Everything lands in ~/.local/bin rather than /usr/local/bin: this host has no
# passwordless sudo, and neither tool is packaged for Debian anyway. Versions are
# pinned and checksums verified so a rebuild gets the same toolchain.
set -euo pipefail

TOFU_VERSION="${TOFU_VERSION:-1.12.6}"
KUBECTL_VERSION="${KUBECTL_VERSION:-v1.36.3}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"

mkdir -p "$BIN_DIR"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

have() { command -v "$1" >/dev/null 2>&1; }

install_tofu() {
  if have tofu && tofu version | head -1 | grep -q "v${TOFU_VERSION}$"; then
    echo "tofu ${TOFU_VERSION} already installed"
    return
  fi
  echo "installing tofu ${TOFU_VERSION}"
  local base="https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}"
  curl -fsSL -o "$tmp/tofu.zip" "${base}/tofu_${TOFU_VERSION}_linux_amd64.zip"
  curl -fsSL -o "$tmp/sums" "${base}/tofu_${TOFU_VERSION}_SHA256SUMS"
  ( cd "$tmp" \
    && grep "tofu_${TOFU_VERSION}_linux_amd64.zip" sums \
     | sed "s|tofu_${TOFU_VERSION}_linux_amd64.zip|tofu.zip|" \
     | sha256sum -c - )
  python3 -c "import zipfile,sys;zipfile.ZipFile(sys.argv[1]).extract('tofu',sys.argv[2])" \
    "$tmp/tofu.zip" "$BIN_DIR"
  chmod +x "$BIN_DIR/tofu"
}

install_kubectl() {
  if have kubectl && kubectl version --client 2>/dev/null | grep -q "$KUBECTL_VERSION"; then
    echo "kubectl ${KUBECTL_VERSION} already installed"
    return
  fi
  echo "installing kubectl ${KUBECTL_VERSION}"
  local base="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64"
  curl -fsSL -o "$tmp/kubectl" "${base}/kubectl"
  curl -fsSL -o "$tmp/kubectl.sha256" "${base}/kubectl.sha256"
  ( cd "$tmp" && echo "$(cat kubectl.sha256)  kubectl" | sha256sum -c - )
  install -m 0755 "$tmp/kubectl" "$BIN_DIR/kubectl"
}

install_tofu
install_kubectl

echo
echo "tofu:    $(tofu version | head -1)"
echo "kubectl: $(kubectl version --client 2>/dev/null | head -1)"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo; echo "warning: $BIN_DIR is not on PATH — add it to your shell profile" ;;
esac

#!/usr/bin/env bash
#
# Apply Debian security updates automatically, and nothing else.
# Operator-run: this installs a package and writes APT configuration.
#
#   sudo ./scripts/setup-unattended-upgrades.sh
#   sudo DRY_RUN=yes ./scripts/setup-unattended-upgrades.sh   # show, do not apply
#
# Why this exists. Cloudflare Access gates who may reach sshd, but it cannot help with a
# pre-authentication vulnerability in sshd itself — anyone who passes Access reaches that
# code. regreSSHion (CVE-2024-6387) was exactly this shape. Patching is the control;
# banning addresses is not. See SECURITY.md.
#
# WHAT IS DELIBERATELY EXCLUDED. This host is a hypervisor, and the enabled repositories
# are Debian, Proxmox, Docker and cloudflared. Only the Debian *security* origin is
# allowed to upgrade unattended:
#
#   Debian-Security   yes  — where openssh-server and the rest of the base system patch
#   Debian stable     no   — point releases; nothing urgent, and more churn
#   trixie-updates    no   — non-security fixes
#   Proxmox           no   — pve-manager, QEMU and the kernel ship in one suite with no
#                            security-only channel. Upgrading those unattended can want a
#                            reboot or restart running VMs. That is an operator decision.
#   Docker            no   — third party, no security-only channel
#   cloudflared       no   — same, and the tunnel is the path in; do not auto-change it
#
# AND NOTHING REBOOTS. Automatic-Reboot stays false: a reboot here takes down every VM,
# including the k3s node serving the public site. A kernel or libssl update therefore
# waits for the operator. `needrestart` reports what still runs old code.
#
# Re-runnable. Writes one file of its own and leaves the package defaults in place.

set -euo pipefail

CONF="/etc/apt/apt.conf.d/52homelab-unattended-upgrades"
PERIODIC="/etc/apt/apt.conf.d/20auto-upgrades"

if [ "$(id -u)" -ne 0 ]; then
  echo "error: run this as root — it installs a package and writes to /etc/apt" >&2
  exit 1
fi

if [ "${DRY_RUN:-}" = "yes" ]; then
  echo "DRY_RUN: would install unattended-upgrades and write:"
  echo "  $CONF"
  echo "  $PERIODIC"
  echo
  echo "Then report what it would upgrade with:"
  echo "  unattended-upgrade --dry-run --debug"
  exit 0
fi

if ! dpkg -s unattended-upgrades >/dev/null 2>&1; then
  echo "installing unattended-upgrades..."
  DEBIAN_FRONTEND=noninteractive apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq unattended-upgrades
else
  echo "unattended-upgrades is already installed"
fi

# Loaded after the package's own 50unattended-upgrades, so these win. Both list names are
# cleared first: assigning an APT list appends to it, so without the clears we would add
# our origin to the shipped defaults rather than replacing them, and inherit whatever
# else they allow.
cat > "$CONF" <<'CONF_EOF'
// Written by scripts/setup-unattended-upgrades.sh — see that script for the reasoning.
//
// Debian security only. Proxmox, Docker and cloudflared are deliberately excluded:
// they ship no security-only channel, and unattended upgrades of the virtualisation
// stack can want a reboot or disturb running VMs.

#clear Unattended-Upgrade::Allowed-Origins;
#clear Unattended-Upgrade::Origins-Pattern;

Unattended-Upgrade::Origins-Pattern {
    "origin=Debian,codename=${distro_codename}-security,label=Debian-Security";
};

// Belt and braces. The origin list above already excludes these, so this only matters
// if someone widens it later without thinking about the hypervisor.
#clear Unattended-Upgrade::Package-Blacklist;
Unattended-Upgrade::Package-Blacklist {
    "proxmox-ve";
    "pve-manager";
    "pve-kernel-.*";
    "proxmox-kernel-.*";
    "linux-image-.*";
};

// A reboot here stops every VM, including the node serving the public site.
Unattended-Upgrade::Automatic-Reboot "false";

// Remove kernels and dependencies that nothing needs any more, so /boot does not fill.
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";

// Redundant while Automatic-Reboot is false, and kept so widening that one key does
// not quietly start rebooting a host with logged-in operators.
Unattended-Upgrade::Automatic-Reboot-WithUsers "false";

// Upgrade in the smallest steps dpkg allows, so an interrupted run leaves a consistent
// system rather than a half-configured one.
Unattended-Upgrade::MinimalSteps "true";
CONF_EOF
echo "wrote $CONF"

# Enables the apt-daily and apt-daily-upgrade timers' actual work. Both timers already
# exist on this host; without these keys they update the lists and upgrade nothing.
cat > "$PERIODIC" <<'PERIODIC_EOF'
// Written by scripts/setup-unattended-upgrades.sh
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
PERIODIC_EOF
echo "wrote $PERIODIC"

systemctl enable --now apt-daily.timer apt-daily-upgrade.timer >/dev/null 2>&1 || true

echo
echo "--- effective configuration ---"
apt-config dump 2>/dev/null | grep -E 'Unattended-Upgrade::(Origins-Pattern|Automatic-Reboot|Package-Blacklist)|APT::Periodic::(Unattended-Upgrade|Update-Package-Lists)' | sed 's/^/  /'

echo
echo "--- what it would upgrade right now (dry run, changes nothing) ---"
unattended-upgrade --dry-run --debug 2>&1 | grep -iE 'allowed origins|packages that will be upgraded|^Checking|No packages found' | head -20 || true

echo
echo "verify:      make check-updates"
echo "run it now:  sudo unattended-upgrade --debug"
echo "revert with: sudo rm $CONF $PERIODIC && sudo apt-get remove --purge unattended-upgrades"

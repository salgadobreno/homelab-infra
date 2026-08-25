# Operator console for the homelab.
#
# Every routine command lives here rather than in shell history or a chat log, so
# both operator and agent reach for the same instrument and see the same output.
# `make` on its own lists what is available.
#
# Targets marked [root] need a real terminal: this host has no passwordless sudo
# and agent sessions have no TTY, so the operator runs those.

TOFU     := tofu
TF_DIR   := tofu
# The active change, discovered rather than hardcoded — a pinned name silently
# breaks the moment a change is archived.
CHANGE   ?= $(shell ls -1 openspec/changes 2>/dev/null | grep -v '^archive$$' | head -1)
KUBECONFIG_PATH := $(CURDIR)/kubeconfig

# Read the node address from Terraform, so the address plan has exactly one home.
# Falls back to the D7 value before the output exists.
# Filtered through a strict IP match, never used raw: `tofu output` prints its
# "no outputs found" warning to stdout, and that text contains backticks which
# the shell would happily execute.
NODE_IP  ?= $(shell $(TOFU) -chdir=$(TF_DIR) output -raw node_address 2>/dev/null | grep -Eox '[0-9]{1,3}(\.[0-9]{1,3}){3}')
ifeq ($(strip $(NODE_IP)),)
NODE_IP := 192.168.0.30
endif
NODE_USER ?= buzaga
PVE_IP   ?= 192.168.0.21
PVE_SSH_PORT ?= 4444
PVE_SSH_USER ?= buzaga
TUNNEL_USER  ?= cloudflared
# What the tunnel dials. It was the Compose stack on the hypervisor until M4 retired
# it; it is traefik on the node now. This is the tunnel's own origin, not the public
# URL — check-tunnel asserts the service still has something to forward to.
ORIGIN_URL   ?= http://192.168.0.30/
SITE_HOST    ?= k8s.buzaga.com.br
SITE_MARKER  ?= served-by: k3s
APEX_HOSTS   ?= buzaga.com.br www.buzaga.com.br
SNIPPET_USER ?= tofu-snippets
SNIPPET_DIR  ?= /var/lib/vz/snippets
SSH_OPTS := -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new

.DEFAULT_GOAL := help

# ---------------------------------------------------------------- help --------

.PHONY: help
help: ## List available targets
	@echo "homelab-infra — operator console"
	@echo
	@awk 'BEGIN {FS = ":.*?## "} \
		/^# ---.*-----$$/ { gsub(/[- ]/,"",$$0); sub(/^#/,"",$$0); \
			if ($$0 != "help") printf "\n\033[1m%s\033[0m\n", toupper($$0); next } \
		/^[a-zA-Z0-9_-]+:.*?## / { printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo
	@echo "  node=$(NODE_IP)  pve=$(PVE_IP)  kubeconfig=$(KUBECONFIG_PATH)"

# ---------------------------------------------------------------- status ------

.PHONY: status
status: ## One-screen overview: host, VMs, cluster, drift
	@printf '\033[1m== host ==\033[0m\n'
	@hostname; uptime -p; free -h | awk 'NR<=2'
	@printf '\n\033[1m== VMs ==\033[0m\n'
	@ls -1 /etc/pve/qemu-server/*.conf 2>/dev/null | xargs -rn1 basename | sed 's/.conf//' || echo "(none)"
	@printf '\n\033[1m== node %s ==\033[0m\n' "$(NODE_IP)"
	@ping -c1 -W2 $(NODE_IP) >/dev/null 2>&1 && echo "reachable" || echo "NO REPLY"
	@printf '\n\033[1m== tofu ==\033[0m\n'
	@$(MAKE) --no-print-directory tf-state
	@printf '\n\033[1m== progress ==\033[0m\n'
	@$(MAKE) --no-print-directory progress

.PHONY: pve
pve: ## Proxmox version, load, and memory
	@pveversion 2>/dev/null || cat /etc/pve/.version 2>/dev/null || echo "(pveversion needs root)"
	@uptime; free -h

.PHONY: storage
storage: ## Datastores and their content types (via API token, no root)
	@cd $(TF_DIR) && EP=$$(sed -n 's/^proxmox_endpoint *= *"\(.*\)"/\1/p' terraform.tfvars) && \
	 TOKEN=$$(sed -n 's/^proxmox_api_token *= *"\(.*\)"/\1/p' terraform.tfvars) && \
	 curl -sk -H "Authorization: PVEAPIToken=$$TOKEN" "$${EP}api2/json/storage" | \
	 python3 -c "import json,sys;[print(f\"{s['storage']:12} {s.get('type','?'):8} {s.get('content','')}\") for s in json.load(sys.stdin)['data']]"

.PHONY: vms
vms: ## VM configs known to Proxmox
	@for f in /etc/pve/qemu-server/*.conf; do \
	  [ -e "$$f" ] || { echo "(no VMs)"; break; }; \
	  echo "--- $$(basename $$f .conf) ---"; cat "$$f" 2>/dev/null || echo "  (needs root to read)"; \
	done

.PHONY: net
net: ## Address plan versus what actually answers on the wire
	@echo "  .1   gateway   $$(ping -c1 -W1 192.168.0.1  >/dev/null 2>&1 && echo up || echo '--')"
	@echo "  .21  proxmox   $$(ping -c1 -W1 $(PVE_IP)    >/dev/null 2>&1 && echo up || echo '--')"
	@echo "  .30  k3s node  $$(ping -c1 -W1 $(NODE_IP)   >/dev/null 2>&1 && echo up || echo '--')"
	@echo "  .40-.50        reserved for MetalLB (M6, unused)"
	@echo "  .100+          router DHCP pool — never allocated here"

# ---------------------------------------------------------------- cluster -----

.PHONY: nodes
nodes: ## kubectl get nodes (needs kubeconfig; task 7.4)
	@KUBECONFIG=$(KUBECONFIG_PATH) kubectl get nodes -o wide 2>/dev/null \
	  || $(MAKE) --no-print-directory node-exec CMD='sudo k3s kubectl get nodes -o wide'

.PHONY: pods
pods: ## All pods in all namespaces
	@KUBECONFIG=$(KUBECONFIG_PATH) kubectl get pods -A 2>/dev/null \
	  || $(MAKE) --no-print-directory node-exec CMD='sudo k3s kubectl get pods -A'

.PHONY: cluster
cluster: ## k3s service state and node readiness, straight from the node
	@$(MAKE) --no-print-directory node-exec \
	  CMD='echo -n "k3s: "; systemctl is-active k3s; cloud-init status; sudo k3s kubectl get nodes'

.PHONY: ssh
ssh: ## Interactive shell on the k3s node
	@ssh $(SSH_OPTS) $(NODE_USER)@$(NODE_IP)

.PHONY: node-exec
node-exec: ## Run CMD='...' on the node
	@ssh $(SSH_OPTS) -o BatchMode=yes $(NODE_USER)@$(NODE_IP) "$(CMD)"


.PHONY: kubeconfig
kubeconfig: ## Fetch the node's kubeconfig, rewritten to reach it off-node (task 7.4)
	@umask 077; ssh $(SSH_OPTS) -o BatchMode=yes $(NODE_USER)@$(NODE_IP) \
	  'sudo cat /etc/rancher/k3s/k3s.yaml' \
	  | sed 's|https://127\.0\.0\.1:6443|https://$(NODE_IP):6443|' > $(KUBECONFIG_PATH).tmp
	@grep -q 'server: https://$(NODE_IP):6443' $(KUBECONFIG_PATH).tmp \
	  || { rm -f $(KUBECONFIG_PATH).tmp; echo "FAIL: server address not rewritten"; exit 1; }
	@mv $(KUBECONFIG_PATH).tmp $(KUBECONFIG_PATH) && chmod 600 $(KUBECONFIG_PATH)
	@echo "wrote $(KUBECONFIG_PATH) -> https://$(NODE_IP):6443"
	@echo "use with:  export KUBECONFIG=$(KUBECONFIG_PATH)"

.PHONY: argocd
argocd: ## Port-forward the ArgoCD UI to localhost:8080 (task 2.5)
	@echo "ArgoCD UI:  http://localhost:8080     user: admin"
	@echo "password:   make argocd-password"
	@echo "ctrl-c to stop."
	@KUBECONFIG=$(KUBECONFIG_PATH) kubectl port-forward -n argocd svc/argocd-server 8080:80

.PHONY: argocd-password
argocd-password: ## Print the ArgoCD admin password (prints a secret — your terminal only)
	@KUBECONFIG=$(KUBECONFIG_PATH) kubectl get secret -n argocd argocd-initial-admin-secret \
	  -o jsonpath='{.data.password}' 2>/dev/null | base64 -d && echo \
	  || { echo "no initial admin secret — it is deleted after the first password change"; exit 1; }

.PHONY: argocd-status
argocd-status: ## What ArgoCD is running and what it has been asked to reconcile
	@KUBECONFIG=$(KUBECONFIG_PATH) kubectl get pods -n argocd \
	  -o custom-columns='POD:.metadata.name,READY:.status.containerStatuses[*].ready,STATUS:.status.phase' --no-headers
	@echo
	@# kubectl exits 0 with empty output when nothing matches, so an empty result has
	@# to be handled rather than relying on the exit code.
	@apps=$$(KUBECONFIG=$(KUBECONFIG_PATH) kubectl get applications.argoproj.io -n argocd \
	  -o custom-columns='APP:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REVISION:.status.sync.revision' \
	  --no-headers 2>/dev/null); \
	 if [ -n "$$apps" ]; then echo "$$apps"; else echo "(no Applications declared yet — group 4)"; fi

.PHONY: cloud-init-log
cloud-init-log: ## Read cloud-init output from the node (task 7.1)
	@$(MAKE) --no-print-directory node-exec CMD='sudo cat /var/log/cloud-init-output.log'

.PHONY: forget-node-key
forget-node-key: ## Drop the node's old SSH host key — a rebuilt node has a new identity
	@# Deliberately NOT called from `rebuild`: a recipe line containing $$(MAKE) is run
	@# even under `make -n`, which turned a dry run of the destroy+apply chain into a
	@# real one. `rebuild` inlines the same ssh-keygen instead.
	@ssh-keygen -f "$$HOME/.ssh/known_hosts" -R $(NODE_IP) >/dev/null 2>&1 || true
	@echo "forgot the host key for $(NODE_IP)"

.PHONY: pve-ssh
pve-ssh: ## SSH to the Proxmox host on the hardened port (not as root — group 5)
	@ssh $(SSH_OPTS) -p $(PVE_SSH_PORT) $(PVE_SSH_USER)@$(PVE_IP)

.PHONY: harden-sshd
harden-sshd: ## NEEDS ROOT, run in a real terminal: withdraw root and password SSH (5.1, 5.1a)
	@echo "This edits /etc/ssh/sshd_config and reloads sshd, so it needs root."
	@echo "It backs the file up, validates with 'sshd -t', and reloads rather than"
	@echo "restarts, so your current session survives a mistake."
	@echo
	@echo "    sudo ./scripts/harden-sshd.sh"

.PHONY: withdraw-root-key
withdraw-root-key: ## NEEDS ROOT, run in a real terminal: remove root's authorised keys (5.4)
	@echo "Only root can read /root/.ssh/authorized_keys, so run this yourself:"
	@echo
	@echo "    sudo ./scripts/withdraw-root-key.sh              # the provisioning key"
	@echo "    sudo PURGE=all ./scripts/withdraw-root-key.sh    # every key root holds"
	@echo
	@echo "PermitRootLogin no already refuses them. This makes the withdrawal a removed"
	@echo "credential rather than one edit away from working again."

.PHONY: check-privileges
check-privileges: ## Assert every property narrow-privileges established (task 7.1)
	@echo "=== the provisioning credential ==="
	@./scripts/check-privileges.sh
	@echo
	@echo "=== what it is refused ==="
	@./scripts/check-token-scope.sh
	@echo
	@echo "=== the snippet account ==="
	@$(MAKE) --no-print-directory check-snippet-user
	@echo
	@echo "=== administrative SSH ==="
	@$(MAKE) --no-print-directory check-root-ssh
	@echo
	@echo "=== the tunnel ==="
	@$(MAKE) --no-print-directory check-tunnel

.PHONY: check-privileges-regression
check-privileges-regression: ## Show the privilege check failing on a widened role (task 7.2)
	@echo "A check never seen to fail is not a check. Two fixtures stand in for a role"
	@echo "change, so proving the check works does not mean granting the credential the"
	@echo "privileges it exists to forbid."
	@echo
	@echo "--- a role that gained Permissions.Modify and VM.Console ---"
	@! PERMISSIONS_FIXTURE=tests/permissions-regressed.json ./scripts/check-privileges.sh \
	  || { echo "FAIL: the check passed a widened role"; exit 1; }
	@echo
	@echo "--- a role that quietly lost Sys.AccessNetwork ---"
	@! PERMISSIONS_FIXTURE=tests/permissions-narrowed.json ./scripts/check-privileges.sh \
	  || { echo "FAIL: the check passed a role missing a privilege provisioning needs"; exit 1; }
	@echo
	@echo "OK: the check fails in both directions"

.PHONY: harden-tunnel
harden-tunnel: ## NEEDS ROOT, run in a real terminal: run the tunnel unprivileged, token off argv (6.1-6.3)
	@echo "Rotate the tunnel token first — the current one is readable by every local"
	@echo "user and has been printed into a transcript."
	@echo "  Zero Trust -> Networks -> Tunnels -> your tunnel -> Configure -> refresh token"
	@echo
	@echo "    sudo TUNNEL_TOKEN='<new token>' ./scripts/harden-cloudflared.sh"
	@echo
	@echo "Or, keeping the current token (it stays readable by anyone who has seen it):"
	@echo
	@echo "    sudo ./scripts/harden-cloudflared.sh --reuse-existing-token"

.PHONY: check-tunnel
check-tunnel: ## Confirm the tunnel holds no readable credential and is not root (6.4, 6.5)
	@systemctl is-active --quiet cloudflared \
	  || { echo "FAIL: cloudflared is not running"; exit 1; }
	@echo "OK: the tunnel is running"
	@owner=$$(ps -o user= -p $$(systemctl show cloudflared -p MainPID --value) | tr -d ' '); \
	 test "$$owner" != "root" \
	  && echo "OK: it runs as $$owner, not root" \
	  || { echo "FAIL: it still runs as root"; exit 1; }
	@# argv is world-readable, so a token passed as --token is readable by anyone.
	@# Assert the token-file form and the absence of an inline one, without printing
	@# argv itself.
	@pid=$$(systemctl show cloudflared -p MainPID --value); \
	 tr '\0' '\n' < /proc/$$pid/cmdline | grep -q -- '--token-file' \
	  || { echo "FAIL: not using --token-file"; exit 1; }; \
	 tr '\0' '\n' < /proc/$$pid/cmdline | grep -qx -- '--token' \
	  && { echo "FAIL: a token is on the command line"; exit 1; } \
	  || echo "OK: no credential in /proc/$$pid/cmdline"
	@pid=$$(systemctl show cloudflared -p MainPID --value); \
	 cat /proc/$$pid/environ >/dev/null 2>&1 \
	  && { echo "FAIL: this account can read the tunnel's environment"; exit 1; } \
	  || echo "OK: /proc/$$pid/environ is not readable by this account"
	@# The unit file is world-readable by design; it must therefore hold no secret.
	@grep -qE -- '--token[[:space:]]' /etc/systemd/system/cloudflared.service \
	  && { echo "FAIL: the unit file still carries an inline token"; exit 1; } \
	  || echo "OK: no credential in the unit file"
	@# Take the path from argv rather than hardcoding it, and rely on the service
	@# being active for its existence: cloudflared would not have started if the file
	@# were missing. `test ! -r` on a hardcoded path passes when the file is simply
	@# absent, which would read as a pass for the wrong reason.
	@pid=$$(systemctl show cloudflared -p MainPID --value); \
	 f=$$(tr '\0' '\n' < /proc/$$pid/cmdline | grep -A1 -x -- '--token-file' | tail -1); \
	 test -n "$$f" || { echo "FAIL: could not read the token path from argv"; exit 1; }; \
	 test ! -r "$$f" \
	  && echo "OK: $$f is unreadable by $$(id -un)" \
	  || { echo "FAIL: $$f is readable by $$(id -un)"; exit 1; }
	@shell=$$(getent passwd $(TUNNEL_USER) | cut -d: -f7); \
	 case "$$shell" in \
	   */nologin|*/false) echo "OK: $(TUNNEL_USER) has no login shell ($$shell)";; \
	   *) echo "FAIL: $(TUNNEL_USER) has a login shell ($$shell)"; exit 1;; \
	 esac
	@groups=$$(id -nG $(TUNNEL_USER) 2>/dev/null); \
	 echo "$$groups" | grep -qwE 'root|sudo|adm' \
	  && { echo "FAIL: $(TUNNEL_USER) is in a privileged group ($$groups)"; exit 1; } \
	  || echo "OK: $(TUNNEL_USER) holds no privileged group ($$groups)"
	@code=$$(curl -s -o /dev/null -m 5 -H 'Host: $(SITE_HOST)' -w '%{http_code}' $(ORIGIN_URL)); \
	 test "$$code" = "200" \
	  && echo "OK: the origin still answers ($(ORIGIN_URL) -> $$code)" \
	  || { echo "FAIL: origin returned $$code"; exit 1; }

.PHONY: check-public
check-public: ## Confirm every public hostname is served by the cluster
	@# Deliberately NOT part of `make check`: it depends on DNS, Cloudflare and the
	@# internet, so it can fail for reasons that say nothing about this system.
	@# Both return 200, so a status code cannot tell them apart. The marker can.
	@curl -s -m 15 https://$(SITE_HOST)/ | grep -q '$(SITE_MARKER)' \
	  && echo "OK: https://$(SITE_HOST)/ serves the cluster's copy" \
	  || { echo "FAIL: https://$(SITE_HOST)/ is not serving the cluster's copy"; exit 1; }
	@# Inverted at the M4 cutover. This previously asserted the apex had NOT moved to the
	@# cluster, which was correct while both copies ran and became wrong the moment the
	@# hostname was repointed.
	@for h in $(APEX_HOSTS); do \
	   curl -s -m 15 "https://$$h/" | grep -q '$(SITE_MARKER)' \
	     && echo "OK: https://$$h/ serves the cluster's copy" \
	     || { echo "FAIL: https://$$h/ is not being served by the cluster"; exit 1; }; \
	 done

.PHONY: check-site
check-site: ## Confirm the cluster is serving the site (task 6.1)
	@# Reachability first, so "the site is down" and "the cluster is not there" are
	@# different answers. A rebuilt cluster also has a new CA, which makes a saved
	@# kubeconfig fail in a way that looks like an outage if it is not named.
	@ping -c1 -W2 $(NODE_IP) >/dev/null 2>&1 \
	  || { echo "UNREACHABLE: $(NODE_IP) does not answer — the node is down, not the site"; exit 1; }
	@KUBECONFIG=$(KUBECONFIG_PATH) kubectl get --raw /readyz >/dev/null 2>&1 \
	  || { echo "UNREACHABLE: the Kubernetes API rejected us. If the cluster was rebuilt,"; \
	       echo "             its CA changed — run 'make kubeconfig'."; exit 1; }
	@echo "OK: the node answers and the API accepts this kubeconfig"
	@# The host header is what the tunnel sends. Asking without it is a different
	@# question, and a catch-all Ingress would answer both.
	@code=$$(curl -s -o /dev/null -m 10 -w '%{http_code}' -H 'Host: $(SITE_HOST)' http://$(NODE_IP)/); \
	 test "$$code" = "200" \
	  && echo "OK: traefik serves $(SITE_HOST) (HTTP $$code)" \
	  || { echo "FAIL: $(SITE_HOST) returned $$code — the cluster is up and the site is not"; exit 1; }
	@# Identity, not equality. Cloudflare rewrites the page at its edge, so a hash
	@# comparison against the origin can never pass, and hashing the public response
	@# breaks whenever that rewriting changes. A marker survives both.
	@curl -s -m 10 -H 'Host: $(SITE_HOST)' http://$(NODE_IP)/ | grep -q '$(SITE_MARKER)' \
	  && echo "OK: it is the cluster's copy (marker present)" \
	  || { echo "FAIL: served a page without the '$(SITE_MARKER)' marker — something else answered"; exit 1; }
	@# The hypervisor must not be serving the site any more. A listener here means the
	@# retired Compose stack came back, and two origins for one site is the state M4
	@# exists to end. Local, so it belongs in the routine suite.
	@curl -s -o /dev/null -m 3 http://127.0.0.1:30000/ 2>/dev/null \
	  && { echo "FAIL: something serves on the hypervisor's :30000 — the retired stack is back"; exit 1; } \
	  || echo "OK: the hypervisor serves nothing"
	@KUBECONFIG=$(KUBECONFIG_PATH) kubectl get application -n argocd site \
	  -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null \
	  | grep -qx 'Synced/Healthy' \
	  && echo "OK: ArgoCD reports the app Synced and Healthy" \
	  || { echo "FAIL: ArgoCD does not report Synced/Healthy — the page may be stale"; exit 1; }

.PHONY: check-root-ssh
check-root-ssh: ## Confirm root SSH is refused and key auth still works (5.1b, 5.2)
	@! ssh $(SSH_OPTS) -o BatchMode=yes -o ConnectTimeout=5 -p $(PVE_SSH_PORT) \
	     root@$(PVE_IP) 'id -un' >/dev/null 2>&1 \
	  || { echo "FAIL: root SSH still succeeds"; exit 1; }
	@echo "OK: root SSH is refused"
	@# What the server *offers* matters as much as what succeeds: an advertised
	@# 'password' method means a LAN client may still be prompted. Asking as a user
	@# that cannot exist gets the method list without authenticating as anyone.
	@methods=$$(ssh $(SSH_OPTS) -o PreferredAuthentications=password \
	     -o PubkeyAuthentication=no -o NumberOfPasswordPrompts=0 -o ConnectTimeout=5 \
	     -p $(PVE_SSH_PORT) nosuchuser@$(PVE_IP) true 2>&1 \
	     | sed -n 's/.*(\(.*\)).*/\1/p'); \
	 case "$$methods" in \
	   *password*) echo "FAIL: the server still offers password auth ($$methods)"; exit 1;; \
	   *publickey*) echo "OK: publickey only ($$methods)";; \
	   *) echo "FAIL: publickey is not offered ($$methods) — nobody can get in"; exit 1;; \
	 esac
	@# A positive control: an account whose key lives on this host proves key auth
	@# still works end to end. The operator's own login comes from another machine
	@# and cannot be tested from here — see the note below.
	@ssh $(SSH_OPTS) -o BatchMode=yes -o ConnectTimeout=5 -p $(PVE_SSH_PORT) \
	     $(SNIPPET_USER)@$(PVE_IP) 'id -un' >/dev/null 2>&1 \
	  && echo "OK: key authentication still works ($(SNIPPET_USER) logged in)" \
	  || { echo "FAIL: key authentication is broken — revert before continuing"; exit 1; }
	@printf 'NOTE: %s account(s) hold authorised keys. Whether YOUR client machine is\n' \
	  "$$(ls -1 /home/*/.ssh/authorized_keys 2>/dev/null | wc -l)"
	@echo "      among them can only be checked from that machine, not from here."

.PHONY: snippet-user
snippet-user: ## NEEDS ROOT, run in a real terminal: create the unprivileged snippet-upload account (task 4.2)
	@echo "This creates a host account and changes directory ownership, so it needs root."
	@echo "Run it yourself:"
	@echo
	@echo "    sudo ./scripts/create-snippet-user.sh"

.PHONY: check-snippet-user
check-snippet-user: ## Confirm the snippet account is unprivileged and its directory survives a destroy (4.2)
	@ssh $(SSH_OPTS) -p $(PVE_SSH_PORT) -o BatchMode=yes $(SNIPPET_USER)@$(PVE_IP) \
	  'test "$$(id -un)" = "$(SNIPPET_USER)" && test "$$(id -u)" -ne 0' \
	  || { echo "FAIL: $(SNIPPET_USER) is unreachable or is root — run 'make snippet-user'"; exit 1; }
	@echo "OK: $(SNIPPET_USER) is not root"
	@# `tee` over an ssh exec: the channel a source_raw snippet upload actually uses.
	@# An SFTP probe passes on a path this write fails on, which is how 4.4 got through
	@# a green check into a broken rebuild.
	@echo probe | ssh $(SSH_OPTS) -p $(PVE_SSH_PORT) -o BatchMode=yes $(SNIPPET_USER)@$(PVE_IP) \
	  'tee $(SNIPPET_DIR)/.probe >/dev/null && rm -f $(SNIPPET_DIR)/.probe' \
	  || { echo "FAIL: cannot write $(SNIPPET_DIR) as $(SNIPPET_USER)"; exit 1; }
	@echo "OK: $(SNIPPET_USER) can write $(SNIPPET_DIR) the way the provider does"
	@# Without the sentinel, PVE rmdir's this directory when destroy removes the last
	@# snippet, and recreates it root-owned — so the ownership above is true now and
	@# false after the next destroy. Design D6.
	@ssh $(SSH_OPTS) -p $(PVE_SSH_PORT) -o BatchMode=yes $(SNIPPET_USER)@$(PVE_IP) \
	  'test -e $(SNIPPET_DIR)/.keep' \
	  || { echo "FAIL: $(SNIPPET_DIR)/.keep is missing — the directory will not survive a destroy"; exit 1; }
	@echo "OK: the directory survives a destroy"

# ---------------------------------------------------------------- tofu --------

.PHONY: init validate fmt plan apply destroy output refresh
init: ## tofu init
	@$(TOFU) -chdir=$(TF_DIR) init

validate: ## tofu validate
	@$(TOFU) -chdir=$(TF_DIR) validate

fmt: ## tofu fmt
	@$(TOFU) -chdir=$(TF_DIR) fmt -diff

plan: ## tofu plan, saved to tofu/tfplan
	@$(TOFU) -chdir=$(TF_DIR) plan -input=false -out=tfplan

apply: ## [root-ish] Apply the saved plan — needs ssh-agent loaded
	@test -n "$$SSH_AUTH_SOCK" || { echo "no ssh-agent: run  eval \$$(ssh-agent) && ssh-add ~/.ssh/id_ed25519"; exit 1; }
	@$(TOFU) -chdir=$(TF_DIR) apply tfplan

destroy: ## Destroy everything this repo manages (asks first)
	@$(TOFU) -chdir=$(TF_DIR) destroy

refresh: ## Persist outputs to state; touches no infrastructure
	@$(TOFU) -chdir=$(TF_DIR) apply -refresh-only

output: ## Show tofu outputs
	@$(TOFU) -chdir=$(TF_DIR) output

.PHONY: rebuild
rebuild: ## [destructive] Timed destroy + apply + readiness (tasks 9.1-9.3)
	@test "$(CONFIRM)" = "yes" || { echo "refusing: this destroys the cluster."; \
	  echo "run:  make rebuild CONFIRM=yes"; exit 1; }
	@test -n "$$SSH_AUTH_SOCK" || { echo "no ssh-agent: snippet upload will fail."; \
	  echo "run:  eval \$$(ssh-agent) && ssh-add ~/.ssh/id_ed25519"; exit 1; }
	@start=$$(date +%s); \
	 $(TOFU) -chdir=$(TF_DIR) destroy -auto-approve -input=false && \
	 $(TOFU) -chdir=$(TF_DIR) apply   -auto-approve -input=false && \
	 echo "--- clearing the old host key ---" && \
	 { ssh-keygen -f "$$HOME/.ssh/known_hosts" -R $(NODE_IP) >/dev/null 2>&1 || true; } && \
	 echo "--- waiting for the node to report Ready ---" && \
	 until ssh $(SSH_OPTS) -o BatchMode=yes $(NODE_USER)@$(NODE_IP) \
	   'test -f /run/cloud-init-k3s-complete' 2>/dev/null; do sleep 5; done && \
	 echo && echo "REBUILD COMPLETE in $$(( $$(date +%s) - start ))s" && \
	 echo "(record this number in the README — task 9.3)"

.PHONY: verify-rebuild
# kubeconfig is a prerequisite rather than a $(MAKE) line in the recipe: make
# executes recipe lines containing $(MAKE) even under -n, which is how a dry run
# once destroyed this cluster. Prerequisites are not executed under -n.
verify-rebuild: kubeconfig ## After a rebuild: prove the page still matches without regenerating (task 6.2)
	@echo
	@echo "=== waiting for ArgoCD to finish reconciling ==="
	@# check-diagram compares against the app's sync and health, so running it
	@# while the app is still Progressing fails for a reason that has nothing to
	@# do with the property being tested.
	@until [ "$$(KUBECONFIG=$(KUBECONFIG_PATH) kubectl get application site -n argocd \
	    -o jsonpath='{.status.sync.status}{.status.health.status}' 2>/dev/null)" = "SyncedHealthy" ]; do \
	  printf '.'; sleep 5; done; echo " Synced/Healthy"
	@echo
	@echo "=== the page must already agree — do NOT run 'make diagram' first ==="
	@./scripts/check-diagram.sh && \
	  echo && echo "PASS: a rebuilt cluster reports the same shapes; the committed page needed no regeneration."

.PHONY: tf-state
tf-state: ## What Terraform currently believes exists
	@python3 -c "import json;d=json.load(open('$(TF_DIR)/terraform.tfstate'));\
	print('serial',d['serial'],'-',len([r for r in d['resources'] if r['mode']=='managed']),'managed');\
	[print('  ',r['type']+'.'+r['name']) for r in d['resources'] if r['mode']=='managed']" 2>/dev/null || echo "(no state yet)"

# ---------------------------------------------------------------- checks ------

.PHONY: check
check: check-secrets check-disclosure check-privileges check-site check-diagram check-drift ## Run all safety checks
# The two added at M5 sit where their cost is. check-disclosure is a local grep and
# runs early, so a boundary violation fails before anything talks to the cluster.
# check-diagram needs the cluster and runs after check-site, which distinguishes an
# unreachable node from a broken one.

.PHONY: diagram
diagram: ## Regenerate the page from parts/ and the cluster (task 3.3)
	@./scripts/generate-diagram.sh

.PHONY: check-diagram
check-diagram: ## Fail if the page and the cluster disagree (task 4.1)
	@./scripts/check-diagram.sh

.PHONY: check-disclosure
check-disclosure: ## Assert nothing served crosses the disclosure boundary (task 2.2)
	@./scripts/check-disclosure.sh

.PHONY: check-disclosure-selftest
check-disclosure-selftest: ## Prove each disclosure rule fires on a fixture (task 2.3)
	@./scripts/check-disclosure.sh --selftest

.PHONY: check-secrets
check-secrets: ## Confirm no API token or key material is tracked by git (task 8.5)
	@TOKEN=$$(sed -n 's/.*!\([^=]*\)=\(.*\)"/\2/p' $(TF_DIR)/terraform.tfvars 2>/dev/null); \
	if [ -n "$$TOKEN" ] && git grep -qI --cached "$$TOKEN" 2>/dev/null; then \
	  echo "FAIL: token value found in tracked files"; exit 1; fi
	@git ls-files | grep -E '(\.tfstate|\.tfvars$$|kubeconfig|id_[re]d?sa$$)' && \
	  { echo "FAIL: sensitive file is tracked"; exit 1; } || echo "OK: no secrets tracked"

.PHONY: check-scope
check-scope: ## Prove the provisioning token is refused everything outside its job (task 3.2)
	@./scripts/check-token-scope.sh

.PHONY: check-drift
check-drift: ## Confirm reality still matches configuration (task 8.1)
	@$(TOFU) -chdir=$(TF_DIR) plan -input=false -detailed-exitcode >/dev/null 2>&1; \
	case $$? in \
	  0) echo "OK: no drift" ;; \
	  2) echo "DRIFT: plan wants changes — run 'make plan' to see them"; exit 1 ;; \
	  *) echo "ERROR: plan failed — run 'make plan'"; exit 1 ;; \
	esac

.PHONY: check-ip
check-ip: ## Confirm the node address is free before claiming it (task 6.1a)
	@ping -c2 -W1 $(NODE_IP) >/dev/null 2>&1 \
	  && echo "IN USE: $(NODE_IP) answered" \
	  || echo "FREE: $(NODE_IP) did not answer"

# ---------------------------------------------------------------- project -----

.PHONY: progress
progress: ## Task completion for the active OpenSpec change
	@f=openspec/changes/$(CHANGE)/tasks.md; \
	if [ -z "$(CHANGE)" ]; then \
	  echo "no active change — last archived: $$(ls -1t openspec/changes/archive 2>/dev/null | head -1)"; \
	elif [ ! -f "$$f" ]; then \
	  echo "$(CHANGE): no tasks.md at $$f"; exit 1; \
	else \
	  echo "$(CHANGE): $$(grep -c '^- \[x\]' $$f)/$$(grep -c '^- \[' $$f) tasks"; \
	fi

.PHONY: todo
todo: ## Next few unfinished tasks
	@grep -m5 '^- \[ \]' openspec/changes/$(CHANGE)/tasks.md

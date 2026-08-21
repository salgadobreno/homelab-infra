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
	@echo "  .40-.50        reserved for MetalLB (M7, unused)"
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

.PHONY: cloud-init-log
cloud-init-log: ## Read cloud-init output from the node (task 7.1)
	@$(MAKE) --no-print-directory node-exec CMD='sudo cat /var/log/cloud-init-output.log'

.PHONY: pve-ssh
pve-ssh: ## SSH to the Proxmox host as root on the hardened port
	@ssh $(SSH_OPTS) -p $(PVE_SSH_PORT) root@$(PVE_IP)

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
	 echo "--- waiting for the node to report Ready ---" && \
	 until ssh $(SSH_OPTS) -o BatchMode=yes $(NODE_USER)@$(NODE_IP) \
	   'test -f /run/cloud-init-k3s-complete' 2>/dev/null; do sleep 5; done && \
	 echo && echo "REBUILD COMPLETE in $$(( $$(date +%s) - start ))s" && \
	 echo "(record this number in the README — task 9.3)"

.PHONY: tf-state
tf-state: ## What Terraform currently believes exists
	@python3 -c "import json;d=json.load(open('$(TF_DIR)/terraform.tfstate'));\
	print('serial',d['serial'],'-',len([r for r in d['resources'] if r['mode']=='managed']),'managed');\
	[print('  ',r['type']+'.'+r['name']) for r in d['resources'] if r['mode']=='managed']" 2>/dev/null || echo "(no state yet)"

# ---------------------------------------------------------------- checks ------

.PHONY: check
check: check-secrets check-drift ## Run all safety checks

.PHONY: check-secrets
check-secrets: ## Confirm no API token or key material is tracked by git (task 8.5)
	@TOKEN=$$(sed -n 's/.*!\([^=]*\)=\(.*\)"/\2/p' $(TF_DIR)/terraform.tfvars 2>/dev/null); \
	if [ -n "$$TOKEN" ] && git grep -qI --cached "$$TOKEN" 2>/dev/null; then \
	  echo "FAIL: token value found in tracked files"; exit 1; fi
	@git ls-files | grep -E '(\.tfstate|\.tfvars$$|kubeconfig|id_[re]d?sa$$)' && \
	  { echo "FAIL: sensitive file is tracked"; exit 1; } || echo "OK: no secrets tracked"

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
	echo "$(CHANGE): $$(grep -c '^- \[x\]' $$f)/$$(grep -c '^- \[' $$f) tasks"

.PHONY: todo
todo: ## Next few unfinished tasks
	@grep -m5 '^- \[ \]' openspec/changes/$(CHANGE)/tasks.md

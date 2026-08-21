# Tasks

Ordered so each group ends in something observable, and so the expensive-to-undo steps
come after the cheap ones have proved the mechanism. The tunnel hostname is last of the
plumbing because it is the only step that touches the internet.

## 1. Establish the baseline

- [x] 1.1 Record what serves today: the Compose stack's containers, the public hostname, and the response from the existing site — the "unaffected" half of `site-delivery` needs a before to compare against
- [x] 1.2 Record the node's memory headroom with nothing deployed, so D2's budget is measured rather than asserted
- [x] 1.3 Confirm `make rebuild CONFIRM=yes` still passes before anything is added to the node's bootstrap

## 2. The reconciler

- [ ] 2.1 Add the ArgoCD `HelmChart` manifest to cloud-init, written into `/var/lib/rancher/k3s/server/manifests/` (design D1), with the component trim from D2
- [ ] 2.2 Rebuild, and confirm ArgoCD comes up unattended — `gitops` "A rebuilt cluster reconciles without operator steps"
- [ ] 2.3 Answer Open Question 2: whether helm-controller installs the chart cleanly, or needs a pinned version and a raised timeout. Record what it did
- [ ] 2.4 Answer Open Question 1: measure what ArgoCD consumes once settled, against the 1.2 baseline. Trim further if the headroom is gone
- [ ] 2.5 Add `make argocd` for access — port-forward and the admin credential — so reaching the UI is a command rather than a recalled incantation

## 3. The site, declared

- [ ] 3.1 Create `k8s/site/` with Deployment, Service, and a kustomize `configMapGenerator` over the HTML content (design D3)
- [ ] 3.2 Copy the site content into the repository, and confirm it is what is served rather than the hypervisor path — `site-delivery` "no content copied from the hypervisor by hand"
- [ ] 3.3 Decide the `Ingress` shape (Open Question 3) and write it
- [ ] 3.4 Confirm the site answers from inside the cluster — `site-delivery` "The site answers from inside the cluster"

## 4. Reconciliation, proved

- [ ] 4.1 Add the ArgoCD `Application` pointing at `k8s/site/`, with `selfHeal` and `prune` on (design D7)
- [ ] 4.2 Commit and push a visible change to the site, and confirm it reaches the cluster with no command run against it — `gitops` "A change to the site reaches the running cluster"
- [ ] 4.3 Edit a reconciled resource with `kubectl` and confirm it is reverted — `gitops` "An out-of-band edit does not survive"
- [ ] 4.4 Confirm the ConfigMap name changes with the content, so a push actually rolls the pods rather than leaving stale content served (design D3)

## 5. The internet

- [ ] 5.1 Add the second public hostname in the Cloudflare dashboard, pointing at traefik on 192.168.0.30 (design D5) — operator action
- [ ] 5.2 Confirm the new hostname serves the cluster's copy — `site-delivery` "The public hostname serves the cluster copy"
- [ ] 5.3 Confirm the existing hostname still serves the Compose copy, unchanged — the other half of the same requirement, and the reason for D6

## 6. Make it verifiable

- [ ] 6.1 Add `make check-site` asserting the cluster's copy specifically, distinguishing "the site is down" from "the cluster is unreachable" — `site-delivery` "The check fails when the site does not serve"
- [ ] 6.2 Confirm it fails when the workload is scaled to zero, and that the message names what did not answer
- [ ] 6.3 Wire it into `make check`

## 7. Prove it survives

- [ ] 7.1 Run `make rebuild CONFIRM=yes` and confirm the site serves again with no step beyond the rebuild — `site-delivery` "The site survives a rebuild"
- [ ] 7.2 Record the rebuild time now that a workload reconciles on boot, and update the README if the number has moved

## 8. Close the record

- [ ] 8.1 Update `README.md`, `CLAUDE.md` and `openspec/config.yaml`: the cluster serves something, and `k8s/` is deployed by ArgoCD rather than by OpenTofu
- [ ] 8.2 Record the boundary between what `tofu/` owns and what ArgoCD owns, so the next change does not have to rediscover it
- [ ] 8.3 Record in `LEARNINGS/` whatever the reconcile loop turned out to actually do — an entry only if something was learned the hard way

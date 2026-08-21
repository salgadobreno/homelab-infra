# k3s is one binary, and five of its seven pods are opinions

`[hit]` · 2026-08-21

Two separate questions hide behind "what did k3s install": how the control plane is
*arranged*, and what got deployed *on top*.

**The arrangement.** A kubeadm cluster runs the apiserver, scheduler, controller-manager
and etcd as static pods — you can see them in `kube-system`. Here:

```
$ kubectl get pods -n kube-system | grep -E 'apiserver|etcd|scheduler|controller-manager'
NONE - no control-plane pods at all
```

They are all goroutines inside a single 82 MB `/usr/local/bin/k3s`, along with kubelet,
containerd and flannel. That is the whole trick: same components, same APIs, packed into
one process instead of orchestrated as pods. Certified-conformant, so `kubectl` cannot
tell the difference — but `systemctl restart k3s` restarts the entire control plane at
once, which a kubeadm cluster would never do.

**The datastore is sqlite, not etcd** — `/var/lib/rancher/k3s/server/db/state.db`, 11 MB
with a 6 MB write-ahead log. This is the D10 storage argument made concrete: that WAL is
fsync-bound, which is why node disks live on the NVMe. M6 swaps it for embedded
etcd, and the requirement gets stricter, not looser.

**What got deployed on top.** Seven manifests in
`/var/lib/rancher/k3s/server/manifests/` are applied automatically at first boot:

| Component | Kubernetes proper? |
|---|---|
| coredns | Yes — every conformant cluster needs cluster DNS |
| metrics-server | Standard addon, but not core; `kubectl top` depends on it |
| flannel (CNI) | Upstream makes you *choose* a CNI; k3s chose for you |
| traefik | k3s's opinion — upstream ships no default ingress controller |
| local-path-provisioner | k3s's opinion — upstream ships no default StorageClass |
| svclb / klipper-lb | k3s's opinion — fakes LoadBalancer with a hostPort DaemonSet |
| ccm | k3s's stub cloud-controller-manager |

Traefik arrives through a `HelmChart` custom resource, served from the apiserver itself
(`https://%{KUBERNETES_API}%/static/charts/…`) rather than the internet — k3s embeds a
Helm controller so a cluster can bootstrap offline.

**Forward-looking consequence, worth knowing before M6:** klipper-lb already
claims `Service type=LoadBalancer`. Installing MetalLB alongside it means two controllers
answering for the same thing. k3s must be started with `--disable servicelb`, which is a
change to the cloud-init `runcmd` and therefore to the *provisioning* layer — not
something that can be fixed from inside the cluster with GitOps. Same likely applies to
`--disable traefik` if ingress is managed declaratively later.

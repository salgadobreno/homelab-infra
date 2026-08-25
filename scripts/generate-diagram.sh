#!/usr/bin/env bash
# Generate k8s/site/content/index.html: hand-written parts plus a reading of the cluster.
#
# The page is static content. It is generated here, committed, and deployed by
# ArgoCD like any other page — nothing in the cluster renders it at request
# time. `make check-diagram` fails if what is committed disagrees with what this
# script would produce now, so the page can be wrong but not wrong and green.
#
# Determinism is a requirement, not a nicety: an identical cluster must produce
# a byte-identical file, or the drift check fails at random and gets ignored.
# See design D3. The four sources of spurious difference, and their treatment:
#
#   AGE / uptime            omitted entirely — it changes every run
#   READY (1/1)             desired replicas are reported, never current, so a
#                           pod restarting mid-generation does not change output
#   row order               every list is sorted explicitly
#   generated name suffixes svclb-traefik-df1a854e keeps a hash derived from the
#                           Service; it survives a restart but not a rebuild, so
#                           the suffix is stripped rather than the row dropped
#
# A fifth source turned up while building this and is worth naming, because it
# cannot be normalised away — it has to be left out. ArgoCD's synced revision is
# the commit containing this file. Publishing it means every push changes what
# the page should say, so the drift check goes red after each commit; and the
# fix — regenerate and commit — is itself a new commit, which changes the value
# again. There is no fixpoint. Sync status and health are reported; the revision
# is not. Normalising it away instead would let the page show a stale commit and
# stay green, which is precisely what D2 forbids.
#
# Reads the operator's kubeconfig from this host. Writes one file. No root.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export KUBECONFIG="${KUBECONFIG:-$repo_root/kubeconfig}"
out="${1:-$repo_root/k8s/site/content/index.html}"

# The site is one page, composed here. Everything in parts/ is hand-written and
# inlined verbatim, so it is static input and does not affect determinism; only
# the snapshot between them is read from the cluster.
parts="$repo_root/k8s/site/parts"

command -v kubectl >/dev/null || { echo "FAIL: kubectl not on PATH" >&2; exit 1; }
command -v jq >/dev/null      || { echo "FAIL: jq not on PATH" >&2; exit 1; }
for f in intro architecture; do
    [ -r "$parts/$f.html" ] || { echo "FAIL: cannot read k8s/site/parts/$f.html" >&2; exit 1; }
done

kubectl get --raw /readyz >/dev/null 2>&1 || {
    echo "FAIL: cannot reach the cluster with $KUBECONFIG" >&2
    echo "      run 'make kubeconfig' if the node was rebuilt" >&2
    exit 1
}

# --- the node ----------------------------------------------------------------
# Capacity, not allocatable: capacity is what the machine has and is stable,
# allocatable moves as k3s revises its own reservations.
node_json="$(kubectl get nodes -o json)"
IFS=$'\t' read -r node_name node_status node_kubelet node_cpu node_mem_ki node_os node_runtime <<EOF
$(printf '%s' "$node_json" | jq -r '
  .items | sort_by(.metadata.name) | .[0] |
  [ .metadata.name,
    ([.status.conditions[] | select(.type=="Ready") | .status] | first),
    .status.nodeInfo.kubeletVersion,
    .status.capacity.cpu,
    (.status.capacity.memory | rtrimstr("Ki")),
    .status.nodeInfo.osImage,
    (.status.nodeInfo.containerRuntimeVersion | sub("://"; " "))
  ] | @tsv')
EOF
node_count="$(printf '%s' "$node_json" | jq '.items | length')"
[ "$node_status" = "True" ] && node_ready="Ready" || node_ready="Not Ready"
node_mem="$(awk -v k="$node_mem_ki" 'BEGIN{printf "%.1f", k/1048576}')"

# --- what is running ---------------------------------------------------------
# Desired counts. A DaemonSet's desired count is derived from the nodes that
# match it, which is a fact about the cluster rather than a momentary state.
workloads="$(
  {
    kubectl get deployments -A -o json | jq -r '.items[] |
      [.metadata.namespace, .metadata.name, "Deployment",
       (.spec.replicas // 0 | tostring),
       (.spec.template.spec.containers[0].image)] | @tsv'
    kubectl get statefulsets -A -o json | jq -r '.items[] |
      [.metadata.namespace, .metadata.name, "StatefulSet",
       (.spec.replicas // 0 | tostring),
       (.spec.template.spec.containers[0].image)] | @tsv'
    kubectl get daemonsets -A -o json | jq -r '.items[] |
      [.metadata.namespace,
       (.metadata.name | sub("-[0-9a-f]{6,}$"; "")),
       "DaemonSet",
       (.status.desiredNumberScheduled // 0 | tostring),
       (.spec.template.spec.containers[0].image)] | @tsv'
  } | LC_ALL=C sort -t"$(printf '\t')" -k1,1 -k2,2
)"

# --- the reconciler ----------------------------------------------------------
app="$(kubectl get applications.argoproj.io -n argocd -o json | jq -r '
  .items | sort_by(.metadata.name) | .[] |
  [ .metadata.name,
    (.status.sync.status // "Unknown"),
    (.status.health.status // "Unknown"),
    .spec.source.repoURL,
    .spec.source.path ] | @tsv')"

hosts="$(kubectl get ingress -A -o json | jq -r '
  [.items[].spec.rules[].host] | sort | unique | join(", ")')"

# --- render ------------------------------------------------------------------
html_escape() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

{
cat <<HEAD
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>buzaga.com.br</title>
<script src="https://cdn.tailwindcss.com"></script>
<!-- Generated by scripts/generate-diagram.sh from k8s/site/parts/ and a reading
     of the cluster. Do not edit this file: it is output. \`make diagram\`
     regenerates it, \`make check-diagram\` fails when it and the cluster
     disagree, so the page can be wrong but not wrong and green. -->
</head>
<body class="font-mono bg-gray-50 min-h-screen">
<div class="flex justify-center py-16">
<div class="max-w-3xl w-full mx-4">
<div class="border-2 border-dashed border-gray-400 p-8 bg-white">
HEAD

cat "$parts/intro.html"
cat "$parts/architecture.html"

cat <<SNAPSHOT
<section class="border-t border-gray-300 pt-6">
  <h2 class="text-xl mb-1">Cluster snapshot</h2>
  <p class="text-gray-500 text-sm mb-4">Read from the cluster by a command, then committed. No part of this section was written by hand.</p>

  <h3 class="text-sm text-gray-500 uppercase tracking-wide mb-2">The machine</h3>
  <ul class="mb-6 text-sm">
    <li>${node_count} node &middot; <span class="font-semibold">$(printf '%s' "$node_name" | html_escape)</span> &middot; ${node_ready}</li>
    <li>Kubernetes $(printf '%s' "$node_kubelet" | html_escape) &middot; ${node_cpu} vCPU &middot; ${node_mem} GiB</li>
    <li>$(printf '%s' "$node_os" | html_escape) &middot; $(printf '%s' "$node_runtime" | html_escape)</li>
  </ul>

  <h3 class="text-sm text-gray-500 uppercase tracking-wide mb-2">What runs on it</h3>
  <p class="text-gray-500 text-sm mb-2">Counts are what the cluster has been <em>asked</em> to run, not what happens to be up at this instant. That is deliberate: a number that flickers while a container restarts would make this page impossible to check.</p>
  <div class="overflow-x-auto mb-6">
  <table class="text-sm w-full">
    <thead class="text-gray-500 text-left">
      <tr><th class="pr-4 font-normal">namespace</th><th class="pr-4 font-normal">workload</th><th class="pr-4 font-normal">replicas</th><th class="font-normal">image</th></tr>
    </thead>
    <tbody>
SNAPSHOT

while IFS=$'\t' read -r ns name kind want image; do
    [ -n "${ns:-}" ] || continue
    printf '      <tr><td class="pr-4 text-gray-500">%s</td><td class="pr-4">%s</td><td class="pr-4">%s</td><td class="text-gray-600 break-all">%s</td></tr>\n' \
        "$(printf '%s' "$ns" | html_escape)" \
        "$(printf '%s' "$name" | html_escape)" \
        "$want" \
        "$(printf '%s' "$image" | html_escape)"
done <<< "$workloads"

cat <<MID
    </tbody>
  </table>
  </div>

  <h3 class="text-sm text-gray-500 uppercase tracking-wide mb-2">How it got here</h3>
  <p class="text-gray-500 text-sm mb-2">None of it was deployed by hand. A program inside the cluster watches a Git repository and continuously makes the cluster match it, so the repository is the record of what is running rather than a description of what someone intended.</p>
  <ul class="mb-2 text-sm">
MID

while IFS=$'\t' read -r aname async ahealth arepo apath; do
    [ -n "${aname:-}" ] || continue
    printf '    <li><span class="font-semibold">%s</span> &middot; %s &middot; %s</li>\n' \
        "$(printf '%s' "$aname" | html_escape)" "$async" "$ahealth"
    printf '    <li class="text-gray-600">reconciled from <span class="break-all">%s</span> at <code>%s</code></li>\n' \
        "$(printf '%s' "$arepo" | html_escape)" "$(printf '%s' "$apath" | html_escape)"
done <<< "$app"

cat <<MID2
  </ul>
  <p class="text-sm text-gray-600">Served for $(printf '%s' "$hosts" | html_escape).</p>
</section>
MID2

cat <<TAIL
<!-- served-by: k3s -->
</div>
</div>
</div>
</body>
</html>
TAIL
} > "$out.tmp"

mv "$out.tmp" "$out"
echo "wrote ${out#$repo_root/}"

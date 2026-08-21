# Verifying recovery means proving the disruption happened first

`[hit]` · 2026-08-21

Twice now, a readiness check has passed without waiting for anything.

The cloud-init gate ran `kubectl wait --for=condition=Ready node --all` before the node
object existed. `wait` does not block for a resource to *appear* — it errors instantly
with `no matching resources found`, and cloud-init wrote its completion marker anyway.

The reboot check made the same mistake from the other end: it polled for "2 ready
replicas" immediately after issuing the reboot, matched the *pre-reboot* state, and
declared recovery in 27 seconds while the deployment was actually at 0/2.

Fundamental: a check for "is it healthy" is not a check for "did it recover". The
second needs a fact that could only be true after the disruption — node boot time,
a restart count, a resource UID. Here the honest evidence was `uptime -s` moving and
`/proc/uptime` reading 57 seconds.

Adjacent trap from the same session: the node runs UTC and the host UTC−03, so
`date -d "$(ssh node uptime -s)"` produced a recovery time of −10764 seconds. Compare
instants, not wall-clock strings, across machines.

# A 404 from the ingress is not a missing site

`[301]` · took the public site down during a hostname cutover

## What happened

A public hostname was repointed from an old origin to traefik in the cluster. The site
started returning **404**.

The obvious readings were both wrong. The workload was running and healthy. The origin
address was correct.

## The distinction that located it in one step

| Symptom | Means |
|---|---|
| **502 / 530** from the CDN | Nothing accepted the connection — wrong host, wrong port, nothing listening |
| **404** from the origin | Something accepted it and had no route for what was asked |

A 404 is a *successful* connection to a server that decided it had nothing to serve. That
rules out the whole class of "did I point it at the right place" causes immediately, and
points at routing rather than reachability.

## The cause

An `Ingress` matches on the `Host` header. The tunnel forwarded the original header
unchanged, and the Ingress listed only the *other* hostname:

```yaml
rules:
  - host: k8s.example.com     # the only rule
```

A request arriving as `Host: example.com` matched nothing, and traefik answered 404
because that is what an ingress controller does with a name it does not recognise.

Adding the hostnames fixed it:

```yaml
rules:
  - host: example.com
    http: &site
      paths: [...]
  - host: www.example.com
    http: *site
  - host: k8s.example.com
    http: *site
```

## Why it was invisible until then

The Ingress was written when exactly one public name reached the cluster. It was not
wrong — it was **complete for one name and silently incomplete for two**, and nothing in
Kubernetes flags that. There is no warning for "this Ingress does not cover a hostname
that will eventually arrive", because nothing knows what will arrive.

The general shape: **a host-based rule encodes an assumption about who will call**, and
that assumption is invisible until the caller changes. Path-based and catch-all rules
have the opposite failure — they answer for names they should not.

## What to do about it

- **When adding a hostname anywhere upstream, check the ingress rule before repointing.**
  It is a one-line grep and it is the difference between a clean cutover and an outage.
- **Sequence a cutover so the old origin is still running.** The fix took minutes; the
  outage would have lasted as long as the diagnosis if the old origin had already been
  torn down.
- **Test with the header, not just the address.** `curl -H 'Host: example.com'` against
  the node reproduces exactly what the tunnel does. Asking without the header asks a
  different question, and can pass while the real one fails.

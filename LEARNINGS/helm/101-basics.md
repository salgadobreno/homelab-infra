# Helm charts

`[101]` · written to be read cold, no project knowledge assumed

## The problem it solves

Deploying anything real to Kubernetes means writing several YAML objects that have to agree
with each other: a Deployment, a Service, an Ingress, a ConfigMap, probably a
ServiceAccount. The application's name appears in all of them. So does its label set. The
Service's selector has to match the Deployment's pod labels exactly, or it silently routes
to nothing.

Now deploy the same application to staging and production, with a different replica count,
a different hostname and a different image tag. The obvious move is to copy the directory
and edit it, and from that moment the two copies drift.

Helm is the answer to *"how do I install this application, configured for my situation,
without hand-editing a pile of YAML."*

## What a chart is

A **chart** is a directory of templated Kubernetes manifests plus a file of default values.

```
mychart/
  Chart.yaml         name, version, appVersion, dependencies
  values.yaml        the defaults, and the documented knobs
  templates/
    deployment.yaml  Kubernetes YAML with {{ }} placeholders
    service.yaml
    _helpers.tpl     named snippets reused across templates
```

The templates are Go templates. A fragment looks like:

```yaml
spec:
  replicas: {{ .Values.replicaCount }}
  template:
    spec:
      containers:
        - image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
```

`.Values` is `values.yaml`, with your overrides merged over it. There is also `.Chart`
(metadata) and `.Release` (the name and namespace you are installing as).

Three terms that get confused:

| Term | Meaning |
|---|---|
| **Chart version** | the version of the packaging — bumped when the templates change |
| **appVersion** | the version of the software being packaged — often unrelated |
| **Release** | one *installation* of a chart, with a name; installing twice gives two releases |

A chart is a package. A release is an instance of it. The same chart installed as
`db-staging` and `db-prod` is two releases, tracked independently.

## Installing and configuring

```bash
helm repo add <name> <url>          # register a chart repository
helm install myapp <repo>/<chart>   # create a release
helm upgrade myapp <repo>/<chart>   # change it
helm list                           # what is installed
helm uninstall myapp
```

Configuration is `values.yaml` overrides, and the only sane way to do it is a file you keep:

```bash
helm install myapp repo/chart -f my-values.yaml
helm install myapp repo/chart --set replicaCount=3     # fine for one-offs
```

**Values merge, they do not replace — except for lists.** A map you override is merged key
by key with the defaults, so you specify only what differs. A *list* you override replaces
the whole list. That asymmetry is a routine source of surprise: setting one item of a
default list of five leaves you with one item, not five.

Two commands worth using before every install:

```bash
helm show values <repo>/<chart>     # every knob and its default — this is the API
helm template myapp <repo>/<chart> -f my-values.yaml
```

`helm template` renders locally and prints the YAML without contacting a cluster. It is how
you find out what a chart will actually create, and it turns "I hope this value does what I
think" into something you can read.

## What Helm does that plain YAML does not

**It tracks the release.** Helm stores the rendered manifests in a Secret in the cluster,
one per revision. That is what makes `helm upgrade` know which objects belong to the
release, `helm rollback` able to go back, and `helm uninstall` able to delete exactly what
it created and nothing else.

```bash
helm history myapp
helm rollback myapp 3
```

This state is the substantive difference from `kubectl apply -f`. It also means Helm's view
of reality can diverge from the cluster's: edit an object by hand and Helm's stored copy
still describes what it last applied.

**It resolves dependencies.** A chart can declare other charts in `Chart.yaml`, so
installing one brings its database along.

## The parts that bite

**Templating YAML as text.** Helm renders strings and *then* parses YAML, so indentation is
your problem. A value substituted at the wrong depth produces either a parse error or,
worse, valid YAML meaning something else. `{{ toYaml .Values.thing | nindent 8 }}` is the
usual incantation, and `helm template` is how you check it.

**Everything is resolved before anything is applied.** Helm renders and validates the whole
release against the API server first, then applies. The practical consequence: a chart
cannot contain both a CustomResourceDefinition and an instance of it — validation fails on
the instance because the kind does not exist yet. Hence the separate `crds/` directory,
installed before templates and never upgraded.

**Values are untyped and unvalidated by default.** Misspell a key and Helm does not
complain; it uses the default and you get behaviour you did not ask for. `helm template |
grep` for what you expected to change is the cheap defence. Charts *can* ship a
`values.schema.json`, and the good ones do.

**`helm upgrade` is not declarative in the way `kubectl apply` is.** It computes a patch
against the previous *release*, not against the live cluster. Something changed outside
Helm may not be corrected, and may not be noticed.

## Where it sits next to the alternatives

- **Plain manifests** — nothing to learn, no parameterisation. Right until you need a
  second environment.
- **Kustomize** — no templating: a base plus overlays that patch it. Simpler and safer to
  reason about; awkward when you need real conditionals. Built into `kubectl`.
- **Helm** — full templating and a package ecosystem. The reason to learn it is that
  third-party software is distributed this way, so consuming charts is not optional even
  in a repository that prefers Kustomize for its own manifests.

A common arrangement is both: Helm for other people's software, Kustomize for your own.

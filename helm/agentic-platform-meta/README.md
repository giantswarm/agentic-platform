# agentic-platform-meta (POC)

> **Status: proof of concept.** A sibling to the `agentic-platform` umbrella that
> demonstrates the **app-of-apps meta-package** release flow from
> [giantswarm/giantswarm#36875](https://github.com/giantswarm/giantswarm/issues/36875).
> The existing umbrella is untouched. Nothing here is wired into a cluster yet.

## What problem this solves

The `agentic-platform` umbrella pins every component to an exact version in
`Chart.yaml`. Helm bundles subchart `.tgz` archives at **package time**, so the
umbrella structurally cannot auto-update. Every component release therefore costs
a five-step hoop (Renovate bump PR → review → merge → umbrella re-release →
gitops bump). Too slow and token-expensive for internal dogfooding.

## How the meta-package works

This chart bundles **no subcharts** (note the absent `dependencies:` block in
`Chart.yaml` — that is the point). Its templates instead **render one
GitOps object per component**:

| `gitops.engine` | rendered per component |
|---|---|
| `flux` (default) | `OCIRepository` (semver range) + `HelmRelease` (`chartRef` + values) |
| `argo` | `Application` (`repoURL` + `chart` + `targetRevision` + `valuesObject`) |

The GitOps controller re-resolves the version **range** on every reconcile and
rolls a component forward when a new matching chart tag appears — **no PR to this
chart, no re-package**. The meta-chart is re-released only when the *wiring shape*
changes.

```
component repo releases vX.Y.Z  →  Flux re-resolves the range  →  component upgraded
                                   (this chart never moves)
```

## Two content layers

- **Component layer** (`components.*`): muster, agentgateway, kagent,
  klaus-gateway, valkey, agentic-platform-mcps, **and** agentic-platform-crds —
  each a rendered `HelmRelease`/`Application` with a version range. Never
  re-released by us.
- **Integration / glue layer** (`glue.*` + plain templates): the wiring this repo
  owns. In this POC that is just the namespace; the umbrella's `Gateway`,
  `AgentgatewayParameters`, `HTTPRoute`s, `NetworkPolicy`s and the `mcpServers`
  list move here unchanged.

CRD-before-CR ordering is preserved: `agentic-platform-crds` is just another
rendered release that every consumer `dependsOn` (Flux) / orders ahead of via
`argocd.argoproj.io/sync-wave` (Argo).

## Version policy is a value, not a `Chart.yaml` pin

```yaml
components:
  muster:        { versionRange: "0.4.x" }
  agentgateway:  { versionRange: ">=1.0.0 <2.0.0" }   # exclude a v2 reset
  kagent:        { versionRange: "0.9.x" }
  klaus-gateway: { versionRange: ">=0.0.0-0", filterTags: { pattern: '.*-dev\..*' } }
```

`values:` per component passes straight through to that component's release,
exactly like the umbrella passes subchart values today.

## Dev vs customer: same chart, two presets

| Track | Preset | Behaviour |
|---|---|---|
| **(1) Internal / dogfooding** | `values.yaml` (default) — wide ranges | continuous auto-update on the management clusters, **zero PRs** |
| **(2) Customer** | `-f ci/customer-bom-values.yaml` — exact pins | reproducible bill-of-materials; upgrades are a deliberate values edit |

A "product release" is a **values lock**: snapshot the resolved versions from a
known-good dev state into the BOM. No separate release object needed.

## Try it

```bash
# (1) internal preset — Flux objects with wide ranges
helm template t helm/agentic-platform-meta

# render the Argo variant instead
helm template t helm/agentic-platform-meta --set gitops.engine=argo

# (2) customer bill-of-materials — every range pinned
helm template t helm/agentic-platform-meta -f helm/agentic-platform-meta/ci/customer-bom-values.yaml

# the runnable check (also in CI as `test-meta-package`)
make verify-meta
```

## Mapping to issue #36875 acceptance criteria

- **A new component release reaches dogfooding clusters without a PR** — Flux
  re-resolves the `OCIRepository` semver range; the meta-chart never moves.
- **Internal auto-updates, customer pins a BOM** — `values.yaml` (wide) vs
  `ci/customer-bom-values.yaml` (exact).
- **CRD-before-CR ordering preserved** — `dependsOn: [agentic-platform-crds]`
  (Flux) / sync-wave 0 (Argo).
- **Per-component values passthrough unchanged** — `components.<c>.values` →
  `HelmRelease.spec.values` / `Application…valuesObject`.
- **Migration path keeps the umbrella working** — this is an additive sibling
  chart; the pinned umbrella is untouched.

Full concept: `architecture/agentic-platform-meta-package.md` in the klaus-lab.

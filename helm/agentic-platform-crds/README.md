# agentic-platform-crds

CustomResourceDefinitions for the Giant Swarm [agentic platform](https://github.com/giantswarm/agentic-platform). This is a CRD-only umbrella chart: installing it installs the CRDs, and nothing else. The companion `agentic-platform` chart ships the workloads and the CRs that consume these CRDs.

Owner: team-bumblebee.

## Why a separate chart

CRDs and the CRs that use them have different lifecycles and must be applied in order (CRDs first, then CRs). Shipping them in one Helm release races on install under Flux/Argo and couples CRD upgrades to workload upgrades. Splitting CRDs into their own release makes the ordering a plain "two releases in sequence" — agnostic of Flux `dependsOn` or Argo sync-waves.

## What it ships

| CRDs | Group | Source sub-chart |
|---|---|---|
| `agentgatewayparameters`, `agentgatewaypolicies`, `agentgatewaybackends` | `agentgateway.dev` | [`agentgateway-crds`](oci://cr.agentgateway.dev/charts/agentgateway-crds) |
| `agents`, `agentharnesses`, `modelconfigs`, `mcpservers`, `remotemcpservers`, `memories`, `toolservers`, `sandboxagents` | `kagent.dev` | `kagent-crds` (`oci://ghcr.io/kagent-dev/kagent/helm/kagent-crds`) |
| `sandboxes`, `sandboxtemplates`, `sandboxclaims`, `sandboxwarmpools` | `agents.x-k8s.io` | `agent-sandbox-crds` (`oci://gsoci.azurecr.io/charts/giantswarm/agent-sandbox-crds`) |

The Gateway API CRDs (`gateways`, `httproutes`, `gatewayclasses.gateway.networking.k8s.io`) remain a cluster prerequisite and are **not** shipped here.

> **muster's CRDs are no longer in this bundle.** muster now ships `mcpservers` and
> `workflows` (`muster.giantswarm.io`) in its own app chart's `crds/` directory and
> owns their version, upgraded atomically with the app via Flux `CreateReplace`
> (the `agentic-platform` chart sets `crds: CreateReplace` on the muster component).
> This is the "app-owned CRDs" pattern; it removes the version-drift that the
> separate-bundle approach allowed between a CRD and its app.

## Install

Install this chart **before** the `agentic-platform` chart.

```bash
helm install agentic-platform-crds \
  oci://gsoci.azurecr.io/charts/giantswarm/agentic-platform-crds \
  --version <chart-version> --namespace muster --create-namespace
```

Then verify the CRDs are Established before installing the platform:

```bash
kubectl wait --for=condition=Established \
  crd/agentgatewayparameters.agentgateway.dev \
  crd/agents.kagent.dev
```

### Flux

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: agentic-platform-crds
  namespace: muster
spec:
  interval: 1h
  url: oci://gsoci.azurecr.io/charts/giantswarm/agentic-platform-crds
  ref: { tag: <chart-version> }
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: agentic-platform-crds
  namespace: muster
spec:
  interval: 10m
  chartRef: { kind: OCIRepository, name: agentic-platform-crds }
```

The `agentic-platform` HelmRelease should then declare `dependsOn: [{ name: agentic-platform-crds }]`.

## Uninstall behaviour — read this

`helm uninstall agentic-platform-crds` does **not** delete all CRDs uniformly:

| CRDs | `helm.sh/resource-policy: keep`? | On uninstall |
|---|---|---|
| `sandboxes`, `sandboxtemplates`, `sandboxclaims`, `sandboxwarmpools` (`agents.x-k8s.io`) | **Yes** | CRDs and their CRs **survive** (keep injected by `agent-sandbox-crds`). |
| `agentgatewayparameters`, `agentgatewaypolicies`, `agentgatewaybackends` (`agentgateway.dev`) | **No** | CRDs are **deleted** and the delete **cascades to every agentgateway CR cluster-wide**. |
| kagent CRDs (`kagent.dev`) | **No** | CRDs are **deleted** and the delete **cascades to every kagent CR cluster-wide**. |

The agentgateway and kagent CRDs are **not** keep-protected. The upstream charts render their CRDs without the annotation and expose **no values knob** to inject it, so this chart cannot add it via sub-chart values. This is a known gap:

- Uninstalling this release (named "crds", which makes it tempting to nuke casually) destroys all agentgateway and kagent CRs.
- The behaviour is unchanged from when these CRDs were bundled in the `agentic-platform` chart — wrapping them here does not add `keep`.

**Tracking:** an upstream change to parameterize the agentgateway CRD annotations is pending (referenced in the platform `CHANGELOG.md`). Once it lands, set `helm.sh/resource-policy: keep` for the agentgateway CRDs via `agentgateway-crds` sub-chart values in this chart's `values.yaml`. Until then, treat uninstalling this release as destructive for agentgateway and kagent CRs.

## Configuration

This chart carries no values of its own; the bundled sub-charts (`agentgateway-crds`, `kagent-crds`, `agent-sandbox-crds`) are installed with their defaults. The `agentgateway-crds` and `kagent-crds` sub-charts expose no relevant values today (see the keep-gap above).

## Upgrading

CRDs migrate as part of a `helm upgrade` of this release. An identical-content CRDs bump (re-published unchanged alongside a workload release) is a no-op upgrade. See [UPGRADE.md](../../UPGRADE.md) for the one-time ownership handoff when migrating from the `0.2.0` platform chart that bundled these CRDs.

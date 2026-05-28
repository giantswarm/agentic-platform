# agentic-platform-crds

CustomResourceDefinitions for the Giant Swarm [agentic platform](https://github.com/giantswarm/agentic-platform). This is a CRD-only umbrella chart: installing it installs the CRDs, and nothing else. The companion `agentic-platform` chart ships the workloads and the CRs that consume these CRDs.

Owner: team-bumblebee.

## Why a separate chart

CRDs and the CRs that use them have different lifecycles and must be applied in order (CRDs first, then CRs). Shipping them in one Helm release races on install under Flux/Argo and couples CRD upgrades to workload upgrades. Splitting CRDs into their own release makes the ordering a plain "two releases in sequence" — agnostic of Flux `dependsOn` or Argo sync-waves.

## What it ships

| CRDs | Group | Source sub-chart |
|---|---|---|
| `agentgatewayparameters`, `agentgatewaypolicies`, `agentgatewaybackends` | `agentgateway.dev` | [`agentgateway-crds`](oci://cr.agentgateway.dev/charts/agentgateway-crds) `v1.2.1` |
| `mcpservers`, `workflows` | `muster.giantswarm.io` | `muster-crds` (`oci://gsoci.azurecr.io/charts/giantswarm/muster-crds`) |

Five CRDs total. The Gateway API CRDs (`gateways`, `httproutes`, `gatewayclasses.gateway.networking.k8s.io`) remain a cluster prerequisite and are **not** shipped here.

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
  crd/mcpservers.muster.giantswarm.io
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
| `mcpservers`, `workflows` (`muster.giantswarm.io`) | **Yes** | CRDs and their `MCPServer` / `Workflow` CRs **survive**. |
| `agentgatewayparameters`, `agentgatewaypolicies`, `agentgatewaybackends` (`agentgateway.dev`) | **No** | CRDs are **deleted** and the delete **cascades to every agentgateway CR cluster-wide**. |

The muster CRDs are keep-protected via `muster-crds.crds.annotations` (set in this chart's `values.yaml` and defaulted by the `muster-crds` sub-chart).

The agentgateway CRDs are **not** keep-protected. The upstream `agentgateway-crds` chart renders its CRDs without the annotation and exposes **no values knob** to inject it, so this chart cannot add it via sub-chart values. This is a known gap:

- Uninstalling this release (now *named* "crds", which makes it tempting to nuke casually) destroys all agentgateway CRs.
- The behaviour is unchanged from when these CRDs were bundled in the `agentic-platform` chart — wrapping them here does not add `keep`.

**Tracking:** an upstream change to parameterize the agentgateway CRD annotations is pending (referenced in the platform `CHANGELOG.md`). Once it lands, set `helm.sh/resource-policy: keep` for the agentgateway CRDs via `agentgateway-crds` sub-chart values in this chart's `values.yaml`, mirroring the `muster-crds` block. Until then, treat uninstalling this release as destructive for agentgateway CRs.

## Configuration

| Key | Default | Purpose |
|---|---|---|
| `muster-crds.crds.annotations` | `{ helm.sh/resource-policy: keep }` | Annotations merged into the muster CRDs. Keeps them (and their CRs) on uninstall. |

The `agentgateway-crds` sub-chart exposes no relevant values today (see the keep-gap above).

## Upgrading

CRDs migrate as part of a `helm upgrade` of this release. An identical-content CRDs bump (re-published unchanged alongside a workload release) is a no-op upgrade. See [UPGRADE.md](../../UPGRADE.md) for the one-time ownership handoff when migrating from the `0.2.0` platform chart that bundled these CRDs.

[![CircleCI](https://dl.circleci.com/status-badge/img/gh/giantswarm/agentic-platform/tree/main.svg?style=svg)](https://dl.circleci.com/status-badge/redirect/gh/giantswarm/agentic-platform/tree/main)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/giantswarm/agentic-platform/badge)](https://securityscorecards.dev/viewer/?uri=github.com/giantswarm/agentic-platform)

# agentic-platform

The agentic platform is Giant Swarm's MCP gateway deploy unit. It ships [muster](https://github.com/giantswarm/muster) (MCP gateway / aggregator) and [agentgateway](https://github.com/agentgateway/agentgateway) (MCP data plane) together, plus the consumer-side `Gateway`, `AgentgatewayParameters`, and network policies that wire them up.

Owner: team-bumblebee.

## Prerequisites

- Kubernetes ≥ 1.33 on the install target.
- Gateway API v1 CRDs (`gateways.gateway.networking.k8s.io`, `httproutes.gateway.networking.k8s.io`, `gatewayclasses.gateway.networking.k8s.io`) installed cluster-wide. The agentic platform does **not** install them.
- `agentgateway-crds` chart installed (provides `AgentgatewayParameters`, `AgentgatewayBackend`, `AgentgatewayPolicy`). Not bundled — see [CRD lifecycle](#crd-lifecycle).
- `muster-crds` chart installed (provides `MCPServer`, `Workflow`). Not bundled — see [CRD lifecycle](#crd-lifecycle).
- A `GatewayClass` CR named `agentgateway` (`status.conditions[type=Accepted]=True`). The bundled `agentgateway` sub-chart creates it on install; operators managing the controller out-of-band must ensure the `GatewayClass` exists.
- Cilium CNI for `networkPolicy.flavor: cilium` (default). Vanilla Kubernetes clusters: set `networkPolicy.flavor: kubernetes`. Opt out entirely with `networkPolicy.enabled: false`.

## Installing

CRDs first, then the platform. Encode ordering with Flux `HelmRelease.spec.dependsOn` (or use the raw-Helm sequence).

### Flux

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: agentgateway-crds
  namespace: muster
spec:
  interval: 1h
  url: oci://cr.agentgateway.dev/charts/agentgateway-crds
  ref: { tag: v1.2.1 }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: muster-crds
  namespace: muster
spec:
  interval: 1h
  url: oci://gsoci.azurecr.io/charts/giantswarm/muster-crds
  ref: { tag: <muster-crds-version> }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: agentic-platform
  namespace: muster
spec:
  interval: 1h
  url: oci://gsoci.azurecr.io/charts/giantswarm/agentic-platform
  ref: { tag: <agentic-platform-version> }
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: agentgateway-crds
  namespace: muster
spec:
  interval: 10m
  chartRef: { kind: OCIRepository, name: agentgateway-crds }
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: muster-crds
  namespace: muster
spec:
  interval: 10m
  chartRef: { kind: OCIRepository, name: muster-crds }
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: agentic-platform
  namespace: muster
spec:
  interval: 10m
  chartRef: { kind: OCIRepository, name: agentic-platform }
  dependsOn:
    - { name: agentgateway-crds }
    - { name: muster-crds }
  valuesFrom:
    - kind: Secret
      name: agentic-platform-values
```

### Raw Helm

```bash
helm install agentgateway-crds \
  oci://cr.agentgateway.dev/charts/agentgateway-crds \
  --version v1.2.1 --namespace muster --create-namespace

helm install muster-crds \
  oci://gsoci.azurecr.io/charts/giantswarm/muster-crds \
  --version <muster-crds-version> --namespace muster

helm install agentic-platform \
  oci://gsoci.azurecr.io/charts/giantswarm/agentic-platform \
  --version <chart-version> --namespace muster -f values.yaml
```

## Configuration

| Key | Default | Purpose |
|---|---|---|
| `global.registry` | `gsoci.azurecr.io` | Default container image registry. |
| `gateway.name` | `agentgateway` | `Gateway` resource name. |
| `gateway.gatewayClassName` | `agentgateway` | The `GatewayClass` the data plane attaches to. |
| `gateway.listeners` | `[{name: http, port: 8080, protocol: HTTP}]` | Listener spec passed verbatim. |
| `gateway.parameters.serviceType` | `ClusterIP` | Data-plane Service type (overrides controller-hardcoded LoadBalancer via `AgentgatewayParameters.spec.service`). |
| `gateway.parameters.{pod,container}SecurityContext` | restricted-PSS compatible | Strategic-merge overlay on the data-plane Deployment. |
| `networkPolicy.enabled` | `true` | Master switch for the umbrella's network policies. |
| `networkPolicy.flavor` | `cilium` | `cilium` → CiliumNetworkPolicy; `kubernetes` → vanilla NetworkPolicy (best-effort, no entity selectors / FQDN egress). |
| `extraObjects` | `[]` | Arbitrary manifests rendered through `tpl` alongside the chart. |
| `muster.*` | passes through to muster | See [muster chart README](https://github.com/giantswarm/muster/blob/main/helm/muster/README.md). |
| `agentgateway.*` | passes through to upstream agentgateway | See [agentgateway docs](https://agentgateway.dev). |
| `valkey.enabled` | `false` | Bundle bitnami/valkey for muster OAuth session storage. |

Full schema: [`helm/agentic-platform/values.schema.json`](./helm/agentic-platform/values.schema.json).

### Gateway API CR ownership

Of the resources the umbrella manages, **only `AgentgatewayParameters` is vendor-specific** to agentgateway. Everything else is standard Gateway API / standard Cilium.

| Resource | API | Owned by | Notes |
|---|---|---|---|
| `Gateway` (data-plane spawn trigger) | `gateway.networking.k8s.io/v1` (standard) | this umbrella (`templates/agentgateway/gateway.yaml`) | Coupled to agentgateway only via `gatewayClassName: agentgateway`. One per data plane. |
| `AgentgatewayParameters` | `agentgateway.dev/v1alpha1` (**vendor-specific**) | this umbrella (`templates/agentgateway/agentgatewayparameters.yaml`) | The only agentgateway-vendor CR the umbrella ships. Strategic-merge overlay over the controller-rendered Deployment + Service; forces Service type ClusterIP by default. |
| `CiliumNetworkPolicy` / `NetworkPolicy` (×4 — controller + data-plane, per flavor) | `cilium.io/v2` or `networking.k8s.io/v1` | this umbrella (`templates/agentgateway/networkpolicy-*.yaml`) | Two pods covered: controller and data-plane. Upstream agentgateway ships no policies. |
| `HTTPRoute` (per app — muster, future tools) | `gateway.networking.k8s.io/v1` (standard) | each app's sub-chart | Attaches to the cluster's public Gateway (typically `envoy-gateway-system/giantswarm-default`), NOT to the umbrella's data-plane Gateway. |
| `Gateway` (public routing endpoint) | `gateway.networking.k8s.io/v1` (standard) | platform team | `envoy-gateway-system/giantswarm-default` — not owned by this chart. |

### OAuth secrets

Three orthogonal paths. None replace the others — pick what matches your topology.

| Path | Configured via | Use case |
|---|---|---|
| **Inline values** | `muster.muster.oauth.server.dex.clientSecret`, `registrationToken`, `encryptionKeyValue`, `storage.valkey.password` | Quick dev/test or GitOps with values-level encryption (sops + helm-secrets, Flux `decryption:`). No external Secret to manage. |
| **`existingSecret`** | `muster.muster.oauth.server.existingSecret: <name>` (Secret pre-created out-of-band) | Production Giant Swarm pattern — SOPS-encrypted Secret in giantswarm-configs reconciled by Flux ahead of the platform; or `kubectl create secret` for manual ops. |
| **`extraObjects`** | Umbrella-level `extraObjects: []` list (this chart) + muster `existingSecret` pointed at the rendered Secret | Single Helm release ships Secret + values together. Non-Flux operators (ArgoCD, vanilla Helm) who want one `helm upgrade` to manage everything. |

Example using `extraObjects` + `existingSecret`:

```yaml
extraObjects:
  - apiVersion: v1
    kind: Secret
    metadata:
      name: muster-oauth
    type: Opaque
    stringData:
      dex-client-secret: REPLACE_ME
      registration-token: REPLACE_ME
      oauth-encryption-key: REPLACE_ME
      valkey-password: REPLACE_ME

muster:
  muster:
    oauth:
      server:
        existingSecret: muster-oauth
```

Random auto-generation via Helm `lookup` is intentionally not supported — every `helm upgrade` would either regenerate values (invalidating issued tokens) or render different output under `helm template` / `--dry-run` than at install time.

### Dex / OIDC client registration

`muster.muster.oauth.server.dex.{issuerUrl,clientId}` and the matching `dex-client-secret` must correspond to a client registered against the cluster's Dex (or another OIDC issuer). The agentic platform does NOT register the client — that's the IdP operator's job. On Giant Swarm workload clusters running `dex-operator`:

```yaml
apiVersion: dex.giantswarm.io/v1alpha1
kind: DexIdentityProvider
metadata:
  name: muster
  namespace: <dex-operator-namespace>
spec:
  type: github
  name: GitHub
  connectorConfig:
    clientID: <github-app-id>
    clientSecret: <github-app-secret>
    redirectURI: https://muster.<cluster>.<base-domain>/oauth/callback
```

`redirectURI` must equal `<muster.oauth.server.baseUrl>/oauth/callback`.

### Bundled Valkey

`valkey.enabled: true` bundles a bitnami valkey instance with persistent storage. `fullnameOverride: muster-valkey` plus bitnami's primary/replica topology exposes the writable endpoint at `muster-valkey-primary.<namespace>.svc:6379` — **note the `-primary` suffix.**

```yaml
valkey:
  enabled: true
  auth:
    existingSecret: muster-oauth

muster:
  muster:
    oauth:
      server:
        storage:
          type: valkey
          valkey:
            url: muster-valkey-primary.<namespace>.svc:6379
            existingSecret: muster-oauth
```

Operators with an out-of-band Valkey leave `valkey.enabled: false` and configure `muster.muster.oauth.server.storage.valkey.*` directly. See [UPGRADE.md](./UPGRADE.md) for migration notes from a previously-existing standalone Valkey.

### Public HTTPRoute (required for OAuth)

The umbrella renders a `Gateway` for the **data plane** only — that Gateway is not exposed publicly and is not the right parent for muster's HTTPRoute. Muster's HTTPRoute must attach to the cluster's public Gateway (typically envoy-gateway-system) with hostnames that match the OAuth callback URL from `muster.oauth.mcpClient.publicUrl`.

The muster sub-chart's fail-guard rejects install until both `parentRefs` and `hostnames` are set:

```yaml
muster:
  gatewayAPI:
    enabled: true
    httpRoute:
      parentRefs:
        - name: giantswarm-default
          namespace: envoy-gateway-system
          group: gateway.networking.k8s.io
          kind: Gateway
      hostnames:
        - muster.<cluster>.<base-domain>
```

## Private registry overrides

All images default to `gsoci.azurecr.io/giantswarm/*`:

| Image | Source (mirrored by GS retagger) |
|---|---|
| `gsoci.azurecr.io/giantswarm/muster:0.1.193` | `gsoci.azurecr.io/giantswarm/muster` (native GS image) |
| `gsoci.azurecr.io/giantswarm/agentgateway-controller:v1.2.1` | `cr.agentgateway.dev/controller` |
| `gsoci.azurecr.io/giantswarm/agentgateway:v1.2.1` | `cr.agentgateway.dev/agentgateway` |

To pull from a private mirror, override the registry on every image (neither subchart exposes a `global.registry` that propagates to all images):

```yaml
global:
  registry: registry.example.com

muster:
  image:
    registry: registry.example.com

agentgateway:
  image:
    registry: registry.example.com
  proxy:
    image:
      registry: registry.example.com
```

## Security

The agentgateway data-plane pod template is rendered at runtime by the controller, not by Helm. To inject restricted-PSS-compatible `securityContext` fields, the umbrella ships an `AgentgatewayParameters` resource referenced from `Gateway.spec.infrastructure.parametersRef`. The controller applies it as a strategic merge patch over the generated Deployment and Service — that's how `gateway.parameters.serviceType: ClusterIP` forces the otherwise-hardcoded `type: LoadBalancer`.

The data-plane pod template hardcodes `sysctls: [net.ipv4.ip_unprivileged_port_start=0]`. This is a namespaced-safe sysctl (no kubelet allowlist required). On clusters with built-in Pod Security Admission `restricted` enforced, the sysctl will be rejected — label the install namespace with `pod-security.kubernetes.io/enforce: baseline` (or allowlist the sysctl in Kyverno's `restrict-sysctls` policy as Giant Swarm workload clusters already do).

## CRD lifecycle

The agentic platform does NOT install any CRDs. They are owned by three sibling releases:

| CRDs | Chart | Catalog |
|---|---|---|
| `gateways.gateway.networking.k8s.io`, `httproutes…`, `gatewayclasses…` | Gateway API upstream | cluster prerequisite |
| `agentgatewayparameters.agentgateway.dev`, `agentgatewaybackends…`, `agentgatewaypolicies…` | `agentgateway-crds` | `oci://cr.agentgateway.dev/charts/agentgateway-crds` |
| `mcpservers.muster.giantswarm.io`, `workflows.muster.giantswarm.io` | `muster-crds` | `oci://gsoci.azurecr.io/charts/giantswarm/muster-crds` |

Helm 3 only special-cases the top-level chart's `crds/` directory; sub-chart `crds/` is silently ignored. Sibling CRD charts decouple the schema lifecycle from the data plane and let `helm uninstall agentic-platform` skip CRDs and the CRs that depend on them.

### Adoption on clusters that already have the CRDs

If a previous topology installed the CRDs through a sub-chart, the new sibling releases will refuse to take ownership. One-time adoption:

```bash
for crd in $(kubectl get crd -o name | grep -E 'agentgateway\.dev$'); do
  kubectl annotate "$crd" \
    meta.helm.sh/release-name=agentgateway-crds \
    meta.helm.sh/release-namespace=muster --overwrite
  kubectl label "$crd" app.kubernetes.io/managed-by=Helm --overwrite
done

for crd in mcpservers.muster.giantswarm.io workflows.muster.giantswarm.io; do
  kubectl annotate "crd/$crd" \
    meta.helm.sh/release-name=muster-crds \
    meta.helm.sh/release-namespace=muster --overwrite
  kubectl label "crd/$crd" app.kubernetes.io/managed-by=Helm --overwrite
done
```

### Upgrading CRDs

See [`helm/muster-crds/UPGRADE.md`](https://github.com/giantswarm/muster/blob/main/helm/muster-crds/UPGRADE.md) for muster's schema-change ratchet. For `agentgateway-crds`, follow upstream release notes.

## Compatibility

Targets Giant Swarm workload clusters running Kubernetes ≥ 1.33 with Cilium and Kyverno. The `kubernetes` NetworkPolicy flavor works on any CNI but is best-effort (no entity selectors, no FQDN egress).

## Credit

- [muster](https://github.com/giantswarm/muster) — Giant Swarm, Apache 2.0.
- [agentgateway](https://github.com/agentgateway/agentgateway) — agentgateway authors, Apache 2.0.

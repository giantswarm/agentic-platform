[![CircleCI](https://dl.circleci.com/status-badge/img/gh/giantswarm/agentic-platform/tree/main.svg?style=svg)](https://dl.circleci.com/status-badge/redirect/gh/giantswarm/agentic-platform/tree/main)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/giantswarm/agentic-platform/badge)](https://securityscorecards.dev/viewer/?uri=github.com/giantswarm/agentic-platform)

# agentic-platform

The agentic platform is Giant Swarm's MCP gateway deploy unit. It ships [muster](https://github.com/giantswarm/muster) (MCP gateway / aggregator) and [agentgateway](https://github.com/agentgateway/agentgateway) (MCP data plane) together, plus the consumer-side `Gateway`, `AgentgatewayParameters`, and network policies that wire them up.

Owner: team-bumblebee.

## Prerequisites

- Kubernetes ≥ 1.33 on the install target.
- Gateway API v1 CRDs (`gateways.gateway.networking.k8s.io`, `httproutes.gateway.networking.k8s.io`, `gatewayclasses.gateway.networking.k8s.io`) installed cluster-wide. The agentic platform does **not** install them.
- The companion **`agentic-platform-crds` chart installed first** — it ships all CRDs this chart's CRs consume (`AgentgatewayParameters` / `AgentgatewayPolicy` / `AgentgatewayBackend` and muster's `MCPServer` / `Workflow`). This chart installs **no** CRDs of its own; see [CRD lifecycle](#crd-lifecycle).
- A `GatewayClass` CR named `agentgateway` (`status.conditions[type=Accepted]=True`). The bundled `agentgateway` sub-chart creates it on install; operators managing the controller out-of-band must ensure the `GatewayClass` exists.
- Cilium CNI for `networkPolicy.flavor: cilium` (default). Vanilla Kubernetes clusters: set `networkPolicy.flavor: kubernetes` **AND** `muster.networkPolicy.flavor: kubernetes` **AND** `valkey.ciliumNetworkPolicy.enabled: false` (the bundled valkey wrapper's CNP has no kubernetes-flavor counterpart). Opt out entirely with `networkPolicy.enabled: false` + `muster.networkPolicy.enabled: false` + `valkey.ciliumNetworkPolicy.enabled: false`.

## Installing

Two charts from this repo, installed **in order**: the companion `agentic-platform-crds` chart first (it ships every CRD this chart's CRs need), then `agentic-platform`. CRD and workload lifecycles are decoupled — ordering is just "two releases in sequence", agnostic of Flux `dependsOn` / Argo sync-waves.

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
  ref: { tag: <agentic-platform-crds-version> }
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
  name: agentic-platform-crds
  namespace: muster
spec:
  interval: 10m
  chartRef: { kind: OCIRepository, name: agentic-platform-crds }
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
    - { name: agentic-platform-crds }
  valuesFrom:
    - kind: Secret
      name: agentic-platform-values
```

### Raw Helm

```bash
helm install agentic-platform-crds \
  oci://gsoci.azurecr.io/charts/giantswarm/agentic-platform-crds \
  --version <crds-chart-version> --namespace muster --create-namespace

helm install agentic-platform \
  oci://gsoci.azurecr.io/charts/giantswarm/agentic-platform \
  --version <chart-version> --namespace muster -f values.yaml
```

#### Raw CRD-chart fallback (no `agentic-platform-crds`)

`agentic-platform-crds` is a thin umbrella over two upstream CRD charts. If you prefer to manage the CRD charts directly (or already run a shared `agentgateway-crds` release), install both source charts instead — they provide the same five CRDs:

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
| `ingress.mode` | `muster-direct` | Request topology selector. `muster-direct` (client → muster, no agentgateway data plane), `agentgateway-muster` (client → agentgateway `/mcp` → muster), or `agentgateway-direct` (client → agentgateway `/mcp` → servers; **not yet supported**). See [Ingress topology](#ingress-topology). |
| `ingress.parentRefs` | `[]` | **All modes.** The public `Gateway`(s) both rendered routes attach to (typically `envoy-gateway-system/giantswarm-default`). Required in `agentgateway-*` modes. |
| `ingress.hostnames` | `[]` | **All modes.** muster's public hostname(s); must match the OAuth callback URL. |
| `ingress.backendTrafficPolicy.enabled` | `false` | Render route-scoped `BackendTrafficPolicy` objects (preserve `WWW-Authenticate`, set `requestTimeout: 0s`): one over muster's `/` route in **all** modes, plus one over the agentgateway `/mcp` route in `agentgateway-*` modes. |
| `agentgateway.enabled` | `false` | Install the agentgateway controller dependency. Must be `true` in `agentgateway-*` modes. |
| `gateway.name` | `agentgateway` | `agentgateway-*` modes only. Data-plane `Gateway` resource name. |
| `gateway.gatewayClassName` | `agentgateway` | `agentgateway-*` modes only. The `GatewayClass` the data plane attaches to. |
| `gateway.listeners` | `[{name: http, port: 8080, protocol: HTTP}]` | `agentgateway-*` modes only. Listener spec passed verbatim. |
| `gateway.parameters.serviceType` | `ClusterIP` | `agentgateway-*` modes only. Data-plane Service type (overrides controller-hardcoded LoadBalancer via `AgentgatewayParameters.spec.service`). |
| `gateway.parameters.{pod,container}SecurityContext` | restricted-PSS compatible | `agentgateway-*` modes only. Strategic-merge overlay on the data-plane Deployment. |
| `networkPolicy.enabled` | `true` | Master switch for the umbrella's network policies. |
| `networkPolicy.flavor` | `cilium` | `cilium` → CiliumNetworkPolicy; `kubernetes` → vanilla NetworkPolicy (best-effort, no entity selectors / FQDN egress). |
| `extraObjects` | `[]` | Arbitrary manifests rendered through `tpl` alongside the chart. |
| `muster.*` | passes through to muster | See [muster chart README](https://github.com/giantswarm/muster/blob/main/helm/muster/README.md). |
| `agentgateway.*` | passes through to upstream agentgateway | See [agentgateway docs](https://agentgateway.dev). |
| `valkey.enabled` | `true` | Bundle [giantswarm/valkey-app](https://github.com/giantswarm/valkey-app) for muster OAuth session storage. |
| `mcps.enabled` | `false` | Bundle [giantswarm/agentic-platform-mcps](https://github.com/giantswarm/agentic-platform-mcps) to render the platform's MCP server CRs. Toggle is separate from the value namespace — see [Bundled MCP servers](#bundled-mcp-servers). |
| `agentic-platform-mcps.mcpServers` | `[]` | Abstract list of MCP servers rendered into `MCPServer` / `AgentgatewayBackend` CRs. Renders nothing until populated. |
| `muster.muster.oauth.server.enabled` | `true` | OAuth resource-server protection on the muster API. Requires `baseUrl`, `dex.{issuerUrl,clientId}`, and a Secret carrying `dex-client-secret` / `registration-token` / `oauth-encryption-key` / `valkey-password`. |
| `muster.muster.oauth.server.storage.type` | `valkey` | Muster storage backend default. Pairs with `valkey.enabled: true`; flip to `memory` for dev. |
| `muster.muster.oauth.server.storage.valkey.url` | `muster-valkey:6379` | Bundled-valkey Service. Override to point at an out-of-band Valkey. |

Full schema: [`helm/agentic-platform/values.schema.json`](./helm/agentic-platform/values.schema.json).

### Gateway API CR ownership

Of the resources the umbrella manages, **only `AgentgatewayParameters` is vendor-specific** to agentgateway. Everything else is standard Gateway API / standard Cilium.

| Resource | API | Owned by | Notes |
|---|---|---|---|
| `Gateway` (data-plane spawn trigger) | `gateway.networking.k8s.io/v1` (standard) | this umbrella (`templates/agentgateway/gateway.yaml`) | Coupled to agentgateway only via `gatewayClassName: agentgateway`. One per data plane. |
| `AgentgatewayParameters` | `agentgateway.dev/v1alpha1` (**vendor-specific**) | this umbrella (`templates/agentgateway/agentgatewayparameters.yaml`) | The only agentgateway-vendor CR the umbrella ships. Strategic-merge overlay over the controller-rendered Deployment + Service; forces Service type ClusterIP by default. |
| `CiliumNetworkPolicy` / `NetworkPolicy` (×4 — controller + data-plane, per flavor) | `cilium.io/v2` or `networking.k8s.io/v1` | this umbrella (`templates/agentgateway/networkpolicy-*.yaml`) | Two pods covered: controller and data-plane. Upstream agentgateway ships no policies. |
| `HTTPRoute` (muster public `/` route) | `gateway.networking.k8s.io/v1` (standard) | this umbrella (`templates/ingress/muster-httproute.yaml`) | Always rendered. Attaches to the public Gateway from `ingress.parentRefs` / `ingress.hostnames` (typically `envoy-gateway-system/giantswarm-default`), NOT to the umbrella's data-plane Gateway. |
| `HTTPRoute` (agentgateway `/mcp` route) | `gateway.networking.k8s.io/v1` (standard) | this umbrella (`templates/agentgateway/httproute.yaml`) | `agentgateway-*` modes only. Reads the same `ingress.parentRefs` / `ingress.hostnames`; the more-specific `/mcp` path steals MCP traffic while OAuth / `.well-known` / DCR stay on muster's `/` route. |
| `BackendTrafficPolicy` (muster `/` route) | `gateway.envoyproxy.io/v1alpha1` (standard Envoy Gateway) | this umbrella (`templates/ingress/muster-backendtrafficpolicy.yaml`) | All modes, gated on `ingress.backendTrafficPolicy.enabled`. Route-scoped over muster's `/` route to preserve muster's `401 … WWW-Authenticate` challenge against the cluster-wide error-pages policy — critical in `muster-direct`, where muster serves `/mcp` directly. |
| `BackendTrafficPolicy` (agentgateway `/mcp` route) | `gateway.envoyproxy.io/v1alpha1` (standard Envoy Gateway) | this umbrella (`templates/agentgateway/backendtrafficpolicy.yaml`) | `agentgateway-*` modes only, gated on `ingress.backendTrafficPolicy.enabled`. Route-scoped over the `/mcp` route to preserve `WWW-Authenticate` and set `requestTimeout: 0s`. |
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

`muster.muster.oauth.server.dex.{issuerUrl,clientId}` and the matching `dex-client-secret` must correspond to a client registered against the cluster's OIDC issuer. Registration is out of scope for this chart; `redirectURI` must equal `<muster.oauth.server.baseUrl>/oauth/callback`.

### Bundled Valkey

`valkey.enabled: true` bundles [giantswarm/valkey-app](https://github.com/giantswarm/valkey-app) (a Giant Swarm wrapper around upstream `valkey-io/valkey-helm`) with persistent storage. Single-pod Deployment behind a Service named `muster-valkey` (via `fullnameOverride`). Muster's storage defaults to `type: valkey` + `url: muster-valkey:6379`, so enabling the bundled chart alongside `oauth.server.enabled: true` is the only flip needed — no `url` override required.

```yaml
valkey:
  enabled: true
  valkey:
    auth:
      usersExistingSecret: muster-oauth  # Secret must carry key `valkey-password`

muster:
  muster:
    oauth:
      server:
        enabled: true
        existingSecret: muster-oauth
        # storage.type: valkey
        # storage.valkey.url: muster-valkey:6379
        # — both inherited from the umbrella defaults.
```

ACL authentication is enabled by default for the `default` user (`~* &* +@all`), with the cleartext password read from `valkey-password` in the operator-supplied Secret. Muster sends `AUTH <password>` against the default user, which is the standard backwards-compatible form.

Operators with an out-of-band Valkey leave `valkey.enabled: false` and override `muster.muster.oauth.server.storage.valkey.url` to point at the external endpoint. See [UPGRADE.md](./UPGRADE.md) for migration notes from a previously-existing standalone Valkey.

### Bundled MCP servers

`mcps.enabled: true` bundles [giantswarm/agentic-platform-mcps](https://github.com/giantswarm/agentic-platform-mcps), which renders the platform's MCP server CRs from one abstract, vendor-neutral `mcpServers` list — muster `MCPServer` CRs by default, and/or agentgateway `AgentgatewayBackend` + `AgentgatewayPolicy` CRs. Like the umbrella's other CRs, these consume CRDs shipped by the companion `agentic-platform-crds` chart (install first); this sub-chart ships **no** CRDs of its own.

```yaml
mcps:
  enabled: true

agentic-platform-mcps:
  mcpServers:
    - cluster: <cluster>
      group: kubernetes
      url: https://mcp.<cluster>.<base-domain>/mcp
```

The `mcps.enabled` toggle deliberately lives in its **own** top-level block rather than under `agentic-platform-mcps.enabled`: the sub-chart's `values.schema.json` is strict (`additionalProperties: false`) and rejects an `enabled` key. Everything under `agentic-platform-mcps.*` is passed through to the sub-chart verbatim — see its [values reference](https://github.com/giantswarm/agentic-platform-mcps) for `defaults`, `identityProviders`, per-entry `auth`, and the `muster` / `agentgateway` rendering toggles. Even when enabled, the chart renders nothing until `mcpServers` is populated.

### Ingress topology

> For the end-to-end authentication story — the request path, OAuth discovery,
> `forward` vs `exchange` token handling, and edge JWT validation / JWKS — see
> [docs/authentication.md](./docs/authentication.md).

The request topology is selected by a single declared selector, `ingress.mode`, with three values:

| `ingress.mode` | Path | Renders |
|---|---|---|
| `muster-direct` (default) | client → muster `/` | muster public `/` route only — **no** agentgateway controller, **no** data-plane `Gateway`, **no** data-plane NetworkPolicies. |
| `agentgateway-muster` | client → agentgateway `/mcp` → muster; everything else → muster | the above **+** agentgateway controller dependency, data-plane `Gateway`, `AgentgatewayParameters`, data-plane NetworkPolicies, `/mcp` `HTTPRoute`, and the optional route-scoped `BackendTrafficPolicy`. |
| `agentgateway-direct` | client → agentgateway `/mcp` → servers | same as `agentgateway-muster`, plus the optional `gateway.jwksEgress` rule. **Not yet supported — install is blocked** (needs a DCR-capable IdP, RFC 7591/8707). |

The mechanism is Gateway-API path-specificity. The umbrella **always** renders muster's public `/` catch-all route (`templates/ingress/muster-httproute.yaml`). In the `agentgateway-*` modes it additionally renders a more-specific `/mcp` route that steals MCP traffic into agentgateway, while OAuth / `.well-known` / DCR stay on muster's `/` route.

Both rendered routes attach to the public Gateway and use the muster hostname(s). `parentRefs` and `hostnames` are now set **once** under `ingress.*` and shared by both routes — they must match the OAuth callback URL from `muster.oauth.mcpClient.publicUrl`. The umbrella's `ingress.parentRefs` guard rejects install in `agentgateway-*` modes until it is set; in `muster-direct` mode neither the agentgateway controller nor any data-plane object is installed.

```yaml
ingress:
  mode: muster-direct          # muster-direct | agentgateway-muster | agentgateway-direct
  parentRefs: []               # ALL modes: the public Gateway both rendered routes attach to
  hostnames: []                # ALL modes: muster public hostname(s)
  httpRoute:
    annotations: {}
    labels: {}
  backendTrafficPolicy:        # agentgateway-* modes only
    enabled: false
    timeout: "0s"
    annotations: {}
    labels: {}
```

In an `agentgateway-*` mode, also set `agentgateway.enabled: true` and the shared `ingress.parentRefs` / `ingress.hostnames`:

```yaml
agentgateway:
  enabled: true

ingress:
  mode: agentgateway-muster
  parentRefs:
    - name: giantswarm-default
      namespace: envoy-gateway-system
      group: gateway.networking.k8s.io
      kind: Gateway
  hostnames:
    - muster.<cluster>.<base-domain>
```

## Observability

All bundled components push OTel traces to the cluster-wide `otlp-gateway.kube-system.svc:4317` (gRPC) by default:

| Component | Mechanism | Default endpoint |
|---|---|---|
| agentgateway data plane | `OTEL_EXPORTER_OTLP_ENDPOINT` + `OTEL_EXPORTER_OTLP_PROTOCOL` env vars via `gateway.parameters.dataPlaneEnv` | `http://otlp-gateway.kube-system.svc:4317` |

Muster does not yet support OTLP push. Its `/metrics` endpoint is scraped via `ServiceMonitor` (`muster.serviceMonitor.enabled: true`).

Override any endpoint per component:

```yaml
gateway:
  parameters:
    dataPlaneEnv:
      - name: OTEL_EXPORTER_OTLP_ENDPOINT
        value: http://tempo-distributor.tempo.svc:4317
      - name: OTEL_EXPORTER_OTLP_PROTOCOL
        value: grpc

```

## Reference workloads (not bundled)

These MCP servers and agent runtimes integrate with the agentic platform but are maintained by other teams and are not bundled in this umbrella.

| Component | Team | Purpose |
|---|---|---|
| [giantswarm/mcp-observability-platform](https://github.com/giantswarm/mcp-observability-platform) | atlas | MCP server exposing Grafana, Mimir, Loki, Tempo, and Alertmanager with OIDC RBAC. Deploy as an `MCPServer` CR behind muster. |
| [giantswarm/mcp-prometheus](https://github.com/giantswarm/mcp-prometheus) | planeteers | MCP server for Prometheus query. |
| [giantswarm/mcp-capi](https://github.com/giantswarm/mcp-capi) | planeteers | MCP server for Cluster API. |
| [giantswarm/mcp-runbooks](https://github.com/giantswarm/mcp-runbooks) | planeteers | MCP server for Giant Swarm runbooks. |
| [giantswarm/mcp-kubernetes](https://github.com/giantswarm/mcp-kubernetes) | bumblebee | MCP server for the Kubernetes API. |

## Private registry overrides

All images default to `gsoci.azurecr.io/giantswarm/*`:

| Image | Source (mirrored by GS retagger) |
|---|---|
| `gsoci.azurecr.io/giantswarm/muster:0.1.197` | `gsoci.azurecr.io/giantswarm/muster` (native GS image) |
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

All CRDs ship in the companion **`agentic-platform-crds`** chart (installed first). This chart (`agentic-platform`) installs **no** CRDs — it only renders CRs that consume them.

| CRDs | Source |
|---|---|
| `gateways.gateway.networking.k8s.io`, `httproutes…`, `gatewayclasses…` | Gateway API upstream — cluster prerequisite (not shipped by either chart) |
| `agentgatewayparameters.agentgateway.dev`, `agentgatewaybackends…`, `agentgatewaypolicies…` | `agentic-platform-crds` chart (vendors the upstream `agentgateway-crds` sub-chart) |
| `mcpservers.muster.giantswarm.io`, `workflows.muster.giantswarm.io` | `agentic-platform-crds` chart (vendors the `muster-crds` sub-chart) |

`helm uninstall agentic-platform` (the workload release) leaves all CRDs and CRs intact — it owns none of them.

**Uninstalling `agentic-platform-crds` is not uniform.** Mind the agentgateway keep-gap:

| CRDs | `helm.sh/resource-policy: keep`? | On `helm uninstall agentic-platform-crds` |
|---|---|---|
| `mcpservers`, `workflows` (`muster.giantswarm.io`) | **Yes** | CRDs and their CRs **survive**. |
| `agentgatewayparameters`, `agentgatewaypolicies`, `agentgatewaybackends` (`agentgateway.dev`) | **No** | CRDs are **deleted** and the delete **cascades to every agentgateway CR cluster-wide**. |

The upstream `agentgateway-crds` chart renders its CRDs without the keep annotation and exposes no knob to inject it, so `agentic-platform-crds` cannot protect them. An upstream change to parameterize the agentgateway CRD annotations is pending (see `CHANGELOG.md`); the keep policy will be set once it lands. Until then, treat uninstalling the CRDs release as destructive for agentgateway CRs.

### Adoption / ownership handoff for pre-existing agentgateway + muster CRDs

If the `0.2.0` `agentic-platform` chart previously installed these CRDs (they were bundled then), or a prior install applied them without Helm metadata, the new `agentic-platform-crds` release refuses to take ownership until you re-annotate them. One-time handoff (run **before** installing `agentic-platform-crds`):

```bash
for crd in $(kubectl get crd -o name | grep -E 'agentgateway\.dev$|muster\.giantswarm\.io$'); do
  kubectl annotate "$crd" \
    meta.helm.sh/release-name=agentic-platform-crds \
    meta.helm.sh/release-namespace=muster --overwrite
  kubectl label "$crd" app.kubernetes.io/managed-by=Helm --overwrite
done
```

See [UPGRADE.md](./UPGRADE.md) for the full `0.2.0 → next` migration.

### Upgrading CRDs

CRDs now migrate with the `agentic-platform-crds` release — `helm upgrade agentic-platform-crds`. An identical-content CRDs bump (re-published unchanged alongside a workload release) is a no-op upgrade.

## Compatibility

Targets Giant Swarm workload clusters running Kubernetes ≥ 1.33 with Cilium and Kyverno. The `kubernetes` NetworkPolicy flavor works on any CNI but is best-effort (no entity selectors, no FQDN egress).

## Credit

- [muster](https://github.com/giantswarm/muster) — Giant Swarm, Apache 2.0.
- [agentgateway](https://github.com/agentgateway/agentgateway) — agentgateway authors, Apache 2.0.

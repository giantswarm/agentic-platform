[![CircleCI](https://dl.circleci.com/status-badge/img/gh/giantswarm/agentic-platform/tree/main.svg?style=svg)](https://dl.circleci.com/status-badge/redirect/gh/giantswarm/agentic-platform/tree/main)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/giantswarm/agentic-platform/badge)](https://securityscorecards.dev/viewer/?uri=github.com/giantswarm/agentic-platform)

# agentic-platform

The agentic platform is Giant Swarm's MCP gateway deploy unit. It ships [muster](https://github.com/giantswarm/muster) (MCP gateway / aggregator) and [agentgateway](https://github.com/agentgateway/agentgateway) (MCP data plane) together, plus the `Gateway`, `AgentgatewayParameters`, and `CiliumNetworkPolicy` resources that wire them up.

Owner: team-bumblebee.

## Prerequisites

- Kubernetes ≥ 1.33 on the install target.
- Gateway API v1 CRDs (`gateways.gateway.networking.k8s.io`, `httproutes.gateway.networking.k8s.io`, `gatewayclasses.gateway.networking.k8s.io`) installed cluster-wide. The agentic platform does **not** install them.
- `agentgateway-crds` chart installed (provides `AgentgatewayParameters`, `AgentgatewayBackend`, `AgentgatewayPolicy`, `Gateway` extensions). Not bundled — see [CRD lifecycle](#crd-lifecycle).
- `muster-crds` chart installed (provides `MCPServer`, `Workflow`). Not bundled — see [CRD lifecycle](#crd-lifecycle).
- A Gateway API `GatewayClass` CR named `agentgateway` is a prerequisite for the `Gateway` this chart renders. The bundled upstream `agentgateway` controller subchart creates that `GatewayClass` on install, so a default install satisfies the prereq. Operators who manage the controller out-of-band (cluster-scoped install in `agentgateway-system`, for example) must ensure the `GatewayClass` exists separately. Verify with `kubectl get gatewayclass agentgateway -o yaml` — `status.conditions[type=Accepted]` must be `True` before this chart's `Gateway` will program.
- Cilium CNI if `networkPolicy.flavor: cilium` (default). Set `networkPolicy.enabled: false` on non-Cilium clusters.

## Installing

The agentic platform does NOT bundle CRDs. Install / upgrade the two CRD
charts FIRST, in order, then install the agentic platform.

### Giant Swarm App platform

Three App CRs with `spec.dependsOn` to encode ordering:

```yaml
apiVersion: application.giantswarm.io/v1alpha1
kind: App
metadata:
  name: agentgateway-crds
  namespace: <org-namespace>
spec:
  catalog: giantswarm
  name: agentgateway-crds
  namespace: muster
  version: v1.2.1
---
apiVersion: application.giantswarm.io/v1alpha1
kind: App
metadata:
  name: muster-crds
  namespace: <org-namespace>
spec:
  catalog: giantswarm
  name: muster-crds
  namespace: muster
  version: <muster-crds-version>
---
apiVersion: application.giantswarm.io/v1alpha1
kind: App
metadata:
  name: agentic-platform
  namespace: <org-namespace>
spec:
  catalog: giantswarm
  name: agentic-platform
  namespace: muster
  version: <agentic-platform-version>
  dependsOn:
    - name: agentgateway-crds
      namespace: <org-namespace>
    - name: muster-crds
      namespace: <org-namespace>
```

Or via Flux `OCIRepository` + `HelmRelease` for each chart — `HelmRelease`
supports `spec.dependsOn` with the same semantics.

### Raw Helm

```bash
# 1. Agentgateway CRDs (AgentgatewayParameters, AgentgatewayBackend, AgentgatewayPolicy).
helm install agentgateway-crds \
  oci://cr.agentgateway.dev/charts/agentgateway-crds \
  --version v1.2.1 \
  --namespace muster --create-namespace

# 2. Muster CRDs (MCPServer, Workflow).
helm install muster-crds \
  oci://gsoci.azurecr.io/charts/giantswarm/muster-crds \
  --version <muster-crds-version> \
  --namespace muster

# 3. The agentic platform itself.
helm install agentic-platform \
  oci://gsoci.azurecr.io/charts/giantswarm/agentic-platform \
  --version <chart-version> \
  --namespace muster
```

The two CRD charts can be upgraded independently of the agentic platform.
See [CRD lifecycle](#crd-lifecycle) for the upgrade procedure.

## Configuration

Top-level values surfaced by the agentic platform:

| Key | Default | Purpose |
|---|---|---|
| `global.registry` | `gsoci.azurecr.io` | Default container image registry. |
| `gateway.name` | `agentgateway` | `Gateway` resource name; HTTPRoute parentRefs use this. |
| `gateway.gatewayClassName` | `agentgateway` | The `GatewayClass` the data plane attaches to. |
| `gateway.listeners` | `[{name: http, port: 8080, protocol: HTTP}]` | Listener spec passed verbatim. |
| `gateway.parameters.enabled` | `true` | Render the `AgentgatewayParameters` overlay. |
| `gateway.parameters.{pod,container}SecurityContext` | restricted-PSS compatible | Injected into the data-plane Deployment via strategic merge patch. |
| `networkPolicy.enabled` / `.flavor` | `true` / `cilium` | Render the agentic-platform `CiliumNetworkPolicy`. |
| `muster.*` | passes through to the muster subchart | See [muster chart README](https://github.com/giantswarm/muster/blob/main/helm/muster/README.md). |
| `agentgateway.*` | passes through to the upstream agentgateway chart | See [agentgateway docs](https://agentgateway.dev). |

Full schema: [`helm/agentic-platform/values.schema.json`](./helm/agentic-platform/values.schema.json).

### OAuth secrets

The umbrella does NOT auto-generate OAuth credentials. Two options:

1. **Inline values.** Set the Dex client secret and registration token directly in `muster.muster.oauth.server.*` and let the muster sub-chart render a Secret. Suitable for GitOps repos that already encrypt values (sops, Sealed Secrets, etc.).
2. **`existingSecret`.** Pre-create a Secret with the muster-expected keys and point the chart at it:

   ```bash
   kubectl create secret generic muster-oauth \
     --namespace muster \
     --from-literal=dex-client-secret=<value> \
     --from-literal=registration-token=$(openssl rand -hex 32) \
     --from-literal=oauth-encryption-key=$(openssl rand -base64 32) \
     --from-literal=valkey-password=<value>
   ```

   ```yaml
   muster:
     muster:
       oauth:
         server:
           existingSecret: muster-oauth
   ```

Random auto-generation via Helm `lookup` is intentionally avoided — every `helm upgrade` would regenerate the values and invalidate every issued token. See [#4](https://github.com/giantswarm/agentic-platform/issues/4).

### Dex / OIDC client registration

`muster.muster.oauth.server.dex.{issuerUrl,clientId}` and the matching `dex-client-secret` must correspond to a client registered against the cluster's Dex (or another OIDC issuer). The agentic platform does NOT register the client — that's the IdP operator's job. On Giant Swarm workload clusters running `dex-operator`, register via a `DexIdentityProvider` CR alongside the umbrella App CR:

```yaml
apiVersion: dex.giantswarm.io/v1alpha1
kind: DexIdentityProvider
metadata:
  name: muster
  namespace: <dex-operator-namespace>
spec:
  type: github           # or "ldap", "oidc", "saml" depending on the cluster's federation
  name: GitHub
  connectorConfig:
    # provider-specific config
    clientID: <github-app-id>
    clientSecret: <github-app-secret>
    redirectURI: https://muster.<cluster>.<base-domain>/oauth/callback
```

The `redirectURI` must equal `<muster.oauth.server.baseUrl>/oauth/callback`. For raw Dex (no `dex-operator`), edit the Dex `ConfigMap` to add the staticClients entry with the same `id` / `secret` / `redirectURIs`.

### Bundled Valkey

Set `valkey.enabled: true` to include a Valkey instance (bitnami chart, persistent storage on by default) for muster's OAuth session storage. The chart pins `fullnameOverride: muster-valkey` so the primary Service resolves at `muster-valkey-primary.<namespace>.svc:6379` — match muster's expectation by setting:

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

Operators with an out-of-band Valkey (shared across namespaces, managed by another release) should leave `valkey.enabled: false` and configure `muster.muster.oauth.server.storage.valkey.*` directly.

### Public HTTPRoute (required for OAuth)

The umbrella renders a Gateway for the **data plane** only — that Gateway is not exposed publicly and is not the right parent for the muster control-plane HTTPRoute. Muster's HTTPRoute must attach to the cluster's public Gateway (typically the envoy-gateway-system one) with hostnames that match the OAuth callback URL operators advertise via `muster.oauth.mcpClient.publicUrl`.

The muster sub-chart's `parentRefs is required when gatewayAPI.enabled is true` guard blocks install until both `parentRefs` and `hostnames` are set explicitly:

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

The mirror must serve these paths verbatim: `giantswarm/muster`, `giantswarm/agentgateway-controller`, `giantswarm/agentgateway`.

## Security

The agentgateway data-plane pod template is rendered at runtime by the controller, not by Helm. To inject restricted-PSS-compatible `securityContext` fields, the agentic platform ships an `AgentgatewayParameters` resource referenced from `Gateway.spec.infrastructure.parametersRef`. The controller applies it as a strategic merge patch over the generated Deployment.

The data-plane pod template hardcodes `sysctls: [net.ipv4.ip_unprivileged_port_start=0]`. This is a **namespaced-safe** sysctl (does not require `allowedUnsafeSysctls` on the kubelet). On clusters with built-in Pod Security Admission `restricted` enforced, the sysctl will be rejected — label the install namespace with `pod-security.kubernetes.io/enforce: baseline` (or allowlist the sysctl in Kyverno's `restrict-sysctls` policy as Giant Swarm workload clusters already do).

## CRD lifecycle

The agentic platform does NOT install any CRDs. They are owned by three
sibling releases whose lifecycle is decoupled from the data plane:

| CRDs | Chart | Catalog |
|---|---|---|
| `gateways.gateway.networking.k8s.io`, `httproutes…`, `gatewayclasses…` | Gateway API upstream | cluster prerequisite |
| `agentgatewayparameters.agentgateway.dev`, `agentgatewaybackends…`, `agentgatewaypolicies…` | `agentgateway-crds` | `oci://cr.agentgateway.dev/charts/agentgateway-crds` |
| `mcpservers.muster.giantswarm.io`, `workflows.muster.giantswarm.io` | `muster-crds` | `oci://gsoci.azurecr.io/charts/giantswarm/muster-crds` |

Why separate releases (mirrors the kgateway / cert-manager pattern):

- Helm 3 only special-cases the top-level chart's `crds/` directory.
  Sub-chart `crds/` directories are silently ignored, so bundling CRDs
  through a sub-chart leaks the CRD lifecycle into every umbrella
  `helm upgrade`.
- Upgrading CRDs becomes an explicit, ordered step instead of a side
  effect — schema-breaking changes can ratchet through the Kubernetes
  deprecation policy without touching the data plane.
- `helm uninstall agentic-platform` no longer cascade-deletes CRDs and
  the CRs that depend on them.

### Adoption on clusters that already have the CRDs

If a previous (broken) topology installed the CRDs through the
`agentgateway-crds` sub-chart or the muster sub-chart's `templates/crds.yaml`,
the new releases will refuse to take ownership. One-time adoption:

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

See [`helm/muster-crds/UPGRADE.md`](https://github.com/giantswarm/muster/blob/main/helm/muster-crds/UPGRADE.md)
for the schema-change ratchet. For `agentgateway-crds`, follow upstream
release notes.

## Compatibility

This chart targets Giant Swarm workload clusters running Kubernetes ≥ 1.33 with Cilium and Kyverno.

## Credit

- [muster](https://github.com/giantswarm/muster) — Giant Swarm, Apache 2.0.
- [agentgateway](https://github.com/agentgateway/agentgateway) — agentgateway authors, Apache 2.0.

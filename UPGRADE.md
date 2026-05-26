# Upgrading agentic-platform

Operator action required between releases. CHANGELOG.md captures the diff; UPGRADE.md captures what an operator has to *do*.

## 0.0.0 → 0.1.0 (first stable release — pending)

### `giantswarm/klaus-gateway` is now bundled (default on)

`"klaus-gateway".enabled` defaults to `true`. If a cluster already runs a standalone `HelmRelease` for `giantswarm/klaus-gateway`, take one of these actions before upgrading:

```yaml
# Option A: disable the bundled sub-chart and keep the standalone release as-is.
"klaus-gateway":
  enabled: false
```

```bash
# Option B: uninstall the standalone release, then upgrade. The umbrella's
# bundled sub-chart takes over management of the Deployment and ServiceMonitor.
helm uninstall <standalone-release-name> -n <namespace>
helm upgrade agentic-platform ...
```

After option B, the bundled `ChannelRoute` CRD (`channelroutes.routing.giantswarm.io`) is now managed by this release. If you previously managed it out-of-band, adopt it or set `"klaus-gateway".crd.install: false`.

### OTel defaults added for agentgateway data plane and Klaus-gateway

`gateway.parameters.dataPlaneEnv` now defaults to:

```yaml
- name: OTEL_EXPORTER_OTLP_ENDPOINT
  value: http://otlp-gateway.kube-system.svc:4317
- name: OTEL_EXPORTER_OTLP_PROTOCOL
  value: grpc
```

This requires an `otlp-gateway` Service in `kube-system` (provided by the Giant Swarm observability platform). On clusters without it, the agentgateway data-plane logs connection errors to the exporter but starts normally. Disable with:

```yaml
gateway:
  parameters:
    dataPlaneEnv: []
```

### Bundled Valkey + OAuth server are ON by default

`valkey.enabled` and `muster.muster.oauth.server.enabled` both default to `true`. Operators must supply per-cluster fields up-front or the muster sub-chart's fail-guards reject install:

| Field | Why |
|---|---|
| `muster.muster.oauth.server.baseUrl` | OAuth issuer URL (HTTPS, public muster hostname). |
| `muster.muster.oauth.server.dex.issuerUrl` | Dex issuer URL on this cluster. |
| `muster.muster.oauth.server.dex.clientId` | OAuth client pre-registered in Dex. |
| `muster.muster.oauth.server.existingSecret` | Secret carrying `dex-client-secret`, `registration-token`, `oauth-encryption-key`, `valkey-password`. |
| `valkey.valkey.auth.usersExistingSecret` | Same Secret (key `valkey-password`) — drives ACL auth on the bundled Valkey. Conventionally the same name as the muster OAuth Secret. |

For dev installs that don't need OAuth: set `muster.muster.oauth.server.enabled: false`, `muster.muster.oauth.server.storage.type: memory`, and (optionally) `valkey.enabled: false`.

### muster 0.1.193 → 0.1.197

`muster.ciliumNetworkPolicy.*` is removed. Migrate:

```yaml
muster:
  networkPolicy:
    enabled: true            # was: ciliumNetworkPolicy.enabled
    flavor: cilium           # new — mirrors umbrella's networkPolicy.flavor
    cilium:
      allowClusterIngress: true  # was: ciliumNetworkPolicy.allowClusterIngress
```

The muster sub-chart now also ships a `kubernetes` flavor (vanilla `networking.k8s.io/v1 NetworkPolicy`) with the same CIDR replacements as the umbrella (`apiServerCIDR`, `clusterCIDR`, `worldExcludedCIDRs`). Muster's CiliumNetworkPolicy egress now covers the agentgateway data-plane on 8080 in the release namespace (upstream-proxy path) in addition to the existing Valkey egress on 6379.

### agentgateway-crds is a cluster prerequisite

Install `agentgateway-crds` before the agentic-platform release. Upstream `agentgateway` ships the controller and CRDs as separate charts at `oci://cr.agentgateway.dev/charts/` — we have no choice but to install both. Muster's CRDs continue to ship inside the umbrella via the muster sub-chart's `templates/crds.yaml`.

```
helm install agentgateway-crds \
  oci://cr.agentgateway.dev/charts/agentgateway-crds --version v1.2.1 \
  -n muster --create-namespace
```

#### Adopting pre-existing agentgateway CRDs

If a previous install applied agentgateway CRDs without Helm metadata, the new `agentgateway-crds` release refuses to take ownership. One-time adoption:

```bash
for crd in $(kubectl get crd -o name | grep -E 'agentgateway\.dev$'); do
  kubectl annotate "$crd" \
    meta.helm.sh/release-name=agentgateway-crds \
    meta.helm.sh/release-namespace=muster --overwrite
  kubectl label "$crd" app.kubernetes.io/managed-by=Helm --overwrite
done
```

### Public HTTPRoute is now operator-mandated

`muster.gatewayAPI.httpRoute.parentRefs` and `.hostnames` no longer default to the umbrella's internal `agentgateway` Gateway — that Gateway is for the data plane and is not exposed publicly. The muster sub-chart's fail-guard rejects install until both fields are set:

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

### Data-plane Service forced to ClusterIP

The agentgateway controller hardcodes the data-plane Service to `type: LoadBalancer`. The umbrella overlays `spec.service.type: ClusterIP` via `AgentgatewayParameters` so the data plane stays internal — envoy-gateway-system fronts public traffic. Override with `gateway.parameters.serviceType: LoadBalancer` if running on a cluster without a front Gateway.

### NetworkPolicy flavors

`networkPolicy.flavor` now accepts `cilium` (default) or `kubernetes`. The previous `none` value is removed — opt out via `networkPolicy.enabled: false`. The `kubernetes` flavor renders vanilla `networking.k8s.io/v1 NetworkPolicy` but is best-effort: no entity selectors (`cluster`, `world`, `kube-apiserver` become CIDR ranges via `networkPolicy.kubernetes.{apiServerCIDR,worldExcludedCIDRs}`), no FQDN egress (`additionalEgressFQDNs` is ignored).

**Cross-subchart flavor switch.** Muster 0.1.197 ships the same `networkPolicy.{enabled,flavor,cilium.*,kubernetes.*}` shape as the umbrella, so the flavor switch is consistent across both. When selecting the `kubernetes` flavor (or running on a non-Cilium cluster), set:

```yaml
networkPolicy:
  flavor: kubernetes
muster:
  networkPolicy:
    flavor: kubernetes
valkey:
  ciliumNetworkPolicy:
    enabled: false   # giantswarm/valkey-app has no kubernetes-flavor CNP yet
```

Previous `muster.ciliumNetworkPolicy.{enabled,allowClusterIngress}` keys are gone — migrate to `muster.networkPolicy.{enabled,flavor,cilium.allowClusterIngress}`.

### Controller CiliumNetworkPolicy added

The umbrella now ships a separate policy for the agentgateway **controller pod** in addition to the data-plane pod. Previously the controller was unprotected (upstream agentgateway chart ships no policies). Data-plane selector switched to the Gateway-API standard label `gateway.networking.k8s.io/gateway-name=<gateway.name>`; controller selector matches the controller's `app.kubernetes.io/instance=<release>` triple.

### Bundled Valkey — giantswarm/valkey-app, ACL auth, default-on for muster

`valkey.enabled: true` now bundles [giantswarm/valkey-app](https://github.com/giantswarm/valkey-app) (wraps upstream `valkey-io/valkey-helm`) instead of `bitnami/valkey`. Differences operators must adopt:

- **Service name.** Writable endpoint is `muster-valkey.<namespace>.svc:6379` (single Deployment + Service — no primary/replica split, no `-primary` suffix).
- **Default muster wiring.** `muster.muster.oauth.server.storage.type` defaults to `valkey` and `storage.valkey.url` defaults to `muster-valkey:6379` at the umbrella level. Enabling OAuth + the bundled valkey requires no further override. Set `storage.type: memory` for dev, or override the `url:` for an out-of-band Valkey.
- **Auth model.** ACL-based, not flat-password. The bundled chart provisions a `default` user with `~* &* +@all` and reads the cleartext password from the `valkey-password` key of `valkey.valkey.auth.usersExistingSecret`. Muster sends `AUTH <password>` against the default user — standard backwards-compatible form.
- **Values shape.** Wrapper exposes upstream values under `valkey.valkey.*`:

  | Old (bitnami) | New (valkey-app) |
  |---|---|
  | `valkey.fullnameOverride: muster-valkey` | `valkey.valkey.fullnameOverride: muster-valkey` |
  | `valkey.image.tag: "9.0.4"` | `valkey.valkey.image.tag` (defaults to chart appVersion 8.1.4) |
  | `valkey.auth.existingSecret: <name>` | `valkey.valkey.auth.usersExistingSecret: <name>` |
  | `valkey.primary.persistence.{enabled,size}` | `valkey.valkey.dataStorage.{enabled,requestedSize}` |
  | `valkey.primary.resources` | `valkey.valkey.resources` |

- **Migration from bitnami.** Re-pointing `storage.valkey.url` from `muster-valkey-primary.<ns>.svc:6379` to `muster-valkey.<ns>.svc:6379` is sufficient at the URL layer; the previous bitnami StatefulSet's PVC is not consumed by the new Deployment-backed PVC (different name). Treat session storage as ephemeral when cutting over.

### `bootstrap.oauth.*` removed

The Helm `lookup`-based OAuth bootstrap Secret has been removed. Three Secret-injection paths remain: inline values, `existingSecret`, and the new umbrella-level `extraObjects: []`. See README "OAuth secrets".

### `extraObjects` added

New top-level umbrella key. Each entry is rendered through `tpl` and emitted alongside the chart. Useful for shipping the muster OAuth Secret manifest in the same Helm release.

### `gateway.parameters.dataPlane{Env,Volumes,VolumeMounts}` (unchanged from earlier draft)

Strategic-merge knobs on the AgentgatewayParameters template. Use when pushing OTel env vars or mounting cert-manager-issued CA bundles for `controller.xds.mode: tls` into the dynamically-rendered data-plane container.

## Template

```
## <previous-version> → <new-version>

### <Short title of breaking change>

<What changed, why, what operators must do. Always cite the value /
template / file involved so reviewers can grep for the change.>
```

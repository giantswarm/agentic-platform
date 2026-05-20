# Upgrading agentic-platform

Operator action required between releases. CHANGELOG.md captures the diff; UPGRADE.md captures what an operator has to *do*.

## 0.0.0 → 0.1.0 (first stable release — pending)

### CRD lifecycle — agentgateway-crds and muster-crds shipped separately

The agentic platform no longer bundles `agentgateway-crds` and no longer relies on the muster sub-chart's `templates/crds.yaml`. Install / upgrade the two CRD charts BEFORE the agentic-platform release. Encode ordering via Flux `HelmRelease.spec.dependsOn` (see README), or follow the raw-helm sequence:

```
helm install agentgateway-crds \
  oci://cr.agentgateway.dev/charts/agentgateway-crds --version v1.2.1 \
  -n muster --create-namespace

helm install muster-crds \
  oci://gsoci.azurecr.io/charts/giantswarm/muster-crds \
  --version <muster-crds-version> -n muster
```

#### Adopting CRDs from a previous broken topology

If a previous install of the agentic-platform created the CRDs via the sub-chart paths, the new sibling releases refuse to take ownership. One-time adoption:

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

**Cross-subchart caveat:** the umbrella's `networkPolicy.flavor` only governs the agentgateway policies it owns. The muster sub-chart's `ciliumNetworkPolicy.enabled` is independent and defaults to `true` in the umbrella values. When selecting the `kubernetes` flavor (or running on a non-Cilium cluster), also set:

```yaml
muster:
  ciliumNetworkPolicy:
    enabled: false
```

Tracked for muster-side alignment — long-term the muster chart will gain a `networkPolicy.flavor` switch matching the umbrella's.

### Controller CiliumNetworkPolicy added

The umbrella now ships a separate policy for the agentgateway **controller pod** in addition to the data-plane pod. Previously the controller was unprotected (upstream agentgateway chart ships no policies). Data-plane selector switched to the Gateway-API standard label `gateway.networking.k8s.io/gateway-name=<gateway.name>`; controller selector matches the controller's `app.kubernetes.io/instance=<release>` triple.

### Bundled bitnami/valkey — `-primary` suffix on the writable Service

`valkey.enabled: true` exposes the writable endpoint at `muster-valkey-primary.<namespace>.svc:6379`. If migrating from a previously-existing standalone Valkey reachable at `muster-valkey.muster.svc:6379`, update the URL:

```yaml
muster:
  muster:
    oauth:
      server:
        storage:
          valkey:
            url: muster-valkey-primary.muster.svc:6379  # was: muster-valkey.muster.svc:6379
```

### `valkey-password` Secret key

If reusing an existing `muster-valkey-auth` Secret with the key `default` (the bitnami default before `auth.usePasswordFiles`), set:

```yaml
muster:
  muster:
    oauth:
      server:
        storage:
          valkey:
            secretKeyPassword: default
```

The muster chart defaults this to `valkey-password`; the bundled valkey expectation matches.

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

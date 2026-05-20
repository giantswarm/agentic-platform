# Upgrading agentic-platform

Use this document as the index of breaking changes and operator action
required between releases of the agentic-platform umbrella. Add a new
`## <version>` section per release; CHANGELOG.md captures the diff,
UPGRADE.md captures what an operator has to *do*.

## 0.0.0 → 0.1.0 (first stable release — pending)

### CRD lifecycle — agentgateway-crds and muster-crds shipped separately

The agentic platform no longer bundles `agentgateway-crds` and no longer
relies on the muster sub-chart's `templates/crds.yaml`. Helm 3 only
special-cases the top-level chart's `crds/` directory; sub-chart `crds/`
dirs are silently ignored, which made the umbrella unable to install
first-try on a fresh cluster and made every `helm upgrade` an implicit
CRD migration.

CRDs now ship in dedicated sibling charts. Install / upgrade them BEFORE
the agentic-platform release:

```
helm install agentgateway-crds \
  oci://cr.agentgateway.dev/charts/agentgateway-crds --version v1.2.1 \
  -n muster --create-namespace

helm install muster-crds \
  oci://gsoci.azurecr.io/charts/giantswarm/muster-crds \
  --version <muster-crds-version> -n muster
```

On Giant Swarm App platform, encode the ordering with `spec.dependsOn`
on the `agentic-platform` App CR — see [README.md](./README.md).

#### Adopting CRDs from a previous broken topology

If a previous install of the agentic-platform created the CRDs via the
sub-chart paths, the new sibling releases refuse to take ownership.
One-time adoption:

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

`muster.gatewayAPI.httpRoute.parentRefs` and `.hostnames` no longer
default to the umbrella's internal `agentgateway` Gateway — that Gateway
is for the data plane and is not exposed publicly. The muster sub-chart's
fail-guard rejects install until both fields are set:

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

### `muster.crds.install` deprecated, no-op

The umbrella pins `muster.crds.install: false` (default in the muster
chart since v0.1.193+). The toggle is scheduled for removal in muster
chart v0.2.0.

### Bundled bitnami/valkey (opt-in)

`valkey.enabled: true` adds a bitnami Valkey instance with persistent
storage. `fullnameOverride: muster-valkey` pins the primary Service so
muster's URL convention resolves without a cross-subchart values
rewrite — see README "Bundled Valkey".

### `CiliumNetworkPolicy` egress broadened

The data-plane CNP gained DNS for `coredns` and `k8s-dns-node-cache`
(ports 53 + 1053), `world` egress on port 80, `cluster` egress on 80/443
for in-cluster ingress (Dex / OIDC / MCPServers), and endpoint egress
to `app.kubernetes.io/name=muster:8090`. `muster.ciliumNetworkPolicy.allowClusterIngress`
default flipped to `true`.

If the cluster runs a different CNI flavor, set `networkPolicy.flavor: none`.

### `gateway.parameters.dataPlane{Env,Volumes,VolumeMounts}` added

New strategic-merge knobs on the AgentgatewayParameters template. No
default behaviour change; consume them when you need to push OTel env
vars or mount cert-manager-issued CA bundles for `controller.xds.mode: tls`
into the dynamically-rendered data-plane container.

## Template

```
## <previous-version> → <new-version>

### <Short title of breaking change>

<What changed, why, what operators must do. Always cite the value /
template / file involved so reviewers can grep for the change.>
```

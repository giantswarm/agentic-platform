# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `agentgateway-crds` bundled as a conditional sub-chart (`condition: agentgateway-crds.enabled`, default `true`) so the umbrella is self-contained. The chart now ships the `AgentgatewayParameters` / `AgentgatewayPolicy` / `AgentgatewayBackend` CRDs alongside the `AgentgatewayParameters` CR it renders; Helm applies CRDs ahead of the CR via install ordering. Disable on clusters that manage these CRDs out of band.
- Agentgateway data-plane OTel env defaults: `OTEL_EXPORTER_OTLP_ENDPOINT=http://otlp-gateway.kube-system.svc:4317` and `OTEL_EXPORTER_OTLP_PROTOCOL=grpc` added to `gateway.parameters.dataPlaneEnv`. Override to point at a different backend.
- `muster.serviceMonitor.enabled: true` default. OTel push to otlp-gateway is not yet supported by muster; ServiceMonitor is the primary observability path until muster gains an `otlpEndpoint` knob.
- `ci/test-full-stack-values.yaml` CI values file satisfying all fail-guards for a complete `helm template` render (OAuth off, valkey off, parentRefs stubbed).

### Changed

- `agentgateway-crds` is no longer a cluster prerequisite (now bundled). Muster's CRDs continue to ship via the muster sub-chart. **Caveat:** the upstream `agentgateway-crds` CRDs are not yet annotated `helm.sh/resource-policy: keep`, so uninstalling the release deletes them and cascades to all agentgateway CRs cluster-wide. An upstream change to parameterize the CRD annotations is pending; the `keep` annotation will be added here once it lands.

## [0.1.0] - 2026-05-26

### Added

- Initial agentic-platform chart bundling `muster` 0.1.197 and `agentgateway` v1.2.1.
- `Gateway` (name `agentgateway`) and `AgentgatewayParameters` overlay injecting restricted-PSS `securityContext` on the controller-rendered data-plane pod.
- `gateway.parameters.serviceType` (default `ClusterIP`) overlays `AgentgatewayParameters.spec.service.type` so the data-plane Service stays internal; the controller hardcodes `LoadBalancer`.
- `gateway.parameters.dataPlaneEnv`, `dataPlaneVolumes`, `dataPlaneVolumeMounts` strategic-merge lists on the AgentgatewayParameters overlay.
- `CiliumNetworkPolicy` for the agentgateway **controller pod** in addition to the data-plane pod (upstream agentgateway chart ships no policies).
- `networking.k8s.io/v1 NetworkPolicy` rendering when `networkPolicy.flavor: kubernetes` — best-effort (no entity selectors, no FQDN egress).
- `networkPolicy.kubernetes.{apiServerCIDR,worldExcludedCIDRs}` for the `kubernetes` flavor.
- Top-level `extraObjects: []` rendering arbitrary manifests through `tpl` alongside the chart.
- `values.schema.json` covering top-level keys with a cross-field combo check (muster valkey storage requires `valkey.enabled` or an explicit URL).
- `UPGRADE.md` documenting the breaking changes for the first stable release.

### Changed

- CRD lifecycle: `agentgateway-crds` is a cluster prerequisite (upstream agentgateway ships controller + CRDs as separate charts). Muster's CRDs continue to ship inside the umbrella via the muster sub-chart's `templates/crds.yaml`.
- Data-plane policy selector switched to the Gateway-API standard label `gateway.networking.k8s.io/gateway-name=<gateway.name>` (was `app.kubernetes.io/name=agentgateway`, which matched both the controller and the data plane).
- Controller policy selector uses the agentgateway sub-chart's selector triple (`agentgateway: agentgateway` + `app.kubernetes.io/name=agentgateway` + `app.kubernetes.io/instance=<release>`).
- Data-plane CNP gains xDS egress to the controller on TCP 9978; controller CNP gains xDS ingress from data-plane pods.
- `CiliumNetworkPolicy` egress covers `kube-dns`, `coredns`, `k8s-dns-node-cache` on 53 + 1053 (UDP + TCP); world 80/443; cluster 80/443 for in-cluster ingress (Dex / MCPServers); muster on 8090.
- Muster sub-chart's NetworkPolicy values migrate from `ciliumNetworkPolicy.*` to `networkPolicy.{enabled,flavor,cilium.allowClusterIngress,kubernetes.*}` (muster 0.1.197). Umbrella overrides `enabled: true`, `flavor: cilium`, `cilium.allowClusterIngress: true`.
- `valkey.enabled` and `muster.muster.oauth.server.enabled` default to `true`. Operators must provide `oauth.server.baseUrl`, `oauth.server.dex.{issuerUrl,clientId}`, `oauth.server.existingSecret`, and `valkey.valkey.auth.usersExistingSecret` — muster's template-time fail-guards reject install otherwise.
- `muster.gatewayAPI.httpRoute.parentRefs` / `.hostnames` no longer default to the data-plane Gateway. Muster's HTTPRoute must attach to the cluster's public Gateway (typically `envoy-gateway-system/giantswarm-default`); the muster fail-guard enforces this.
- Bundled `giantswarm/valkey-app` 0.1.2 as a conditional sub-chart (`condition: valkey.enabled`). Single Deployment + PVC; Service at `muster-valkey.<namespace>.svc:6379`. ACL-based auth: a `default` user with full permissions reads its password from `valkey-password` in `valkey.valkey.auth.usersExistingSecret`.
- Muster wired to the bundled valkey by default: `muster.muster.oauth.server.storage.type=valkey` and `storage.valkey.url=muster-valkey:6379`. Inert while `oauth.server.enabled: false`; kicks in the moment OAuth is enabled.
- `networkPolicy.flavor` enum changed from `cilium | none` to `cilium | kubernetes`. Opt out via `networkPolicy.enabled: false`.
- README is now Flux HelmRelease-first (no Giant Swarm App platform). Adds a "Gateway API CR ownership" section clarifying that only `AgentgatewayParameters` is vendor-specific to agentgateway.
- Templates grouped under `templates/agentgateway/` (Gateway, AgentgatewayParameters, four NetworkPolicy variants).
- `Chart.yaml` description reflects the runtime contract (muster + agentgateway + opt-in Valkey; CRDs as cluster prerequisite). `appVersion` stays at the umbrella's own `0.1.0`.

### Removed

- `bootstrap.oauth.*` values and the `templates/oauth-bootstrap-secret.yaml` Helm `lookup`-based Secret generator. Use `extraObjects` to ship the Secret in the same release, or pre-create it out of band and reference via `muster.muster.oauth.server.existingSecret`.

[Unreleased]: https://github.com/giantswarm/agentic-platform/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/giantswarm/agentic-platform/releases/tag/v0.1.0

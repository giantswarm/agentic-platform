# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `kagent-crds` (`v0.9.4`, `oci://ghcr.io/kagent-dev/kagent/helm`) bundled as a sub-chart. Installs the kagent CRDs (`Agent`, `AgentHarness`, `ModelConfig`, `MCPServer`, `RemoteMCPServer`, `Memory`, `ToolServer`, `SandboxAgent`). Must be installed before the `agentic-platform` chart when `kagent.enabled: true`. Note: upstream does not mark these CRDs `helm.sh/resource-policy: keep`; `helm uninstall agentic-platform-crds` will remove them and cascade to all kagent CRs.
- `kagent` (`v0.9.4`, `oci://ghcr.io/kagent-dev/kagent/helm`) bundled as a conditional sub-chart (`kagent.enabled`, default `false`). All kagent resources land in `kagent.namespaceOverride` (default `kagent`) so they stay separate from the umbrella's release namespace. The `kagent-crds` chart is added to `agentic-platform-crds` as a prerequisite. Enabling kagent requires `agentic-platform-crds` to be installed first.
- `postgres` block: opt-in CloudNativePG `Cluster` CR (`postgres.enabled`, default `false`) provisioning the kagent application database in a named `kagent` schema (not `public`). Supports pgvector via `postInitTemplateSQL` (any CNPG version, bundled image) or the ImageVolume approach (`postgres.vector.extensionImage.reference`, CNPG 1.29+/PG18). The CNPG operator and its CRDs remain a cluster-level prerequisite. An optional Klaus sessions database (`postgres.sessionsDatabase.enabled`, default `false`) is templated but left off pending the core-runtime persistence decision.
- `templates/namespace.yaml`: renders the `kagent` `Namespace` when `kagent.namespaceOverride` differs from the release namespace, so fresh installs do not require manual namespace pre-creation.
- `templates/kagent/controller-route.yaml`: opt-in `AgentgatewayBackend` + `HTTPRoute` (`kagent.controllerRoute.enabled`) exposing the kagent controller API through agentgateway with JWT validation.
- `templates/kagent/netpol.yaml`: cross-namespace network policies for kagent (cilium and kubernetes flavors, gated on `networkPolicy.flavor`). Cilium: egress from agentgateway data-plane to kagent controller (port 8083) + ingress policy in the kagent namespace. Kubernetes: `NetworkPolicy` restricting kagent controller ingress to the release and kagent namespaces, preventing direct access that would bypass agentgateway JWT validation.
- `templates/kagent/ui-httproute.yaml`: opt-in HTTPRoute (`kagent.uiRoute.enabled`) exposing the kagent UI on the public Gateway. When `oauth2-proxy.enabled: true` routes through oauth2-proxy (port 4180); otherwise routes directly to the UI (dev only). Placed in the kagent namespace to avoid cross-namespace backend refs.
- `ci/test-postgres-values.yaml`: CI values file exercising the kagent+postgres path through `helm template`/lint.
- `ci/test-kagent-routing-values.yaml`: CI values file exercising controllerRoute + uiRoute + oauth2-proxy.
- Kagent defaults hardened for GS clusters: restricted-PSS `securityContext` applied at umbrella level (Kyverno requirement); bundled agents/tools disabled with comments explaining why and under what conditions to re-enable; Anthropic set as the default model provider (`claude-sonnet-4-6`); OTel traces and logs routed to `otlp-gateway.kube-system.svc:4317`; `controller.auth.mode: unsecure` (agentgateway provides the JWT validation boundary); `oauth2-proxy` values pre-wired for Dex OIDC integration (`enabled: false` until Dex client credentials are provided).

### Changed

- Bumped bundled `muster` to `0.2.1` (stable; muster#772 JWT signing-key wiring fix + `jwt_key.go` enabling edge JWT validation, and the CNP ingress-gateway egress fix from muster#788).
- Bumped bundled `agentic-platform-mcps` to `0.2.0` (stable release).

## [0.5.0] - 2026-05-29

### Added

- `agentic-platform-mcps` bundled as a conditional sub-chart (`condition: mcps.enabled`, default `false`). It renders the platform's MCP server CRs (muster `MCPServer` and/or agentgateway `AgentgatewayBackend` + `AgentgatewayPolicy`) from one abstract `agentic-platform-mcps.mcpServers` list. The toggle lives in a separate top-level `mcps:` block because the sub-chart's strict `values.schema.json` (`additionalProperties: false`) rejects an `enabled` key. The CRs consume CRDs shipped by the companion `agentic-platform-crds` chart — the umbrella still installs **zero** CRDs. New `ci/test-mcps-values.yaml` exercises the path.

## [0.4.1] - 2026-05-28

### Fixed

- Extended restricted-PSS `securityContext` defaults to the bundled valkey **metrics exporter sidecar** (`valkey.valkey.metrics.exporter.securityContext`). 0.4.0 hardened the main valkey container and its init container, but the `redis_exporter` sidecar (`containers[1]`, port 9121) lives under a separate values key and was still rejected by Kyverno's `disallow-privilege-escalation` policy.

## [0.4.0] - 2026-05-28

### Fixed

- Restored restricted-PSS compliant `securityContext`/`podSecurityContext` defaults on the bundled valkey sub-chart, which were inadvertently dropped during the CRD-chart split (0.3.0). Without them, Kyverno's `disallow-privilege-escalation` and `restrict-seccomp-strict` policies reject the `muster-valkey` Deployment because the init container reuses the main container's `securityContext` and the upstream defaults omit `allowPrivilegeEscalation: false` and `seccompProfile: RuntimeDefault`.

## [0.3.0] - 2026-05-28

### Added

- New `agentic-platform-crds` chart (`helm/agentic-platform-crds/`): a CRD-only umbrella that vendors the upstream `agentgateway-crds` (`v1.2.1`) and `muster-crds` sub-charts, shipping all five CRDs the platform's CRs consume. Install it **before** `agentic-platform`; CRD and workload lifecycles are now decoupled (two releases in sequence, Flux/Argo-agnostic). The muster CRDs are `helm.sh/resource-policy: keep`-protected via `muster-crds.crds.annotations`.
- Second CircleCI `architect/push-to-app-catalog` job (`package-and-push-crds-chart`) building and publishing `agentic-platform-crds` alongside `agentic-platform` on git tags.

### Changed

- All CRDs moved out of `agentic-platform` into the new `agentic-platform-crds` chart. `agentic-platform` now installs **zero** CRDs — it renders only the CRs (`Gateway`, `AgentgatewayParameters`, plus muster's). `helm template agentic-platform` emitting any `CustomResourceDefinition` is a regression.
- `muster.crds.install` defaulted to `false` in `agentic-platform` values, so the bundled `muster` sub-chart renders no CRDs (the currently pinned muster `0.1.197` still defaults `crds.install: true`).
- `Chart.yaml` description: CRDs now ship in the companion `agentic-platform-crds` chart.

### Removed

- `agentgateway-crds` sub-chart dependency (`condition: agentgateway-crds.enabled`) and the `agentgateway-crds:` values block from `agentic-platform`. The CRDs are provided by `agentic-platform-crds`.

## [0.2.0] - 2026-05-27

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

[Unreleased]: https://github.com/giantswarm/agentic-platform/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/giantswarm/agentic-platform/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/giantswarm/agentic-platform/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/giantswarm/agentic-platform/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/giantswarm/agentic-platform/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/giantswarm/agentic-platform/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/giantswarm/agentic-platform/releases/tag/v0.1.0

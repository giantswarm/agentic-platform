# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial agentic-platform chart bundling `muster` 0.1.193 and `agentgateway` v1.2.1.
- `Gateway` (name `agentgateway`) and `AgentgatewayParameters` overlay that injects `seccompProfile: RuntimeDefault` and drops all capabilities on the dynamically-rendered data-plane pod.
- `gateway.parameters.dataPlaneEnv` strategic-merge env list, projected onto the data-plane container so OTel exporter config (and any other env-driven knob) lands on the dynamically-rendered Deployment without forking the controller.
- `gateway.parameters.dataPlaneVolumes` and `gateway.parameters.dataPlaneVolumeMounts` strategic-merge lists for mounting external content (e.g. a cert-manager-issued CA bundle for `controller.xds.mode: tls`) onto the data-plane pod template.
- `CiliumNetworkPolicy` allowing cluster-entity ingress on the listener port and DNS / world / cluster-ingress / muster-aggregator egress.
- `values.schema.json` covering top-level keys; subchart keys pass-through.

### Changed

- The agentic platform no longer bundles `agentgateway-crds` or the muster sub-chart's CRDs. Helm 3 only honours `crds/` at the top-level chart, so bundled sub-chart CRDs would never install cleanly first-try and made every `helm upgrade` an implicit CRD migration. CRDs now ship in dedicated sibling charts (`agentgateway-crds`, `muster-crds`) and must be installed before the agentic platform — encode ordering with `spec.dependsOn` on the App CR, or with the documented `helm install` sequence in `README.md` / `NOTES.txt`. `muster.crds.install` is pinned to `false` in `values.yaml` as a safety declaration.
- `CiliumNetworkPolicy` egress broadened: DNS endpoint selectors now cover `kube-dns`, `coredns`, and `k8s-dns-node-cache` (ports 53 + 1053, UDP + TCP); world egress includes port 80; new `cluster` egress on 80/443 reaches in-cluster ingress (Dex / OIDC / MCPServers); new endpoint egress to `app.kubernetes.io/name=muster:8090` for OAuth + intrinsic tool calls. The previous policy only allowed `kube-dns:53` and `world:443`, which dropped DNS on clusters running NodeLocal DNSCache and blocked the controller from pushing XDS to the data plane.
- `muster.ciliumNetworkPolicy.allowClusterIngress` default flipped to `true` in the umbrella's values.yaml. Production Giant Swarm installs resolve OIDC and MCPServer backends via in-cluster ingress LoadBalancer / ClusterIP IPs that the muster sub-chart's `world` egress does not cover.
- `muster.gatewayAPI.httpRoute.parentRefs` and `.hostnames` no longer default to the umbrella's internal `agentgateway` Gateway. Muster's public HTTPRoute must attach to a separate, operator-owned public Gateway (typically `envoy-gateway-system/giantswarm-default`) — the muster sub-chart's existing fail-guard now blocks install until both fields are set explicitly. `muster.gatewayAPI.enabled` is `true` by default. README documents the values shape.
- Bundled `bitnami/valkey` 5.6.5 as a conditional sub-chart (`condition: valkey.enabled`, default `false`). `fullnameOverride: muster-valkey` pins the primary Service at `muster-valkey-primary.<ns>.svc` so muster's OAuth-session-storage URL convention matches without a cross-subchart values rewrite. README documents the wiring; operators with an out-of-band Valkey leave it disabled.
- README adds an "OAuth secrets" section documenting the inline-values vs `existingSecret` patterns. Auto-generation via Helm `lookup` is intentionally avoided — every `helm upgrade` would regenerate credentials and invalidate issued tokens.
- `GatewayClass agentgateway` documented as a cluster-level prerequisite (verified via `kubectl get gatewayclass agentgateway`). The bundled `agentgateway` controller subchart still satisfies the prereq on default installs; operators managing the controller out-of-band must ensure the `GatewayClass` exists.

[Unreleased]: https://github.com/giantswarm/agentic-platform/tree/main

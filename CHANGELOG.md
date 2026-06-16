# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- `klausGateway.a2a.url` now routes through the agentgateway data-plane Service (`http://agentgateway.agentic-platform.svc.cluster.local:8080/kagent/api/a2a/kagent`) instead of hitting `kagent-controller:8083` directly, so A2A egress is authenticated and observed by agentgateway. Requires a klaus-gateway release that forwards the caller's bearer token.

### Added

- `templates/klausgateway/netpol.yaml`: NetworkPolicy (cilium + kubernetes flavors) allowing klaus-gateway egress to the agentgateway data-plane Gateway on port 8080, rendered when `klausGateway.enabled` and `klausGateway.a2a.enabled`.

## [1.1.31] - 2026-06-16

### Fixed

- `networkPolicy.musterInClusterMcpPorts`: add `8443` to the default so muster's supplementary
  egress CNP permits reaching tunnelport RemoteApp tunnels (ghostunnel terminates TLS on `8443`).
  Without it, muster's connection to in-cluster tunnel backends
  (e.g. `mcp-kubernetes-garm.agentic-platform.svc:8443`) was silently dropped by Cilium and timed
  out (`context deadline exceeded`).

## [1.1.30] - 2026-06-16

### Changed

- Bump `klaus-gateway` subchart to `0.1.5`.

## [1.1.29] - 2026-06-15

### Fixed

- `klausGateway.a2a.saToken` and `klausGateway.upstream`: set `additionalProperties: true` in the
  values schema so the klaus-gateway subchart's own pass-through keys
  (`a2a.saToken.{expirationSeconds,mountPath}`, `upstream.url`) validate. These nested objects were
  still `additionalProperties: false` after the `1.1.27` `a2a` fix, leaving the `agentic-platform`
  HelmRelease stuck `UpgradeFailed` on management clusters whose rendered config supplies them.

## [1.1.28] - 2026-06-15

### Changed

- Bump `klaus-gateway` subchart from `0.1.1` to `0.1.2`.

## [1.1.27] - 2026-06-15

### Fixed

- `klausGateway.a2a`: set `additionalProperties: true` in the values schema so the klaus-gateway
  subchart's own a2a keys (`url`, `saToken`, …) pass through validation. This was missed when
  `klausGateway.routing`/`lifecycle` were widened, leaving the `agentic-platform` HelmRelease stuck
  `UpgradeFailed` on management clusters whose rendered config supplies `klausGateway.a2a.{url,saToken}`.
- `kagent.controllerRoute`: add outer public HTTPRoute (`kagent-controller-public`) on the Envoy
  Gateway so the kagent A2A endpoint is reachable at `https://<hostname>/kagent/...`. The inner
  `kagent-controller` route (agentgateway data plane) was already present, but the missing outer
  route caused Envoy to return 404 for all requests to the hostname before they reached the
  agentgateway pod. Configurable via `kagent.controllerRoute.parentRef` (defaults to
  `giantswarm-default` / `envoy-gateway-system`).
- `AgentgatewayBackend/kagent`: add `spec.policies.auth.passthrough: {}` so the validated muster JWT
  is forwarded to kagent-controller. The agentgateway JWT filter strips the Authorization header
  after validation; without passthrough the controller's `AUTH_MODE=trusted-proxy` receives no
  header and returns 401 for every authenticated request.
- `helm.sh/chart` label: truncating long dev-build versions at 63 characters could leave a trailing `.`, producing an invalid label value and failing the Helm install/upgrade. The `chart` helper now trims trailing `.` as well as `-`.
- `templates/kagent/agents/remotemcpservers.yaml`: `headersFrom[].valueFrom` used a `secretKeyRef` block, but the kagent v1alpha2 `ValueSource` schema is flat (`type`/`name`/`key` with `type: Secret`). The CRs failed admission with `valueFrom.key: Required value`.
- `templates/kagent/agents/muster-token-job.yaml`: mint the muster token via the TokenRequest API (`kubectl create token`, duration `agents.muster.tokenDuration`, default 8760h) instead of a legacy `kubernetes.io/service-account-token` Secret. Legacy Secret tokens carry `iss: kubernetes/serviceaccount` and no `exp`, so muster's `trustedIssuers` JWT validation (cluster OIDC issuer + required expiry) can never accept them; every RemoteMCPServer call failed with `Unauthorized`. The legacy token Secret is removed; the token now rotates on every install/upgrade.
- `templates/kagent/agents/muster-sa.yaml`: the token-init Role granted `create` on Secrets restricted by `resourceNames`, which Kubernetes RBAC never matches for create requests (the object name is not part of the authorization attributes). The hook Job failed with `secrets is forbidden` on first install. `create` is now an unrestricted (namespace-scoped) rule; `get`/`patch` stay name-restricted.
- `templates/kagent/declarative-agent-pod-security.yaml`: remove `seccompProfile: RuntimeDefault` from the injected pod and container security contexts. `RuntimeDefault` blocks `clone(CLONE_NEWUSER)` which bwrap (used by srt internally) requires for user-namespace isolation, causing every shell/bash tool invocation to fail with `bwrap: No permissions to create a new namespace`.
- `templates/kagent/policy-exception.yaml` (new): `PolicyException` in the `policy-exceptions` namespace exempting pods and deployments labelled `app: kagent` in the kagent namespace from the cluster-wide `restrict-seccomp-strict` Kyverno policy. Required because the cluster enforces seccomp profiles and we cannot simply omit `seccompProfile` without an exception.
- `templates/kagent/declarative-agent-srt-settings.yaml` (new): Kyverno policy that patches the `srt-settings.json` key in agent config Secrets (labelled `app: kagent`) on admission to include `"enableWeakerNestedSandbox": true`. Without this flag, bwrap attempts to bind-mount `/proc` into its new PID namespace, which fails inside unprivileged containers with `bwrap: Can't mount proc on /newroot/proc: Operation not permitted`. The flag is the documented srt workaround for container environments (`sandbox/linux-sandbox-utils.ts`); the kagent controller does not expose it through any CR field.
- `templates/kagent/declarative-agent-pod-security.yaml`: extend the security context mutation to `SandboxAgent` CRs. `SandboxAgent` is a distinct kind from `Agent` and was not covered by the existing rule; pods created via the `agents.x-k8s.io` Sandbox backend were blocked by `disallow-capabilities-strict`, `disallow-privilege-escalation`, and `require-run-as-nonroot` Kyverno policies.

## [1.1.26] - 2026-06-12

### Fixed

- Update muster to 0.4.1 (mcp-oauth v0.3.1): forwarded ID tokens (`trustedAudiences`) are no longer hard-rejected when the same issuer is also configured in `trustedIssuers` for the token-exchange broker — fixes Backstage AI-chat SSO forwarding returning 401 behind the agentgateway.

## [1.1.25] - 2026-06-11

### Fixed

- `gateway.jwksEgress` now also opens egress on the agentgateway **controller** network policy
  (Cilium and kubernetes flavors). The controller fetches remote JWKS centrally and distributes
  keys to the data plane via xDS, so the data-plane-only rule left JWKS fetches timing out
  (e.g. Dex on giantswarm/dex:5556 for extra JWT providers).

## [1.1.24] - 2026-06-11

### Changed

- Update agentic-platform-mcps to v0.3.0: new `agentgateway.jwt.extraProviders` value lets the
  inbound agentgateway JWT policy accept tokens from additional issuers (e.g. Dex-issued ID tokens
  forwarded by Backstage AI chat alongside muster-issued JWTs, giantswarm#36840). Also fixes the
  `identityProviders` values schema that rejected every populated provider map.

### Fixed

- `templates/kagent/declarative-agent-pod-security.yaml`: retarget the Kyverno mutate from `Deployment` (controller output) to `Agent` CR (controller input). The previous policy patched the Deployment after the kagent controller had already stamped `privileged: true` on the git-skills path, causing the API server to reject the Deployment as self-contradictory (`privileged: true` + `allowPrivilegeEscalation: false`). Mutating the Agent CR instead sets `allowPrivilegeEscalation: false` on the controller input, which trips the controller's own guard and prevents `privileged: true` from being set in the first place. A `(type): "Declarative"` condition anchor scopes the mutation to Declarative agents only.

## [1.1.23] - 2026-06-11

### Changed

- Update muster and muster-crds to v0.4.0 (via v0.3.14): muster now supports brokered RFC 8693 token exchange (giantswarm/muster#831) — external confidential clients can exchange a trusted-issuer subject token plus an `audience` parameter at `/oauth/token` for a token minted by the audience's downstream Dex. New `muster.oauth.server.tokenExchangeBroker` values block (per-client audience allowlist, audience → downstream Dex target mapping); mcp-oauth bumped to v0.3.0. Inert by default.

## [1.1.22] - 2026-06-11

### Changed

- Update muster and muster-crds to v0.3.13. Muster's OAuth server (mcp-oauth v0.2.199) now defaults the JWT access token `aud` claim to its resource identifier when a client omits the RFC 8707 `resource` parameter, so tokens from generic OAuth clients (e.g. Backstage auth providers) pass the agentgateway's strict JWT audience validation on `/mcp` instead of failing with `401 InvalidAudience`.

## [1.1.21] - 2026-06-10

### Fixed

- Downgrade bundled agentgateway and agentgateway-crds charts from `v2.2.1` back to `v1.2.1`. The upstream project released `v2.2.x` before resetting semver to `v1.0.0`; `v2.2.1` is older than `v1.0.0` and was incorrectly treated as an upgrade (agentgateway/agentgateway#1249). Block the bogus `v2.2.x` range in `renovate.json5`.

- `templates/agentgateway/agentgatewayparameters.yaml`: data-plane image override moved from the deployment container spec to `spec.image.registry/repository/tag`. Drops `AGW_XDS_SERVICE_NAME` from `controller.extraEnv` and removes the explicit controller image tag pin: the v1.2.1 chart already sets `AGW_XDS_SERVICE_NAME: agentgateway-controller` correctly via `fullnameOverride`, and the controller image tag defaults to the chart's `appVersion` (`v1.2.1`) when unset.

- `templates/kagent/ui-httproute.yaml`: oauth2-proxy backend name now resolves `oauth2-proxy.fullnameOverride` from values (falling back to `<release>-oauth2-proxy`), so the `HTTPRoute` points at the correct service when `fullnameOverride: kagent-oauth2-proxy` is set.

- Bundled kagent declarative agents (`cilium-policy-agent`, `promql-agent`, and all others) now deploy into the `kagent` namespace. The kagent `kagent.namespace` helper resolves `namespaceOverride` from the subchart's own `.Values` scope; the parent chart's `kagent.namespaceOverride: kagent` is not visible there, so agents were landing in the Helm release namespace (`agentic-platform`). Both `default-model-config` (ModelConfig) and `kagent-tool-server` (RemoteMCPServer) live in `kagent` and are resolved by bare name within the agent's own namespace, causing every agent to show `Accepted=False`. Each bundled agent subchart block now sets `namespaceOverride: kagent` explicitly.

- `templates/kagent/ui-backendtrafficpolicy.yaml`: route-level `BackendTrafficPolicy` for the kagent UI `HTTPRoute`. The cluster-wide `gateway-giantswarm-default-error-pages` policy replaces all 4xx/5xx bodies with static HTML; without a route-level override, Envoy replaces oauth2-proxy's 403 sign-in page body (which meta-refreshes to `/login`) with that static page, breaking the login flow entirely. Any route-level `BackendTrafficPolicy` overrides the gateway-wide one, so this policy is rendered with `enabled: true` by default whenever `kagent.uiRoute.enabled: true`.

### Added

- `klausGateway.enabled` (default `false`) adds `giantswarm/klaus-gateway` as an opt-in conditional dependency (`condition: klausGateway.enabled`, alias `klausGateway`). With the flag unset or false the rendered output is byte-identical to the previous chart version. When enabled, the sub-chart installs the Klaus Gateway Deployment, Service, RBAC, and ChannelRoute CRD (via `crd.install: true`). The sub-chart's own agentgateway dependency is disabled (`klausGateway.agentgateway.enabled: false`) so the umbrella's bundled agentgateway is reused.
- Single `ingress.mode` topology selector (`muster-direct` | `agentgateway-muster` | `agentgateway-direct`) that declares the whole request topology in one place. The umbrella now owns **both** public routes — muster's `/` catch-all (new `templates/ingress/muster-httproute.yaml`, rendered in all modes) and the agentgateway `/mcp` interception route — fed from a single shared `ingress.parentRefs` / `ingress.hostnames`, so the two routes can no longer drift. A template-time guard (`templates/validate.yaml`) fails fast on an invalid mode, on `ingress.parentRefs` empty in **any** mode (the umbrella-owned muster `/` route attaches to it — an empty `parentRefs` would otherwise render a route bound to no Gateway), and on `agentgateway.enabled` / `agentic-platform-mcps.agentgateway.viaMuster` disagreeing with the mode.
- `agentgateway.enabled` (default `false`) gates the agentgateway controller dependency via `condition: agentgateway.enabled` in `Chart.yaml`. In the default `muster-direct` mode the controller, its `GatewayClass`, the data-plane `Gateway`/`AgentgatewayParameters`, and the data-plane NetworkPolicies are **not installed**.
- `agentgateway-direct` mode is modelled but **fail-guarded** — install is blocked with a clear message until a DCR-capable IdP (RFC 7591/8707) lands.
- `make verify-modes` target (wired into a new CircleCI branch test job) asserts the fail-guards fire; `ci/test-full-stack-values.yaml` now exercises the previously-untested `agentgateway-muster` path.
- Route-scoped `BackendTrafficPolicy` for muster's `/` route (new `templates/ingress/muster-backendtrafficpolicy.yaml`), rendered in **all** modes when `ingress.backendTrafficPolicy.enabled` is set — not just the agentgateway `/mcp` route. This preserves muster's `401 … WWW-Authenticate` challenge against the cluster-wide error-pages policy in `muster-direct` mode (where muster serves `/mcp` directly) and restores the pre-refactor `muster.gatewayAPI.backendTrafficPolicy` behavior on muster's own route.
- Per-route `ingress.httpRoute.muster.{annotations,labels}` and `ingress.httpRoute.mcp.{annotations,labels}` overrides, merged on top of the shared `ingress.httpRoute.{annotations,labels}` (per-route keys win on collision). Lets a downstream diverge one route — e.g. a different cert-manager issuer or Envoy route policy per route — without forking the shared block.
- `kagent-crds` (`v0.9.5`, `oci://ghcr.io/kagent-dev/kagent/helm`) bundled as a sub-chart. Installs the kagent CRDs (`Agent`, `AgentHarness`, `ModelConfig`, `MCPServer`, `RemoteMCPServer`, `Memory`, `ToolServer`, `SandboxAgent`). Must be installed before the `agentic-platform` chart when `kagent.enabled: true`. Note: upstream does not mark these CRDs `helm.sh/resource-policy: keep`; `helm uninstall agentic-platform-crds` will remove them and cascade to all kagent CRs.
- `kagent` (`v0.9.5`, `oci://ghcr.io/kagent-dev/kagent/helm`) bundled as a conditional sub-chart (`kagent.enabled`, default `false`). All kagent resources land in `kagent.namespaceOverride` (default `kagent`) so they stay separate from the umbrella's release namespace. The `kagent-crds` chart is added to `agentic-platform-crds` as a prerequisite. Enabling kagent requires `agentic-platform-crds` to be installed first.
- `kagent.oauth2-proxy.metrics.serviceMonitor.enabled: true` — Prometheus `ServiceMonitor` for the oauth2-proxy metrics endpoint (`:44180`), labelled `observability.giantswarm.io/tenant: giantswarm`.
- `templates/kagent/netpol.yaml`: oauth2-proxy ingress CNP extended to allow scraping of the metrics port (`:44180`) from any cluster-entity source, and oauth2-proxy egress extended to include `cluster` alongside `world` on port 443 — required when the Dex hostname resolves to an internal LB VIP (private-range IP classified as `cluster` by Cilium, not `world`).
- `postgres` block: opt-in CloudNativePG `Cluster` CR (`postgres.enabled`, default `false`) provisioning the kagent application database in a named `kagent` schema (not `public`). Supports pgvector via `postInitTemplateSQL` (any CNPG version, bundled image) or the ImageVolume approach (`postgres.vector.extensionImage.reference`, CNPG 1.29+/PG18). The CNPG operator and its CRDs remain a cluster-level prerequisite. An optional Klaus sessions database (`postgres.sessionsDatabase.enabled`, default `false`) is templated but left off pending the core-runtime persistence decision.
- `templates/namespace.yaml`: renders the `kagent` `Namespace` when `kagent.namespaceOverride` differs from the release namespace, so fresh installs do not require manual namespace pre-creation.
- `templates/kagent/controller-route.yaml`: opt-in `AgentgatewayBackend` + `HTTPRoute` (`kagent.controllerRoute.enabled`) exposing the kagent controller API through agentgateway with JWT validation.
- `templates/kagent/netpol.yaml`: cross-namespace network policies for kagent (cilium and kubernetes flavors, gated on `networkPolicy.flavor`). Cilium: egress from agentgateway data-plane to kagent controller (port 8083) + ingress policy in the kagent namespace. Kubernetes: `NetworkPolicy` restricting kagent controller ingress to the release and kagent namespaces, preventing direct access that would bypass agentgateway JWT validation.
- `templates/kagent/ui-httproute.yaml`: opt-in HTTPRoute (`kagent.uiRoute.enabled`) exposing the kagent UI on the public Gateway. When `oauth2-proxy.enabled: true` routes through oauth2-proxy (port 4180); otherwise routes directly to the UI (dev only). Placed in the kagent namespace to avoid cross-namespace backend refs.
- `ci/test-postgres-values.yaml`: CI values file exercising the kagent+postgres path through `helm template`/lint.
- `ci/test-kagent-routing-values.yaml`: CI values file exercising controllerRoute + uiRoute + oauth2-proxy.
- Kagent defaults hardened for GS clusters: restricted-PSS `securityContext` applied at umbrella level (Kyverno requirement); bundled agents/tools disabled with comments explaining why and under what conditions to re-enable; Anthropic set as the default model provider (`claude-sonnet-4-6`); OTel traces and logs routed to `otlp-gateway.kube-system.svc:4317`; `controller.auth.mode: trusted-proxy` (agentgateway validates the JWT upstream and the netpols fence the controller); `oauth2-proxy` values pre-wired for Dex OIDC integration (`enabled: false` until Dex client credentials are provided).

### Fixed

- In-cluster MCP backends that listen on a non-80/443 port (e.g. the bundled `pro` / `runbooks` MCP servers on `8080`, reached via a ClusterIP) were unreachable from muster — its sub-chart CNP permits cluster-entity egress only on 80/443, so those connections timed out and the corresponding `MCPServer`s went `Failed`. The umbrella now renders a supplementary `CiliumNetworkPolicy` (`<muster>-mcp-egress`) that widens muster's egress to `networkPolicy.musterInClusterMcpPorts` (default `[8080]`; cilium flavor only; Cilium policies are additive, so no sub-chart fork). Set to `[]` to disable.
- **Muster Service name is now pinned** via `muster.fullnameOverride: agentic-platform-muster`, read directly by the umbrella's `agentic-platform.musterFullname` helper instead of re-deriving the muster sub-chart's release-name algorithm. The route `backendRef`, the `BackendTrafficPolicy` target, and `agentic-platform-mcps.musterUrl` now reference one source of truth that stays in lockstep with the sub-chart's Service regardless of release name or any future muster naming change. A blank override fails the render loudly rather than silently pointing the route at a non-existent Service (503).

### Changed

- Bumped bundled `muster` to `0.2.6` (includes the muster#772 JWT signing-key wiring fix + `jwt_key.go` enabling edge JWT validation, and the CNP ingress-gateway egress fix from muster#788).
- Bumped bundled `agentic-platform-mcps` to `0.2.4` — corrects the `identityProviders` value schema (it was `additionalProperties: false` with no properties, forbidding every provider key and making `auth.mode: exchange` unconfigurable). Unblocks multi-cluster token-exchange consumers; `forward`-only installs are unaffected.

### Removed

- **Breaking:** `gateway.enabled`, `gateway.httpRoute.*`, and `gateway.backendTrafficPolicy.*` are removed — replaced by `ingress.mode` (topology switch), `ingress.parentRefs` / `ingress.hostnames` (shared route attachment), and `ingress.backendTrafficPolicy.*`. The retained `gateway.*` keys now hold data-plane *infrastructure* only and apply in `agentgateway-*` modes. `muster.gatewayAPI.enabled` is now `false` (the umbrella renders muster's public route) — set `ingress.parentRefs` / `ingress.hostnames` instead of `muster.gatewayAPI.httpRoute.*`.

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

[Unreleased]: https://github.com/giantswarm/agentic-platform/compare/v1.1.31...HEAD
[1.1.31]: https://github.com/giantswarm/agentic-platform/compare/v1.1.30...v1.1.31
[1.1.30]: https://github.com/giantswarm/agentic-platform/compare/v1.1.30...v1.1.30
[1.1.30]: https://github.com/giantswarm/agentic-platform/compare/v1.1.29...v1.1.30
[1.1.29]: https://github.com/giantswarm/agentic-platform/compare/v1.1.28...v1.1.29
[1.1.28]: https://github.com/giantswarm/agentic-platform/compare/v1.1.27...v1.1.28
[1.1.27]: https://github.com/giantswarm/agentic-platform/compare/v1.1.26...v1.1.27
[1.1.26]: https://github.com/giantswarm/agentic-platform/compare/v1.1.25...v1.1.26
[1.1.25]: https://github.com/giantswarm/agentic-platform/compare/v1.1.24...v1.1.25
[1.1.24]: https://github.com/giantswarm/agentic-platform/compare/v1.1.23...v1.1.24
[1.1.23]: https://github.com/giantswarm/agentic-platform/compare/v1.1.22...v1.1.23
[1.1.22]: https://github.com/giantswarm/agentic-platform/compare/v1.1.21...v1.1.22
[1.1.21]: https://github.com/giantswarm/agentic-platform/compare/v0.5.0...v1.1.21
[0.5.0]: https://github.com/giantswarm/agentic-platform/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/giantswarm/agentic-platform/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/giantswarm/agentic-platform/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/giantswarm/agentic-platform/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/giantswarm/agentic-platform/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/giantswarm/agentic-platform/releases/tag/v0.1.0

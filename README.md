[![CircleCI](https://dl.circleci.com/status-badge/img/gh/giantswarm/agentic-platform/tree/main.svg?style=svg)](https://dl.circleci.com/status-badge/redirect/gh/giantswarm/agentic-platform/tree/main)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/giantswarm/agentic-platform/badge)](https://securityscorecards.dev/viewer/?uri=github.com/giantswarm/agentic-platform)

# agentic-platform

Giant Swarm umbrella chart that ships [muster](https://github.com/giantswarm/muster) (MCP gateway / aggregator) and [agentgateway](https://github.com/agentgateway/agentgateway) (MCP data plane) as one deploy unit, plus the `Gateway`, `AgentgatewayParameters`, and `CiliumNetworkPolicy` resources that wire them together.

Owner: team-bumblebee.

## Prerequisites

- Kubernetes ≥ 1.33 on the install target.
- Gateway API v1 CRDs (`gateways.gateway.networking.k8s.io`, `httproutes.gateway.networking.k8s.io`, `gatewayclasses.gateway.networking.k8s.io`) installed cluster-wide. The umbrella does **not** install them.
- A `GatewayClass` named `agentgateway` reconciled by the agentgateway controller — this chart's `Chart.yaml` pulls the upstream agentgateway controller chart which creates the `GatewayClass`.
- Cilium CNI if `networkPolicy.type: cilium` (default). Set `networkPolicy.enabled: false` on non-Cilium clusters.

## Installing

Install via the Giant Swarm app platform (preferred):

```yaml
apiVersion: application.giantswarm.io/v1alpha1
kind: App
metadata:
  name: agentic-platform
  namespace: <org-namespace>
spec:
  catalog: giantswarm
  name: agentic-platform
  namespace: muster
  version: <chart-version>
```

Direct Helm install (development / kind):

```bash
helm install agentic-platform \
  oci://giantswarmpublic.azurecr.io/giantswarm-catalog/agentic-platform \
  --version <chart-version> \
  --namespace muster --create-namespace
```

## Configuration

Top-level values surfaced by the umbrella:

| Key | Default | Purpose |
|---|---|---|
| `global.registry` | `gsoci.azurecr.io` | Default container image registry. |
| `gateway.name` | `agentgateway` | `Gateway` resource name; HTTPRoute parentRefs use this. |
| `gateway.gatewayClassName` | `agentgateway` | The `GatewayClass` the data plane attaches to. |
| `gateway.listeners` | `[{name: http, port: 8080, protocol: HTTP}]` | Listener spec passed verbatim. |
| `gateway.parameters.enabled` | `true` | Render the `AgentgatewayParameters` overlay. |
| `gateway.parameters.{pod,container}SecurityContext` | restricted-PSS compatible | Injected into the data-plane Deployment via strategic merge patch. |
| `networkPolicy.enabled` / `.type` | `true` / `cilium` | Render the umbrella's `CiliumNetworkPolicy`. |
| `muster.*` | passes through to the muster subchart | See [muster chart README](https://github.com/giantswarm/muster/blob/main/helm/muster/README.md). |
| `agentgateway.*` | passes through to the upstream agentgateway chart | See [agentgateway docs](https://agentgateway.dev). |

Full schema: [`helm/agentic-platform/values.schema.json`](./helm/agentic-platform/values.schema.json).

## Air-gapped / private registries

All images default to `gsoci.azurecr.io/giantswarm/*`:

| Image | Source (mirrored by GS retagger) |
|---|---|
| `gsoci.azurecr.io/giantswarm/muster:0.1.193` | `gsoci.azurecr.io/giantswarm/muster` (native GS image) |
| `gsoci.azurecr.io/giantswarm/agentgateway-controller:v1.2.1` | `cr.agentgateway.dev/controller` |
| `gsoci.azurecr.io/giantswarm/agentgateway:v1.2.1` | `cr.agentgateway.dev/agentgateway` |

To pull from a customer zot mirror, override the registry on every image (neither subchart exposes a `global.registry` that propagates to all images):

```yaml
global:
  registry: zot.example.com

muster:
  image:
    registry: zot.example.com

agentgateway:
  image:
    registry: zot.example.com
  proxy:
    image:
      registry: zot.example.com
```

The customer's zot must mirror these paths verbatim: `giantswarm/muster`, `giantswarm/agentgateway-controller`, `giantswarm/agentgateway`.

## Security

The agentgateway data-plane pod template is rendered at runtime by the controller, not by Helm. To inject restricted-PSS-compatible `securityContext` fields, the umbrella ships an `AgentgatewayParameters` resource referenced from `Gateway.spec.infrastructure.parametersRef`. The controller applies it as a strategic merge patch over the generated Deployment.

The data-plane pod template hardcodes `sysctls: [net.ipv4.ip_unprivileged_port_start=0]`. This is a **namespaced-safe** sysctl (does not require `allowedUnsafeSysctls` on the kubelet). On clusters with built-in Pod Security Admission `restricted` enforced, the sysctl will be rejected — label the install namespace with `pod-security.kubernetes.io/enforce: baseline` (or allowlist the sysctl in Kyverno's `restrict-sysctls` policy as Giant Swarm workload clusters already do).

## CRD lifecycle

- **Gateway API CRDs** — assumed pre-installed (prerequisite). Not managed by this chart.
- **agentgateway CRDs** (`AgentgatewayParameters`, `AgentgatewayBackend`, `AgentgatewayPolicy`) — installed via the `agentgateway-crds` subchart (templates path, so `helm upgrade` works). Upstream does **not** annotate them with `helm.sh/resource-policy: keep`, so `helm uninstall agentic-platform` will cascade-delete the CRDs and every CR. Set `agentgateway-crds.enabled: false` and manage them out-of-band if you need uninstall safety.
- **muster CRDs** (`MCPServer`, `Workflow`) — installed by the muster subchart from its `crds/` directory. Helm installs once; upgrades require `kubectl apply -f` of the CRD bundle before `helm upgrade`.

## Compatibility

This chart targets Giant Swarm workload clusters running Kubernetes ≥ 1.33 with Cilium and Kyverno.

## Credit

- [muster](https://github.com/giantswarm/muster) — Giant Swarm, Apache 2.0.
- [agentgateway](https://github.com/agentgateway/agentgateway) — agentgateway authors, Apache 2.0.

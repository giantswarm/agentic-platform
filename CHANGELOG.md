# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial agentic-platform chart bundling `muster` 0.1.193 and `agentgateway` v1.2.1 (plus `agentgateway-crds` v1.2.1).
- `Gateway` (name `agentgateway`) and `AgentgatewayParameters` overlay that injects `seccompProfile: RuntimeDefault` and drops all capabilities on the dynamically-rendered data-plane pod.
- `CiliumNetworkPolicy` allowing cluster-entity ingress on the listener port and DNS / world-443 egress.
- `values.schema.json` covering top-level keys; subchart keys pass-through.

[Unreleased]: https://github.com/giantswarm/agentic-platform/tree/main

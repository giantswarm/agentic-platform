# Custom targets, auto-included by the root Makefile's `include Makefile.*.mk`.
# Lives outside the devctl-generated Makefile.gen.app.mk so it survives
# regeneration. DO NOT move these targets into the generated file.

##@ Custom

CHART_DIR ?= helm/agentic-platform

# Subchart-quieting flags: the muster/valkey subcharts emit their own render-time
# `fail`s when run without secrets, which would mask the ingress.mode guards we
# are exercising here. Disable them so the umbrella's validate.yaml guard is the
# only thing that can fail a render.
VM_QUIET_BASE := --set valkey.enabled=false \
                 --set muster.muster.oauth.server.enabled=false \
                 --set muster.muster.oauth.server.storage.type=memory
# parentRefs[0].name satisfies the all-modes parentRefs guard so we isolate the
# guard under test. Use VM_QUIET_BASE (no parentRefs) to exercise that guard.
VM_QUIET := $(VM_QUIET_BASE) --set ingress.parentRefs[0].name=x

.PHONY: verify-modes
verify-modes: ## Assert ingress.mode fail-guards fire (mode 3 + consistency guards).
	@echo "====> $@"
	@helm dependency build $(CHART_DIR) >/dev/null
	@echo "--> muster-direct with empty parentRefs must fail"
	@if helm template t $(CHART_DIR) $(VM_QUIET_BASE) --set ingress.mode=muster-direct >/tmp/vm-parents.out 2>&1; then \
		echo "FAIL: empty-parentRefs guard did not fire (render succeeded)"; cat /tmp/vm-parents.out; exit 1; \
	elif ! grep -q "ingress.parentRefs is required in all modes" /tmp/vm-parents.out; then \
		echo "FAIL: empty-parentRefs check failed for the wrong reason"; cat /tmp/vm-parents.out; exit 1; \
	else echo "ok: empty-parentRefs guard"; fi
	@echo "--> agentgateway-direct must be blocked with the DCR message"
	@if helm template t $(CHART_DIR) $(VM_QUIET) --set ingress.mode=agentgateway-direct >/tmp/vm-direct.out 2>&1; then \
		echo "FAIL: direct-mode guard did not fire (render succeeded)"; cat /tmp/vm-direct.out; exit 1; \
	elif ! grep -q "requires a DCR-capable IdP" /tmp/vm-direct.out; then \
		echo "FAIL: direct-mode failed for the wrong reason"; cat /tmp/vm-direct.out; exit 1; \
	else echo "ok: direct blocked"; fi
	@echo "--> agentgateway-muster + viaMuster:false must fail"
	@if helm template t $(CHART_DIR) $(VM_QUIET) --set ingress.mode=agentgateway-muster --set agentgateway.enabled=true --set mcps.enabled=true --set agentic-platform-mcps.agentgateway.viaMuster=false >/tmp/vm-via.out 2>&1; then \
		echo "FAIL: viaMuster guard did not fire"; exit 1; \
	elif ! grep -q "viaMuster=true" /tmp/vm-via.out; then \
		echo "FAIL: viaMuster check failed for the wrong reason"; cat /tmp/vm-via.out; exit 1; \
	else echo "ok: viaMuster guard"; fi
	@echo "--> bogus mode must fail"
	@if helm template t $(CHART_DIR) $(VM_QUIET) --set ingress.mode=bogus >/tmp/vm-enum.out 2>&1; then \
		echo "FAIL: enum guard did not fire"; exit 1; \
	elif ! grep -q "must be one of" /tmp/vm-enum.out; then \
		echo "FAIL: enum check failed for the wrong reason"; cat /tmp/vm-enum.out; exit 1; \
	else echo "ok: enum guard"; fi
	@echo "--> agentgateway-muster + agentgateway.enabled:false must fail"
	@if helm template t $(CHART_DIR) $(VM_QUIET) --set ingress.mode=agentgateway-muster --set agentgateway.enabled=false >/tmp/vm-dep.out 2>&1; then \
		echo "FAIL: dep-condition guard did not fire"; exit 1; \
	elif ! grep -q "agentgateway.enabled must be true" /tmp/vm-dep.out; then \
		echo "FAIL: dep-condition check failed for the wrong reason"; cat /tmp/vm-dep.out; exit 1; \
	else echo "ok: dep-condition guard"; fi
	@echo "--> positive: a valid agentgateway-muster config must render"
	@if helm template t $(CHART_DIR) $(VM_QUIET) --set ingress.mode=agentgateway-muster --set agentgateway.enabled=true --set mcps.enabled=true --set agentic-platform-mcps.agentgateway.viaMuster=true >/dev/null 2>&1; then \
		echo "ok: valid config renders"; \
	else echo "FAIL: a valid agentgateway-muster config was rejected"; exit 1; fi
	@echo "All mode guards verified."

META_DIR ?= helm/agentic-platform-meta

.PHONY: verify-meta
verify-meta: ## Assert the meta-package POC renders in both engines + the pinned BOM.
	@echo "====> $@"
	@echo "--> no subcharts: a meta-package has no Chart.yaml dependencies (no helm dependency build)"
	@if grep -q '^dependencies:' $(META_DIR)/Chart.yaml; then \
		echo "FAIL: meta-package must not pin component versions in Chart.yaml"; exit 1; \
	else echo "ok: zero pinned dependencies"; fi
	@echo "--> flux engine renders OCIRepository + HelmRelease with version RANGES"
	@helm template t $(META_DIR) --set components.klaus-gateway.enabled=true >/tmp/meta-flux.out 2>&1 || { cat /tmp/meta-flux.out; exit 1; }
	@grep -q 'kind: OCIRepository' /tmp/meta-flux.out || { echo "FAIL: no OCIRepository rendered"; exit 1; }
	@grep -q 'kind: HelmRelease'   /tmp/meta-flux.out || { echo "FAIL: no HelmRelease rendered"; exit 1; }
	@grep -q 'semver: "0.4.x"'     /tmp/meta-flux.out || { echo "FAIL: muster version range not rendered as a value"; exit 1; }
	@grep -q 'name: agentic-platform-crds' /tmp/meta-flux.out || { echo "FAIL: crds dependsOn target missing"; exit 1; }
	@grep -q 'pattern: ".*-dev' /tmp/meta-flux.out || { echo "FAIL: dev-tag filterTags not rendered"; exit 1; }
	@echo "ok: flux render"
	@echo "--> argo engine renders Applications with CRD-first sync-waves"
	@helm template t $(META_DIR) --set gitops.engine=argo >/tmp/meta-argo.out 2>&1 || { cat /tmp/meta-argo.out; exit 1; }
	@grep -q 'kind: Application' /tmp/meta-argo.out || { echo "FAIL: no Argo Application rendered"; exit 1; }
	@grep -q 'sync-wave: "0"' /tmp/meta-argo.out || { echo "FAIL: CRDs not in sync-wave 0"; exit 1; }
	@echo "ok: argo render"
	@echo "--> bogus engine must fail"
	@if helm template t $(META_DIR) --set gitops.engine=bogus >/tmp/meta-eng.out 2>&1; then \
		echo "FAIL: engine guard did not fire"; exit 1; \
	elif ! grep -q "must be one of: flux, argo" /tmp/meta-eng.out; then \
		echo "FAIL: engine guard failed for the wrong reason"; cat /tmp/meta-eng.out; exit 1; \
	else echo "ok: engine guard"; fi
	@echo "--> customer BOM pins every range to an exact version"
	@helm template t $(META_DIR) -f $(META_DIR)/ci/customer-bom-values.yaml >/tmp/meta-bom.out 2>&1 || { cat /tmp/meta-bom.out; exit 1; }
	@grep -q 'semver: "0.4.1"' /tmp/meta-bom.out || { echo "FAIL: BOM did not pin muster to 0.4.1"; exit 1; }
	@if grep -q 'semver: ".*x"' /tmp/meta-bom.out; then echo "FAIL: BOM still contains an unpinned range"; exit 1; fi
	@echo "ok: customer BOM pinned"
	@echo "meta-package POC verified."

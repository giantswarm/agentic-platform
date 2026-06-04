# Custom targets, auto-included by the root Makefile's `include Makefile.*.mk`.
# Lives outside the devctl-generated Makefile.gen.app.mk so it survives
# regeneration. DO NOT move these targets into the generated file.

##@ Custom

CHART_DIR ?= helm/agentic-platform

# Subchart-quieting flags: the muster/valkey subcharts emit their own render-time
# `fail`s when run without secrets, which would mask the ingress.mode guards we
# are exercising here. Disable them so the umbrella's validate.yaml guard is the
# only thing that can fail a render. parentRefs[0].name satisfies the
# agentgateway-* parentRefs guard so we isolate the guard under test.
VM_QUIET := --set valkey.enabled=false \
            --set muster.muster.oauth.server.enabled=false \
            --set muster.muster.oauth.server.storage.type=memory \
            --set ingress.parentRefs[0].name=x

.PHONY: verify-modes
verify-modes: ## Assert ingress.mode fail-guards fire (mode 3 + consistency guards).
	@echo "====> $@"
	@helm dependency build $(CHART_DIR) >/dev/null
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

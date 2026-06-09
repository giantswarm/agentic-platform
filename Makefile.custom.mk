# Custom targets, auto-included by the root Makefile's `include Makefile.*.mk`.
# Lives outside the devctl-generated Makefile.gen.app.mk so it survives
# regeneration. DO NOT move these targets into the generated file.

##@ Custom

CHART_DIR ?= helm/agentic-platform

.PHONY: helm-test
helm-test: ## Run helm unit tests (helm-unittest plugin required).
	@echo "====> $@"
	@helm dependency build $(CHART_DIR) >/dev/null
	@helm unittest $(CHART_DIR)

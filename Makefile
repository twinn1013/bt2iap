SHELL := /bin/bash

# Self-documenting help: targets with ## comments are listed.
.PHONY: help check check-t1 check-t2 clean


# Default target
help: ## Show this help message
	@echo "bt2iap — Bluetooth-to-iAP bridge for Mitsubishi Outlander MMCS"
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@grep -E '^[a-zA-Z0-9_-]+:.*## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'

check: check-t1 ## Run all Mac-side quality gates (currently check-t1)

check-t1: ## T1 quality gates: shellcheck, systemd headers, boot patches, doc presence
	@if ! command -v shellcheck >/dev/null 2>&1; then \
		echo "ERROR: shellcheck not found."; \
		echo "Install:  brew install shellcheck   (macOS)"; \
		echo "          apt install shellcheck     (Linux/Debian)"; \
		exit 1; \
	fi
	@echo "==> [check-t1] shellcheck on scripts/"
	@if [ ! -d scripts ]; then \
		echo "ERROR: scripts/ directory not found. Run Workers 2 first."; \
		exit 1; \
	fi
	@fail=0; \
	for f in scripts/*.sh; do \
		[ -f "$$f" ] || continue; \
		shellcheck -x "$$f" || fail=1; \
	done; \
	if [ $$fail -ne 0 ]; then \
		echo "ERROR: shellcheck found issues in scripts/*.sh"; \
		exit 1; \
	fi
	@echo "    PASS: shellcheck"
	@echo ""
	@echo "==> [check-t1] systemd unit header check"
	@unit=systemd/ipod-gadget.service; \
	if [ ! -f "$$unit" ]; then \
		echo "ERROR: $$unit not found."; \
		exit 1; \
	fi; \
	fail=0; \
	for section in '\[Unit\]' '\[Service\]' '\[Install\]'; do \
		if ! grep -qE "$$section" "$$unit"; then \
			echo "ERROR: $$unit is missing section: $$section"; \
			fail=1; \
		fi; \
	done; \
	if [ $$fail -ne 0 ]; then exit 1; fi
	@echo "    PASS: systemd unit headers ([Unit] [Service] [Install])"
	@echo ""
	@echo "==> [check-t1] boot patch content check"
	@cfg=boot/config.txt.patch; \
	if [ ! -f "$$cfg" ]; then \
		echo "ERROR: $$cfg not found."; \
		exit 1; \
	fi; \
	if ! grep -q 'dtoverlay=dwc2' "$$cfg"; then \
		echo "ERROR: $$cfg does not contain 'dtoverlay=dwc2'"; \
		exit 1; \
	fi
	@echo "    PASS: boot/config.txt.patch contains dtoverlay=dwc2"
	@cmd=boot/cmdline.txt.patch; \
	if [ ! -f "$$cmd" ]; then \
		echo "ERROR: $$cmd not found."; \
		exit 1; \
	fi; \
	if ! grep -q 'modules-load=dwc2' "$$cmd"; then \
		echo "ERROR: $$cmd does not contain 'modules-load=dwc2'"; \
		exit 1; \
	fi
	@echo "    PASS: boot/cmdline.txt.patch contains modules-load=dwc2"
	@echo ""
	@echo "==> [check-t1] docs presence check"
	@fail=0; \
	for doc in docs/research-ipod-gadget.md docs/verification-t1.md; do \
		if [ ! -f "$$doc" ]; then \
			echo "ERROR: $$doc not found."; \
			fail=1; \
		elif [ ! -s "$$doc" ]; then \
			echo "ERROR: $$doc exists but is empty."; \
			fail=1; \
		else \
			echo "    PASS: $$doc exists and is non-empty"; \
		fi; \
	done; \
	if [ $$fail -ne 0 ]; then exit 1; fi
	@echo ""
	@echo "==> check-t1 PASSED"

check-t2: ## T2 quality gates (not yet implemented)
	@echo "T2 not implemented yet; see .omc/specs/deep-interview-pre-pi-prep.md"

clean: ## No-op at T1
	@echo "Nothing to clean at T1."

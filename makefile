# Makefile for machine-rites dotfiles management
.PHONY: help install update doctor backup test clean lint apply diff status push rollback ci-setup ci-test

REPO_DIR := $(shell pwd)
CHEZMOI_SRC := $(REPO_DIR)/.chezmoi
SHELL := /bin/bash

# Colors
GREEN := \033[1;32m
YELLOW := \033[1;33m
RED := \033[1;31m
NC := \033[0m

# Default target
help: ## Show this help message
	@echo "machine-rites - Dotfiles Management"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $1, $2}'

install: ## Run the bootstrap script
	@echo "$(GREEN)Running bootstrap...$(NC)"
	@bash bootstrap_machine_rites.sh

install-unattended: ## Run bootstrap in unattended mode
	@echo "$(GREEN)Running unattended bootstrap...$(NC)"
	@bash bootstrap_machine_rites.sh --unattended

update: ## Update dotfiles from repo
	@echo "$(GREEN)Updating dotfiles...$(NC)"
	@git pull --ff-only || echo "$(YELLOW)Warning: Could not fast-forward$(NC)"
	@chezmoi apply || echo "$(RED)Error: Chezmoi apply failed$(NC)"
	@pre-commit autoupdate || echo "$(YELLOW)Warning: Pre-commit update failed$(NC)"

doctor: ## Run health check
	@bash tools/doctor.sh

backup: ## Backup pass store
	@bash tools/backup-pass.sh

test: lint ## Run all tests
	@echo "$(GREEN)Running syntax checks...$(NC)"
	@bash -n bootstrap_machine_rites.sh || exit 1
	@for f in tools/*.sh; do \
		echo "  Checking $f..."; \
		bash -n "$f" || exit 1; \
	done
	@echo "$(GREEN)Running pre-commit checks...$(NC)"
	@pre-commit run --all-files || echo "$(YELLOW)Warning: Some pre-commit checks failed$(NC)"

lint: ## Run shellcheck on all scripts
	@echo "$(GREEN)Running shellcheck...$(NC)"
	@find . -name "*.sh" -type f -not -path "./.git/*" -not -path "./backups/*" -print0 | \
		xargs -0 shellcheck --severity=warning || echo "$(YELLOW)Warning: ShellCheck found issues$(NC)"

apply: ## Apply chezmoi changes
	@chezmoi --source $(CHEZMOI_SRC) apply

diff: ## Show pending chezmoi changes
	@chezmoi --source $(CHEZMOI_SRC) diff

status: ## Show chezmoi status
	@chezmoi --source $(CHEZMOI_SRC) status

clean: ## Clean backup files older than 7 days
	@echo "$(GREEN)Cleaning old backups...$(NC)"
	@find $(HOME) -maxdepth 1 -name "dotfiles-backup-*" -type d -mtime +7 -exec rm -rf {} \; 2>/dev/null || true
	@find $(REPO_DIR)/backups -name "*.gpg" -type f -mtime +30 -exec rm -f {} \; 2>/dev/null || true
	@echo "Cleaned backups older than 7 days"

secrets-add: ## Add a secret to pass (usage: make secrets-add KEY=github_token)
	@if [ -z "$(KEY)" ]; then \
		echo "$(RED)Usage: make secrets-add KEY=<secret_name>$(NC)"; \
		exit 1; \
	fi
	@echo "Enter value for $(KEY):"
	@pass insert personal/$(KEY)

secrets-list: ## List all secrets in pass
	@pass ls personal/ 2>/dev/null || echo "$(YELLOW)Pass not initialized$(NC)"

secrets-backup: ## Create encrypted backup of pass store
	@bash tools/backup-pass.sh

rollback: ## Show available backups for rollback
	@echo "$(GREEN)Available backups:$(NC)"
	@ls -dt $(HOME)/dotfiles-backup-* 2>/dev/null | head -10 || echo "  No backups found"
	@echo ""
	@echo "To rollback, run the rollback.sh script in the backup directory"
	@echo "Example: ~/dotfiles-backup-TIMESTAMP/rollback.sh"

push: test ## Test and push changes to git
	@echo "$(GREEN)Running tests before push...$(NC)"
	@$(MAKE) test
	@echo "$(GREEN)Committing and pushing...$(NC)"
	@git add -A
	@git diff --cached --quiet || git commit -m "chore: update dotfiles [skip ci]"
	@git push || echo "$(RED)Push failed$(NC)"

check-versions: ## Check tool versions
	@echo "$(GREEN)Checking tool versions:$(NC)"
	@for tool in bash git chezmoi pass gitleaks pre-commit gpg age ssh; do \
		printf "  %-12s : " "$tool"; \
		if command -v $tool >/dev/null 2>&1; then \
			$tool --version 2>/dev/null | head -1 || echo "installed"; \
		else \
			echo "$(RED)MISSING$(NC)"; \
		fi \
	done

ssh-setup: ## Generate SSH key if needed
	@bash -c "source ~/.bashrc.d/35-ssh.sh && ensure_ssh_key"

gpg-setup: ## Setup GPG key for pass
	@if ! gpg --list-secret-keys 2>/dev/null | grep -q '^sec'; then \
		echo "$(GREEN)Generating GPG key...$(NC)"; \
		gpg --full-generate-key; \
	else \
		echo "GPG key already exists"; \
	fi

# CI/CD targets
ci-setup: ## Setup CI environment (for GitHub Actions)
	@sudo apt-get update -y
	@sudo apt-get install -y shellcheck
	@sh -c "$(curl -fsLS get.chezmoi.io)" -- -b /usr/local/bin

ci-test: ## Run CI tests
	@test -d $(CHEZMOI_SRC) || { echo "$(RED)Error: .chezmoi source not found$(NC)"; exit 1; }
	@chezmoi --source $(CHEZMOI_SRC) apply --dry-run
	@shellcheck bootstrap_machine_rites.sh tools/*.sh
	@pre-commit run --all-files

# Development helpers
dev-clean: ## Remove all generated files (dangerous!)
	@echo "$(RED)Warning: This will remove all generated configs!$(NC)"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $REPLY =~ ^[Yy]$ ]]; then \
		rm -rf ~/.bashrc.d ~/.config/chezmoi; \
		echo "Cleaned"; \
	fi

dev-reset: ## Reset to latest repo state
	@git fetch origin
	@git reset --hard origin/main || git reset --hard origin/master
	@$(MAKE) apply

.DEFAULT_GOAL := help
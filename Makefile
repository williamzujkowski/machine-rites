# =============================================================================
# Docker Testing Infrastructure for machine-rites
# =============================================================================
# Purpose: Build automation, testing, and Docker operations
# Usage: make [target] [DISTRO=distro] [TEST=test]

# Project configuration
PROJECT_NAME := machine-rites
PROJECT_ROOT := $(shell pwd)

# Docker configuration
DOCKER_DIR := $(PROJECT_ROOT)/docker
COMPOSE_FILE := $(PROJECT_ROOT)/docker-compose.test.yml
SUPPORTED_DISTROS := ubuntu-24 ubuntu-22 debian-12
DEFAULT_DISTRO := ubuntu-24
DISTRO ?= $(DEFAULT_DISTRO)
TEST_TYPES := unit integration bootstrap all
TEST ?= all
DOCKER_BUILDKIT ?= 1

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
NC := \033[0m

# Colors for Docker output
DOCKER_RED := \033[0;31m
DOCKER_GREEN := \033[0;32m
DOCKER_YELLOW := \033[1;33m
DOCKER_BLUE := \033[0;34m
DOCKER_NC := \033[0m

# Logging functions
define log_info
	@echo -e "$(BLUE)[INFO]$(NC) $(1)"
endef

define log_success
	@echo -e "$(GREEN)[SUCCESS]$(NC) $(1)"
endef

define log_warn
	@echo -e "$(YELLOW)[WARN]$(NC) $(1)"
endef

define log_error
	@echo -e "$(RED)[ERROR]$(NC) $(1)"
endef

# Docker helper functions
define docker_log_info
	@echo -e "$(DOCKER_BLUE)[DOCKER-INFO]$(DOCKER_NC) $(1)"
endef

define docker_log_success
	@echo -e "$(DOCKER_GREEN)[DOCKER-SUCCESS]$(DOCKER_NC) $(1)"
endef

define docker_log_warn
	@echo -e "$(DOCKER_YELLOW)[DOCKER-WARN]$(DOCKER_NC) $(1)"
endef

define docker_log_error
	@echo -e "$(DOCKER_RED)[DOCKER-ERROR]$(DOCKER_NC) $(1)"
endef

define validate_distro
	@if [ "$(DISTRO)" != "all" ] && ! echo "$(SUPPORTED_DISTROS)" | grep -q "$(DISTRO)"; then \
		$(call docker_log_error,"Invalid DISTRO: $(DISTRO). Supported: $(SUPPORTED_DISTROS) all"); \
		exit 1; \
	fi
endef

define check_docker
	@if ! command -v docker >/dev/null 2>&1; then \
		$(call docker_log_error,"Docker is not installed or not in PATH"); \
		exit 1; \
	fi
	@if ! docker info >/dev/null 2>&1; then \
		$(call docker_log_error,"Docker daemon is not running"); \
		exit 1; \
	fi
endef

define check_compose
	@if ! command -v docker-compose >/dev/null 2>&1; then \
		$(call docker_log_error,"Docker Compose is not installed or not in PATH"); \
		exit 1; \
	fi
endef

.PHONY: help
help: ## Show this help message
	@echo "Machine-Rites Build System"
	@echo "=========================="
	@echo ""
	@echo "Usage: make [target] [DISTRO=distro] [TEST=test]"
	@echo ""
	@echo "Docker Targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "docker-|build-|test-|validate-"
	@echo ""
	@echo "Development Targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -vE "docker-|build-|test-|validate-|help"
	@echo ""
	@echo "Parameters:"
	@echo "  DISTRO          Docker distro ($(SUPPORTED_DISTROS), all) [default: $(DEFAULT_DISTRO)]"
	@echo "  TEST            Test type ($(TEST_TYPES)) [default: all]"
	@echo ""
	@echo "Examples:"
	@echo "  make docker-build DISTRO=ubuntu-24"
	@echo "  make docker-test DISTRO=debian-12 TEST=bootstrap"
	@echo "  make docker-test-all"

# =============================================================================
# Docker Targets
# =============================================================================

.PHONY: docker-validate
docker-validate: ## Validate Docker environment setup
	$(call check_docker)
	$(call check_compose)
	$(call log_info,"Validating Docker environment...")
	@$(DOCKER_DIR)/validate-environment.sh

.PHONY: docker-build
docker-build: ## Build Docker images for testing (DISTRO=distro|all)
	$(call validate_distro)
	$(call check_docker)
	$(call check_compose)
	$(call log_info,"Building Docker images for: $(DISTRO)")
	@export DOCKER_BUILDKIT=$(DOCKER_BUILDKIT) && \
	if [ "$(DISTRO)" = "all" ]; then \
		for distro in $(SUPPORTED_DISTROS); do \
			$(call log_info,"Building $$distro..."); \
			docker-compose -f $(COMPOSE_FILE) build --parallel $$distro || exit 1; \
		done; \
	else \
		docker-compose -f $(COMPOSE_FILE) build $(DISTRO); \
	fi
	$(call log_success,"Docker build complete")

.PHONY: docker-build-nocache
docker-build-nocache: ## Build Docker images without cache (DISTRO=distro|all)
	$(call validate_distro)
	$(call check_docker)
	$(call check_compose)
	$(call log_info,"Building Docker images without cache for: $(DISTRO)")
	@export DOCKER_BUILDKIT=$(DOCKER_BUILDKIT) && \
	if [ "$(DISTRO)" = "all" ]; then \
		for distro in $(SUPPORTED_DISTROS); do \
			$(call log_info,"Building $$distro..."); \
			docker-compose -f $(COMPOSE_FILE) build --no-cache $$distro || exit 1; \
		done; \
	else \
		docker-compose -f $(COMPOSE_FILE) build --no-cache $(DISTRO); \
	fi
	$(call log_success,"Docker build complete")

.PHONY: docker-up
docker-up: ## Start Docker containers (DISTRO=distro|all)
	$(call validate_distro)
	$(call check_compose)
	$(call log_info,"Starting containers: $(DISTRO)")
	@if [ "$(DISTRO)" = "all" ]; then \
		docker-compose -f $(COMPOSE_FILE) up -d; \
	else \
		docker-compose -f $(COMPOSE_FILE) up -d $(DISTRO); \
	fi
	$(call log_success,"Containers started")

.PHONY: docker-down
docker-down: ## Stop and remove Docker containers
	$(call check_compose)
	$(call log_info,"Stopping containers...")
	@docker-compose -f $(COMPOSE_FILE) down --volumes --remove-orphans
	$(call log_success,"Containers stopped")

.PHONY: docker-shell
docker-shell: ## Open interactive shell in container (DISTRO=distro)
	$(call validate_distro)
	$(call check_compose)
	@if [ "$(DISTRO)" = "all" ]; then \
		$(call log_error,"Cannot open shell for 'all'. Specify a single distro."); \
		exit 1; \
	fi
	$(call log_info,"Opening shell in $(DISTRO) container...")
	@$(DOCKER_DIR)/test-harness.sh shell $(DISTRO)

.PHONY: docker-test
docker-test: ## Run tests in Docker container (DISTRO=distro, TEST=test)
	$(call validate_distro)
	$(call log_info,"Running $(TEST) tests on $(DISTRO)...")
	@$(DOCKER_DIR)/test-harness.sh test $(DISTRO) $(TEST)

.PHONY: docker-test-parallel
docker-test-parallel: ## Run tests in parallel across all distros (TEST=test)
	$(call log_info,"Running $(TEST) tests in parallel...")
	@$(DOCKER_DIR)/test-harness.sh --parallel test all $(TEST)

.PHONY: docker-test-all
docker-test-all: ## Run complete test suite across all distros
	$(call log_info,"Running complete test suite...")
	@$(DOCKER_DIR)/test-harness.sh all

.PHONY: docker-status
docker-status: ## Show Docker container status
	$(call check_compose)
	@$(DOCKER_DIR)/test-harness.sh status

.PHONY: docker-logs
docker-logs: ## Show Docker container logs (DISTRO=distro|all)
	$(call check_compose)
	@$(DOCKER_DIR)/test-harness.sh logs $(DISTRO)

.PHONY: docker-health
docker-health: ## Check Docker container health
	$(call check_compose)
	@$(DOCKER_DIR)/test-harness.sh health

.PHONY: docker-clean
docker-clean: ## Clean up Docker resources
	$(call check_compose)
	$(call log_info,"Cleaning up Docker resources...")
	@$(DOCKER_DIR)/test-harness.sh clean
	$(call log_success,"Docker cleanup complete")

.PHONY: docker-clean-all
docker-clean-all: ## Force clean all Docker resources including images
	$(call check_compose)
	$(call log_info,"Force cleaning all Docker resources...")
	@FORCE=true $(DOCKER_DIR)/test-harness.sh clean
	$(call log_success,"Docker force cleanup complete")

# =============================================================================
# Testing Targets
# =============================================================================

.PHONY: test
test: ## Run all tests
	$(call log_info,"Running all tests...")
	@if [ -f "$(PROJECT_ROOT)/tests/run_tests.sh" ]; then \
		$(PROJECT_ROOT)/tests/run_tests.sh; \
	else \
		$(call log_warn,"No test runner found. Using Docker tests..."); \
		make docker-test DISTRO=all TEST=all; \
	fi

.PHONY: test-unit
test-unit: ## Run unit tests
	$(call log_info,"Running unit tests...")
	@if [ -d "$(PROJECT_ROOT)/tests/unit" ]; then \
		for test in "$(PROJECT_ROOT)"/tests/unit/*.sh; do \
			[ -f "$$test" ] && bash "$$test"; \
		done; \
	else \
		make docker-test DISTRO=$(DEFAULT_DISTRO) TEST=unit; \
	fi

.PHONY: test-integration
test-integration: ## Run integration tests
	$(call log_info,"Running integration tests...")
	@if [ -d "$(PROJECT_ROOT)/tests/integration" ]; then \
		for test in "$(PROJECT_ROOT)"/tests/integration/*.sh; do \
			[ -f "$$test" ] && bash "$$test"; \
		done; \
	else \
		make docker-test DISTRO=$(DEFAULT_DISTRO) TEST=integration; \
	fi

.PHONY: test-bootstrap
test-bootstrap: ## Test bootstrap functionality
	$(call log_info,"Testing bootstrap...")
	@make docker-test DISTRO=$(DEFAULT_DISTRO) TEST=bootstrap

# =============================================================================
# Validation Targets
# =============================================================================

.PHONY: validate
validate: validate-environment validate-syntax validate-structure ## Run all validations

.PHONY: validate-environment
validate-environment: ## Validate development environment
	$(call log_info,"Validating environment...")
	@$(DOCKER_DIR)/validate-environment.sh

.PHONY: validate-syntax
validate-syntax: ## Validate shell script syntax
	$(call log_info,"Validating shell script syntax...")
	@if command -v shellcheck >/dev/null 2>&1; then \
		find "$(PROJECT_ROOT)" -name "*.sh" -type f -exec shellcheck {} + || \
		echo -e "$(YELLOW)[WARN]$(NC) shellcheck found issues"; \
	else \
		echo -e "$(YELLOW)[WARN]$(NC) shellcheck not available"; \
	fi

.PHONY: validate-structure
validate-structure: ## Validate project structure
	$(call log_info,"Validating project structure...")
	@for file in docker/ubuntu-24.04/Dockerfile docker/ubuntu-22.04/Dockerfile docker/debian-12/Dockerfile docker-compose.test.yml docker/test-harness.sh Makefile; do \
		if [ ! -f "$(PROJECT_ROOT)/$$file" ]; then \
			$(call log_error,"Missing required file: $$file"); \
			exit 1; \
		fi; \
	done
	$(call log_success,"Project structure validation complete")

# =============================================================================
# Development Targets
# =============================================================================

.PHONY: setup
setup: ## Setup development environment
	$(call log_info,"Setting up development environment...")
	@make validate-environment
	@make docker-build DISTRO=all
	$(call log_success,"Development environment setup complete")

.PHONY: dev-shell
dev-shell: ## Start development shell with mounted volumes
	@make docker-shell DISTRO=$(DEFAULT_DISTRO)

.PHONY: lint
lint: ## Run linting tools
	$(call log_info,"Running linting tools...")
	@if command -v shellcheck >/dev/null 2>&1; then \
		find "$(PROJECT_ROOT)" -name "*.sh" -type f -exec shellcheck {} +; \
	else \
		echo -e "$(YELLOW)[WARN]$(NC) shellcheck not installed"; \
	fi
	@if command -v hadolint >/dev/null 2>&1; then \
		find "$(PROJECT_ROOT)/docker" -name "Dockerfile" -exec hadolint {} +; \
	else \
		echo -e "$(YELLOW)[WARN]$(NC) hadolint not installed"; \
	fi

.PHONY: format
format: ## Format shell scripts
	$(call log_info,"Formatting shell scripts...")
	@if command -v shfmt >/dev/null 2>&1; then \
		find "$(PROJECT_ROOT)" -name "*.sh" -type f -exec shfmt -w -i 4 {} +; \
	else \
		$(call log_warn,"shfmt not installed - skipping formatting"); \
	fi

.PHONY: deps-check
deps-check: ## Check for required dependencies
	$(call log_info,"Checking dependencies...")
	@bash -c 'for dep in docker docker-compose bash make git; do \
		if command -v "$$dep" >/dev/null 2>&1; then \
			echo -e "$(GREEN)[SUCCESS]$(NC) ✓ $$dep"; \
		else \
			echo -e "$(RED)[ERROR]$(NC) ✗ $$dep (required)"; \
		fi; \
	done'
	@bash -c 'for dep in shellcheck hadolint shfmt bats; do \
		if command -v "$$dep" >/dev/null 2>&1; then \
			echo -e "$(GREEN)[SUCCESS]$(NC) ✓ $$dep (optional)"; \
		else \
			echo -e "$(YELLOW)[WARN]$(NC) ⚠ $$dep (optional)"; \
		fi; \
	done'

.PHONY: clean
clean: docker-clean ## Clean up build artifacts and temporary files
	$(call log_info,"Cleaning up build artifacts...")
	@find "$(PROJECT_ROOT)" -name "*.tmp" -type f -delete 2>/dev/null || true
	@find "$(PROJECT_ROOT)" -name "*.log" -type f -delete 2>/dev/null || true
	@rm -rf "$(PROJECT_ROOT)/test-results" 2>/dev/null || true
	@rm -rf "$(PROJECT_ROOT)/coverage" 2>/dev/null || true
	$(call log_success,"Cleanup complete")

.PHONY: info
info: ## Show project information
	@echo "Project Information"
	@echo "==================="
	@echo "Name: $(PROJECT_NAME)"
	@echo "Root: $(PROJECT_ROOT)"
	@echo "Docker Dir: $(DOCKER_DIR)"
	@echo "Compose File: $(COMPOSE_FILE)"
	@echo ""
	@echo "Supported Distros: $(SUPPORTED_DISTROS)"
	@echo "Default Distro: $(DEFAULT_DISTRO)"
	@echo "Test Types: $(TEST_TYPES)"
	@echo ""
	@echo "Current Settings:"
	@echo "  DISTRO: $(DISTRO)"
	@echo "  TEST: $(TEST)"
	@echo "  DOCKER_BUILDKIT: $(DOCKER_BUILDKIT)"

# =============================================================================
# CI/CD Targets
# =============================================================================

.PHONY: ci-setup
ci-setup: ## Setup for CI environment
	$(call log_info,"Setting up CI environment...")
	@make deps-check
	@make validate-environment
	@make docker-build DISTRO=all

.PHONY: ci-test
ci-test: ## Run CI test suite
	$(call log_info,"Running CI test suite...")
	@make docker-test-parallel TEST=all

.PHONY: ci-validate
ci-validate: ## Run CI validation suite
	$(call log_info,"Running CI validation...")
	@make validate
	@make lint

# =============================================================================
# Default Target
# =============================================================================

.DEFAULT_GOAL := help
# =============================================================================
# Docker Testing Infrastructure Targets
# =============================================================================
# Include this file in your main Makefile with: include docker/docker-targets.mk

# Docker configuration
DOCKER_DIR := $(shell pwd)/docker
COMPOSE_FILE := $(shell pwd)/docker-compose.test.yml
SUPPORTED_DISTROS := ubuntu-24 ubuntu-22 debian-12
DEFAULT_DISTRO := ubuntu-24
DISTRO ?= $(DEFAULT_DISTRO)
TEST_TYPES := unit integration bootstrap all
TEST ?= all
DOCKER_BUILDKIT ?= 1

# Colors for Docker output
DOCKER_RED := \033[0;31m
DOCKER_GREEN := \033[0;32m
DOCKER_YELLOW := \033[1;33m
DOCKER_BLUE := \033[0;34m
DOCKER_NC := \033[0m

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

# =============================================================================
# Docker Testing Targets
# =============================================================================

.PHONY: docker-validate
docker-validate: ## Validate Docker environment setup
	$(call check_docker)
	$(call check_compose)
	$(call docker_log_info,"Validating Docker environment...")
	@$(DOCKER_DIR)/validate-environment.sh

.PHONY: docker-build
docker-build: ## Build Docker images for testing (DISTRO=distro|all)
	$(call validate_distro)
	$(call check_docker)
	$(call check_compose)
	$(call docker_log_info,"Building Docker images for: $(DISTRO)")
	@export DOCKER_BUILDKIT=$(DOCKER_BUILDKIT) && \
	if [ "$(DISTRO)" = "all" ]; then \
		for distro in $(SUPPORTED_DISTROS); do \
			$(call docker_log_info,"Building $$distro..."); \
			docker-compose -f $(COMPOSE_FILE) build $$distro || exit 1; \
		done; \
	else \
		docker-compose -f $(COMPOSE_FILE) build $(DISTRO); \
	fi
	$(call docker_log_success,"Docker build complete")

.PHONY: docker-build-nocache
docker-build-nocache: ## Build Docker images without cache (DISTRO=distro|all)
	$(call validate_distro)
	$(call check_docker)
	$(call check_compose)
	$(call docker_log_info,"Building Docker images without cache for: $(DISTRO)")
	@export DOCKER_BUILDKIT=$(DOCKER_BUILDKIT) && \
	if [ "$(DISTRO)" = "all" ]; then \
		for distro in $(SUPPORTED_DISTROS); do \
			$(call docker_log_info,"Building $$distro..."); \
			docker-compose -f $(COMPOSE_FILE) build --no-cache $$distro || exit 1; \
		done; \
	else \
		docker-compose -f $(COMPOSE_FILE) build --no-cache $(DISTRO); \
	fi
	$(call docker_log_success,"Docker build complete")

.PHONY: docker-up
docker-up: ## Start Docker containers (DISTRO=distro|all)
	$(call validate_distro)
	$(call check_compose)
	$(call docker_log_info,"Starting containers: $(DISTRO)")
	@if [ "$(DISTRO)" = "all" ]; then \
		docker-compose -f $(COMPOSE_FILE) up -d; \
	else \
		docker-compose -f $(COMPOSE_FILE) up -d $(DISTRO); \
	fi
	$(call docker_log_success,"Containers started")

.PHONY: docker-down
docker-down: ## Stop and remove Docker containers
	$(call check_compose)
	$(call docker_log_info,"Stopping containers...")
	@docker-compose -f $(COMPOSE_FILE) down --volumes --remove-orphans
	$(call docker_log_success,"Containers stopped")

.PHONY: docker-shell
docker-shell: ## Open interactive shell in container (DISTRO=distro)
	$(call validate_distro)
	$(call check_compose)
	@if [ "$(DISTRO)" = "all" ]; then \
		$(call docker_log_error,"Cannot open shell for 'all'. Specify a single distro."); \
		exit 1; \
	fi
	$(call docker_log_info,"Opening shell in $(DISTRO) container...")
	@$(DOCKER_DIR)/test-harness.sh shell $(DISTRO)

.PHONY: docker-test
docker-test: ## Run tests in Docker container (DISTRO=distro, TEST=test)
	$(call validate_distro)
	$(call docker_log_info,"Running $(TEST) tests on $(DISTRO)...")
	@$(DOCKER_DIR)/test-harness.sh test $(DISTRO) $(TEST)

.PHONY: docker-test-parallel
docker-test-parallel: ## Run tests in parallel across all distros (TEST=test)
	$(call docker_log_info,"Running $(TEST) tests in parallel...")
	@$(DOCKER_DIR)/test-harness.sh --parallel test all $(TEST)

.PHONY: docker-test-all
docker-test-all: ## Run complete test suite across all distros
	$(call docker_log_info,"Running complete test suite...")
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
	$(call docker_log_info,"Cleaning up Docker resources...")
	@$(DOCKER_DIR)/test-harness.sh clean
	$(call docker_log_success,"Docker cleanup complete")

.PHONY: docker-clean-all
docker-clean-all: ## Force clean all Docker resources including images
	$(call check_compose)
	$(call docker_log_info,"Force cleaning all Docker resources...")
	@FORCE=true $(DOCKER_DIR)/test-harness.sh clean
	$(call docker_log_success,"Docker force cleanup complete")

.PHONY: docker-info
docker-info: ## Show Docker infrastructure information
	@echo "Docker Testing Infrastructure"
	@echo "============================="
	@echo "Compose File: $(COMPOSE_FILE)"
	@echo "Docker Dir: $(DOCKER_DIR)"
	@echo "Supported Distros: $(SUPPORTED_DISTROS)"
	@echo "Default Distro: $(DEFAULT_DISTRO)"
	@echo "Test Types: $(TEST_TYPES)"
	@echo ""
	@echo "Current Settings:"
	@echo "  DISTRO: $(DISTRO)"
	@echo "  TEST: $(TEST)"
	@echo "  DOCKER_BUILDKIT: $(DOCKER_BUILDKIT)"
	@echo ""
	@echo "Available Commands:"
	@echo "  make docker-validate    - Validate environment"
	@echo "  make docker-build       - Build test images"
	@echo "  make docker-test        - Run tests"
	@echo "  make docker-shell       - Interactive shell"
	@echo "  make docker-clean       - Cleanup resources"
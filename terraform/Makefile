-include ../.env

ENV ?= staging
WS  ?=
AUTO_APPROVE ?= $(if $(filter staging,$(ENV)),1,0)
APPLY_ORDER := services kms vpc cloud-nat firewall kubernetes-engine artifact-registry cloud-storage pubsub log-router audit-logs secret-manager argocd-bootstrap

ifeq ($(strip $(GITOPS_REPO_URL)),)
GITOPS_REPO_URL := $(shell git remote get-url origin 2>/dev/null | sed -E 's|^git@([^:]+):|https://\1/|')
endif

export TF_VAR_project_id      := $(PROJECT_ID)
export TF_VAR_gitops_repo_url := $(GITOPS_REPO_URL)

TF_APPROVE := $(if $(filter 1,$(AUTO_APPROVE)),-auto-approve,)
WS_DIR      = environments/$(ENV)/$(1)

.PHONY: check-project init validate plan apply apply-all converge teardown check-leaks

check-project:
	@test -n "$(PROJECT_ID)" || { echo "ERROR: PROJECT_ID is empty — run: cp ../.env.example ../.env and set PROJECT_ID"; exit 1; }
	@active="$$(gcloud config get-value project 2>/dev/null)"; \
	if [ "$$active" != "$(PROJECT_ID)" ]; then \
		echo "ERROR: active gcloud project '$$active' != PROJECT_ID '$(PROJECT_ID)' in .env. Run: gcloud config set project $(PROJECT_ID)"; exit 1; \
	fi
	@if grep -l -E '^[[:space:]]*project_id[[:space:]]*=' environments/$(ENV)/*/$(ENV).tfvars 2>/dev/null; then \
		echo "ERROR: project_id is set in the tfvars above — remove it (public repo); it comes from .env"; exit 1; \
	fi
	@echo "OK: project $(PROJECT_ID)"

init:
	@for ws in $(APPLY_ORDER); do echo "== init $$ws"; terraform -chdir=$(call WS_DIR,$$ws) init -input=false || exit 1; done

validate:
	terraform fmt -check -recursive
	@for ws in $(APPLY_ORDER); do echo "== validate $$ws"; terraform -chdir=$(call WS_DIR,$$ws) validate || exit 1; done

plan: check-project
	@test -n "$(WS)" || { echo "Usage: make plan WS=<workspace>"; exit 1; }
	terraform -chdir=$(call WS_DIR,$(WS)) plan -var-file=$(ENV).tfvars

apply: check-project
	@test -n "$(WS)" || { echo "Usage: make apply WS=<workspace>"; exit 1; }
	terraform -chdir=$(call WS_DIR,$(WS)) apply -var-file=$(ENV).tfvars $(TF_APPROVE)

apply-all: check-project
	@for ws in $(APPLY_ORDER); do \
		echo ""; echo "================ apply $$ws ================"; \
		terraform -chdir=$(call WS_DIR,$$ws) apply -var-file=$(ENV).tfvars $(TF_APPROVE) || exit 1; \
	done
	@$(MAKE) --no-print-directory converge

converge: check-project
	ENV=$(ENV) PROJECT_ID=$(PROJECT_ID) ./scripts/converge.sh

teardown: check-project
	ENV=$(ENV) PROJECT_ID=$(PROJECT_ID) AUTO_APPROVE=$(AUTO_APPROVE) ./scripts/teardown.sh


check-leaks: check-project
	@number="$$(gcloud projects describe $(PROJECT_ID) --format='value(projectNumber)')"; \
	test -n "$$number" || { echo "ERROR: cannot read the project number"; exit 1; }; \
	hits="$$(cd .. && git ls-files -z --cached --others --exclude-standard | xargs -0 grep -lIE "$(PROJECT_ID)|$$number")"; \
	if [ -n "$$hits" ]; then echo "ERROR: project ID or number found in:"; echo "$$hits"; exit 1; fi; \
	echo "OK: no project ID or number in files Git tracks or would track"

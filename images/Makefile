-include ../.env

ENV           ?= staging
REGION        ?= asia-southeast2
IMAGE         := wazuh-gcp-collector
REGISTRY       = $(REGION)-docker.pkg.dev/$(PROJECT_ID)/$(ENV)-siem
KUSTOMIZATION := ../infrastructure/configs/wazuh/base/kustomization.yaml
TAG           := $(shell cat $(IMAGE)/Dockerfile $(IMAGE)/requirements.txt $(IMAGE)/patch_wodle.py | shasum -a 256 | cut -c1-8)

.PHONY: check-project tag release

check-project:
	@test -n "$(PROJECT_ID)" || { echo "ERROR: PROJECT_ID is empty — set it in ../.env"; exit 1; }
	@active="$$(gcloud config get-value project 2>/dev/null)"; \
	if [ "$$active" != "$(PROJECT_ID)" ]; then \
		echo "ERROR: active gcloud project '$$active' != PROJECT_ID '$(PROJECT_ID)' in .env"; exit 1; \
	fi

tag:
	@echo $(TAG)

release: check-project
	@if gcloud artifacts docker images describe "$(REGISTRY)/$(IMAGE):$(TAG)" >/dev/null 2>&1; then \
		echo "$(IMAGE):$(TAG) is already in Artifact Registry"; \
	else \
		gcloud auth configure-docker $(REGION)-docker.pkg.dev --quiet && \
		docker build --platform linux/amd64 -t "$(REGISTRY)/$(IMAGE):$(TAG)" $(IMAGE) && \
		docker push "$(REGISTRY)/$(IMAGE):$(TAG)"; \
	fi
	@sed -i.bak -e '/^  - name: $(IMAGE)$$/{n;s/newTag: .*/newTag: $(TAG)/;}' $(KUSTOMIZATION) && rm -f $(KUSTOMIZATION).bak
	@grep -A1 '^  - name: $(IMAGE)$$' $(KUSTOMIZATION) | grep -q 'newTag: $(TAG)$$' || { echo "ERROR: newTag $(TAG) not written to $(KUSTOMIZATION)"; exit 1; }
	@echo "$(IMAGE):$(TAG) released; commit $(KUSTOMIZATION)"

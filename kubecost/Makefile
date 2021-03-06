.DEFAULT_GOAL := deploy


COMPONENT_NAME          ?= kubecost
DOMAIN_NAME             ?= test.dev.superhub.io
NAMESPACE               ?= kubecost
HELM_REPO_URL           ?= https://kubecost.github.io/cost-analyzer/
HELM_REPO_NAME          ?= kubecost
HELM_CHART              ?= $(HELM_REPO_NAME)/cost-analyzer
VERSION                 ?= v1.59.0
AWS_DEFAULT_REGION      ?= us-east-2
HELM_HOME               ?= $(shell pwd)/.helm
TIMEOUT                 ?= 600


aws                ?= aws
kubectl            ?= kubectl --context="$(DOMAIN_NAME)" --namespace="$(NAMESPACE)"
helm               ?= helm2 --kube-context="$(DOMAIN_NAME)" --tiller-namespace="kube-system"
jq                 ?= jq

SPOT_DATA_ENABLED := $(if $(and $(SPOT_DATA_BUCKET_NAME), $(SPOT_DATA_BUCKET_REGION), $(SPOT_DATA_PREFIX)),true)

ifeq ($(SPOT_DATA_ENABLED),true)
    RESOLVE_AWS_ACCOUNT     := $(aws) sts get-caller-identity --query Account --output text
    HELM_ARGS_PROJECT_ID    := --set-string kubecostProductConfigs.projectID="`$(RESOLVE_AWS_ACCOUNT)`"
    HELM_ARGS_SPOT_DATA     := --values spot-data-feed.yaml
else
    SPOT_DATA_ENABLED:=
    HELM_ARGS_PROJECT_ID:=
    HELM_ARGS_SPOT_DATA:=
endif

deploy: init fetch purge prometheus install wait

init: $(HELM_HOME) charts
	$(helm) init --client-only --upgrade

$(HELM_HOME) charts:
	@rm -rf $@ && mkdir -p $@

fetch:
	$(helm) repo add kubecost $(HELM_REPO_URL)
	$(helm) fetch \
		--destination charts \
		--untar $(HELM_CHART) \
		--version $(VERSION)

purge:
	$(helm) list --deleted --failed -q --namespace $(NAMESPACE) | grep -E '^$(COMPONENT_NAME)$$' \
		&& $(helm) delete --purge $(COMPONENT_NAME) \
		|| exit 0

prometheus:
	$(MAKE) -C "$@"

install:
	$(kubectl) apply -f namespace.yaml

	if ! $(helm) list -q --namespace $(NAMESPACE) | grep -E '^$(COMPONENT_NAME)$$'; then \
		$(helm) install charts/$(notdir $(HELM_CHART)) \
			--name $(COMPONENT_NAME) \
			--namespace $(NAMESPACE) \
			--wait \
			--values values.yaml \
			$(HELM_ARGS_SPOT_DATA) \
			$(HELM_ARGS_PROJECT_ID) \
			--values prometheus.yaml \
			--version $(VERSION); \
	else \
		$(MAKE) upgrade; \
	fi

	$(kubectl) apply -f ingress.yaml

upgrade:
	$(helm) upgrade $(COMPONENT_NAME) charts/$(notdir $(HELM_CHART)) \
		--namespace $(NAMESPACE) \
		--wait \
		--values values.yaml \
		$(HELM_ARGS_SPOT_DATA) \
		$(HELM_ARGS_PROJECT_ID) \
		--values prometheus.yaml \
		--version $(VERSION)

wait:
	$(eval timeout=$(shell echo "`date +%s` + $(TIMEOUT)" | bc ))
	$(eval cost_analyzer_pod=$(kubectl) get pod -l app=cost-analyzer -o=json)
	$(eval check_conttainers=$(jq) '.items[]?.status.conditions[] | select(.type == "ContainersReady" and .status == "True")')
	@ echo "Waiting for Cost Analizer pod up and running"

	@ while [ `date +%s` -le "$(timeout)" ]; do \
		if [[ "`$(cost_analyzer_pod) | $(check_conttainers)`" ]]; then \
			echo " done"; \
			exit 0; \
		fi; \
		echo "still waiting..."; \
		sleep 8; \
	done; \
	echo " ERROR timeout $(TIMEOUT)sec"; \
	exit 1

undeploy: init destroy

destroy: TF_CLI_ARGS:=-destroy $(TF_CLI_ARGS)
destroy:
	- $(kubectl) delete -f ingress.yaml
	$(helm) list -q --namespace $(NAMESPACE) | grep -E '^$(COMPONENT_NAME)$$' && \
		$(helm) delete --purge $(COMPONENT_NAME) || exit 0
	$(MAKE) -C prometheus destroy

-include ../Mk/phonies
.PHONY: prometheus

.DEFAULT_GOAL := deploy

export AWS_DEFAULT_REGION      ?= us-east-2

terraform			?= terraform-v0.12
jq 					:= jq -cM
aws					?= aws
TMP					:= $(abspath .tmp)
WAIT_TIMEOUT		:= 1800
MIN_NUMB_NODES		?= 1

export TF_VAR_name             ?= $(error undefined env var TF_VAR_name)
export TF_VAR_s3_bucket        ?= $(error undefined env var TF_VAR_s3_bucket)
export TF_VAR_s3_bucket_region ?= $(error undefined env var TF_VAR_s3_bucket_region)
export TF_VAR_domain_name      ?= $(error undefined env var TF_VAR_domain_name)
export TF_VAR_subnet_ids       := $(shell echo '$(sort $(SUBNET_ID) $(SUBNET_IDS))' | tr ',' ' ' | xargs | $(jq) -R  'split(" ")')
export TF_VAR_sg_ids           := $(shell echo '$(SG_IDS)' | tr ',' ' ' | xargs | $(jq) -R 'split(" ")')
export TF_VAR_instance_size    := $(shell echo '$(INSTANCE_SIZE)' | tr ',' ' ' | xargs | $(jq) -R 'split(" ")')
export TF_VAR_cluster_tag      := $(shell echo $(TF_VAR_domain_name) | sed -e s/\\./-/)

export TF_DATA_DIR ?= .terraform/$(TF_VAR_name)
export TF_LOG_PATH ?= $(TF_DATA_DIR)/terraform.log

kubectl     ?= kubectl --context="$(TF_VAR_domain_name)"
TF_CLI_ARGS ?= -no-color -input=false
TFPLAN      := $(TF_DATA_DIR)/terraform.tfplan

VALID_NAME   = $(shell echo $(TF_VAR_name) | grep -Eq ^$(SHORT_NAME) && echo matched)


ifneq ($(VALID_NAME),matched)
$(error "shortName" parameter must be a prefix to "name" parameter $(TF_VAR_name))
endif


deploy: init import plan
	# workaround famous ignition provider bug
	$(MAKE) apply || \
		$(MAKE) import plan apply || \
		$(MAKE) import plan apply
	$(MAKE) kubernetes/nvidia-gpu-device-plugin.yml
	$(MAKE) wait

$(TF_DATA_DIR) $(TMP):
	@rm -rf $@ && mkdir -p $@

init: $(TF_DATA_DIR)
	$(terraform) init -get=true -force-copy $(TF_CLI_ARGS) \
        -backend=true -reconfigure \
        -backend-config="bucket=$(TF_VAR_s3_bucket)" \
        -backend-config="region=$(TF_VAR_s3_bucket_region)" \
        -backend-config="key=$(TF_VAR_domain_name)/k8s-mixed-worker-nodes/$(TF_VAR_name)/terraform.tfstate" \
        -backend-config="profile=$(AWS_PROFILE)"

plan:
	$(terraform) plan $(TF_CLI_ARGS) -refresh=true -out=$(TFPLAN)

refresh:
	$(terraform) refresh $(TF_CLI_ARGS)

apply:
	$(terraform) apply $(TF_CLI_ARGS) -auto-approve $(TFPLAN)

# we should make it a part of stack-k8s-aws? then what about eks?
kubernetes/%:
	$(kubectl) apply  -n kube-system -f $@

output:
	@$(terraform) output -no-color

undeploy: init destroy apply

destroy: TF_CLI_ARGS:=-destroy $(TF_CLI_ARGS)
destroy: plan

import: worker:=$(shell echo worker-$(TF_VAR_name) | cut -c 1-63)
import:
	-$(terraform) import $(TF_OPTS) aws_autoscaling_group.workers $(worker)

-include ../Mk/phonies

.PHONY: kubernetes/nvidia-gpu-device-plugin.yml

wait: $(TMP)
	$(eval current_time := date +%s)

	$(eval autoscaling_group_name := $(shell $(terraform) output autoscaling_group_name))
	$(eval jq_group_node_ids := $(jq) -r '.AutoScalingGroups[0].Instances[].InstanceId')

	$(eval resolve_aws_node_ids := $(aws) autoscaling describe-auto-scaling-groups --auto-scaling-group-names  $(autoscaling_group_name) \
			| $(jq_group_node_ids) | xargs)

	$(eval jq_status_nodes_expr := 'select(.status.conditions[] | .type == "Ready" and .status == $$$$readyStatus) | .metadata.name')

	$(eval jq_group_node_names := $(jq) '.items[] | select( .spec.providerID | split("/") | last | IN($$$$ARGS.positional[]))')

	@ echo "Waiting for cluster nodes within $(autoscaling_group_name) to boot"

	$(eval timeout := $(shell echo "`$(current_time)` + $(WAIT_TIMEOUT)" | bc ))

	@ while [ `$(current_time)` -le "$(timeout)" ]; do \
		aws_node_ids="`$(resolve_aws_node_ids)`"; \
		nodes_json="$(TMP)/debug-`$(current_time)`.json"; \
		$(kubectl) get nodes -o json > $$nodes_json; \
		asg_group_nodes="`$(jq_group_node_names) --args $$aws_node_ids < $$nodes_json`"; \
		ready="`echo $$asg_group_nodes | $(jq) -r --arg  readyStatus True $(jq_status_nodes_expr) | xargs`"; \
		not_ready="`echo $$asg_group_nodes | $(jq) -r --arg  readyStatus False $(jq_status_nodes_expr) | xargs`"; \
		test -n "$$ready" && \
			echo "Ready nodes [$$ready] expecting at least $(MIN_NUMB_NODES)";\
		test -n "$$not_ready" && \
			echo "Not ready nodes [$$not_ready]";\
		ready_count="`echo $$ready | wc -w | xargs`"; \
		not_ready_count="`echo $$not_ready | wc -w | xargs`"; \
		up_count="`echo $$ready_count + $$not_ready_count | bc`"; \
		if [ "$$ready_count" -ge '$(MIN_NUMB_NODES)' ]; then \
			echo "Succeeded (ready: $$ready_count; expecting at least: $(MIN_NUMB_NODES))"; \
			exit 0; \
		fi; \
		echo "Still waiting (nodes up: $$up_count; ready: $$ready_count; expecting at least: $(MIN_NUMB_NODES))..."; \
		sleep 8; \
	done; \
	echo "ERROR timeout $(WAIT_TIMEOUT)sec"; \
	exit 1;

	@ echo "-- Workers group is ready --"

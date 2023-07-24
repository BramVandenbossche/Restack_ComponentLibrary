#!/bin/bash

# Parameters
NODE_LIST="$1"
IP_LIST="$2"
KUBECONFIG="$3"
USER="$4"
UPDATE_COMMAND="$5"
SSH_PRIVATE_KEY="${6:-id_rsa}"

IFS=', ' read -r -a KUBE_NODE_LIST <<< "$NODE_LIST"
IFS=', ' read -r -a KUBE_NODE_IP_LIST <<< "$IP_LIST"

# Vars
messages=()

# Functions
echo_message() {
  local message="$1"
  local error="$2"
  local componentname="kubernetes-update"
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")

  echo '{"timestamp": "'"$timestamp"'","componentName": "'"$componentname"'","message": "'"$message"'","error": '$error'}'
}

end_script() {
  local status="$1"

  for ((i=0; i<${#messages[@]}; i++)); do
    echo "${messages[i]}"
  done

  exit $status
}

drain_node() {
  local node="$1"
  messages+=("$(echo_message "Draining node: $node" false)")
  drain_output=$(KUBECONFIG="$KUBECONFIG" kubectl drain "$node" --ignore-daemonsets --delete-emptydir-data --force --grace-period=60 2>&1)
  local exit_status=$?
  if [[ $exit_status -ne 0 ]]; then
    messages+=("$(echo_message "Failed to drain node: $node" true)")
    messages+=("$(echo_message "$drain_output" true)")
    end_script 1
  else
    messages+=("$(echo_message "Node drained: $node" false)")
  fi
}

uncordon_node() {
  local node="$1"
  messages+=("$(echo_message "Uncordoning node: $node" false)")
  uncordon_output=$(KUBECONFIG="$KUBECONFIG" kubectl uncordon "$node" 2>&1)
  local exit_status=$?
  if [[ $exit_status -ne 0 ]]; then
    messages+=("$(echo_message "Failed to uncordon node: $node" true)")
    messages+=("$(echo_message "$uncordon_output" true)")
  else
    messages+=("$(echo_message "Node uncordoned: $node" false)")
  fi
}

update_node() {
  local node="$1"
  messages+=("$(echo_message "Updating node: $node" false)")
  update_output=$(ssh -i "$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no "$USER"@"$node" "$UPDATE_COMMAND" 2>&1)
  local exit_status=$?
  if [[ $exit_status -ne 0 ]]; then
      messages+=("$(echo_message "Node update failed. Error: $update_output" true)")
      end_script 1
  else
      messages+=("$(echo_message "Node updated: $node" false)")
  fi
}

# Run
for i in "${!KUBE_NODE_LIST[@]}"; do
  node="${KUBE_NODE_LIST[$i]}"
  ip="${KUBE_NODE_IP_LIST[$i]}"
  drain_node "$node"
  sleep 10
  update_node "$ip"
  sleep 10
  uncordon_node "$node"
  sleep 10
done
messages+=("$(echo_message "All nodes updated!" false)")
end_script 0

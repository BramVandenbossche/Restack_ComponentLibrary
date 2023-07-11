#!/usr/bin/env bash

# Parameters
VM_CT_ID="$1"          
PROXMOX_HOST="$2"  
USER="$3"
SSH_PRIVATE_KEY="${4:-id_rsa}"

## Vars
messages=()

echo_message() {
  local message="$1"
  local error="$2"
  local componentname="update-debian"
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")

  echo '{
      "timestamp": "'"$timestamp"'",
      "componentName": "'"$componentname"'",
      "message": "'"$message"'",
      "error": '$error'
  }'
}

end_script() {
  local status="$1"

  for ((i=0; i<${#messages[@]}; i++)); do
    echo "${messages[i]}"
    echo ","
  done
  
  exit $status
}

execute_command_on_machine() {
  local command="$1"

  if [[ $VM_CT_ID == "0" || $VM_CT_ID -eq 0 ]]; then
    output=$(ssh -i "$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no "$USER"@"$PROXMOX_HOST" "bash -c '$command' 2>&1")
  else
    output=$(ssh -i "$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no "$USER"@"$PROXMOX_HOST" "pct exec $VM_CT_ID -- bash -c \"$command\" 2>&1")
  fi

  local exit_status=$?

  if [[ $exit_status -ne 0 ]]; then
    messages+=("$(echo_message "Error executing command on machine ($exit_status): $command" true)")
    end_script 1
  # else
  #    echo "$output"
  fi
}


update() {
  execute_command_on_machine "apt-get update"
  messages+=("$(echo_message "Updated Successfully" false)")
  execute_command_on_machine "apt-get upgrade -y"
  messages+=("$(echo_message "Upgraded Successfully" false)")
}

## Run
update
end_script 0

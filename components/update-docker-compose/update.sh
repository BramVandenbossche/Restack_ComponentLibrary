#!/bin/bash

# Parameters
VM_CT_ID="$1"
HOST="$2"
USER="$3"
COMPOSE_LOCATION="$4"
SSH_PRIVATE_KEY="${5:-id_rsa}"

# Vars
messages=()

# Functions
echo_message() {
  local message="$1"
  local error="$2"
  local componentname="docker-compose-update"
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

execute_command_on_machine() {
  local command="$1"

  if [[ $VM_CT_ID == "0" || $VM_CT_ID -eq 0 ]]; then
    output=$(ssh -i "$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no "$USER"@"$HOST" "bash -c '$command' 2>&1")
  else
    output=$(ssh -i "$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no "$USER"@"$HOST" "pct exec $VM_CT_ID -- bash -c \"$command\" 2>&1")
  fi

  local exit_status=$?

  if [[ $exit_status -ne 0 ]]; then
    messages+=("$(echo_message "Error executing command on machine ($exit_status): $command" true)")
    end_script 1
  else
    messages+=("$(echo_message "$output" false)")
  fi
}


update() {
  messages+=("$(echo_message "Updating Docker Compose" false)")
  execute_command_on_machine "cd $COMPOSE_LOCATION && docker compose pull && docker compose up -d"
  messages+=("$(echo_message "Updated Docker Compose Successfully" false)")
}

# Run
update
end_script 0
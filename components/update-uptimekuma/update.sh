#!/usr/bin/env bash

# Parameters
VM_CT_ID="$1"
PROXMOX_HOST="$2"
USER="$3"
SSH_PRIVATE_KEY="${4:-id_rsa}"

# Vars
messages=()

# Functions
echo_message() {
  local message="$1"
  local error="$2"
  local componentname="update-uptimekuma"
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

execute_command_on_container() {
  local command="$1"

  output=$(ssh -i "$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no "$USER"@"$PROXMOX_HOST" "pct exec $VM_CT_ID -- bash -c \"$command\" 2>&1")
  local exit_status=$?

  if [[ $exit_status -ne 0 ]]; then
    messages+=("$(echo_message "Error executing command on container ($exit_status): $command" true)")
    end_script 1
  else
    echo "$output"
  fi
}

update() {
  if [[ ! -d /opt/uptime-kuma ]]; then
    messages+=("$(echo_message "No Kuma Installation Found!" true)")
    end_script 1
  fi

  LATEST=$(curl -sL https://api.github.com/repos/louislam/uptime-kuma/releases/latest | grep '"tag_name":' | cut -d'"' -f4)
  messages+=("$(echo_message "Stopping Kuma" false)")
  execute_command_on_container "sudo systemctl stop uptime-kuma &>/dev/null"
  messages+=("$(echo_message "Stopped Kuma" false)")

  execute_command_on_container "cd /opt/uptime-kuma"

  messages+=("$(echo_message "Pulling Kuma ${LATEST}" false)")
  execute_command_on_container "git fetch --all &>/dev/null"
  execute_command_on_container "git checkout $LATEST --force &>/dev/null"
  messages+=("$(echo_message "Pulled ${LATEST}" false)")

  messages+=("$(echo_message "Updating Kuma to ${LATEST}" false)")
  execute_command_on_container "npm install --production &>/dev/null"
  execute_command_on_container "npm run download-dist &>/dev/null"
  messages+=("$(echo_message "Updated" false)")

  messages+=("$(echo_message "Starting Kuma" false)")
  execute_command_on_container "sudo systemctl start uptime-kuma &>/dev/null"
  messages+=("$(echo_message "Started" false)")
  messages+=("$(echo_message "Updated Successfully" false)")

}

## Run
update
end_script 0

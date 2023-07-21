#!/bin/bash

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
  local componentname="update-nginx-proxymanager"
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")

  echo '{"timestamp": "'"$timestamp"'","componentName": "'"$componentname"'","message": "'"$message"'","error": '$error'}'
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
  check_output=$(execute_command_on_container "[ -d -d /opt/nginx-proxy-manager ] && echo 'Installed' || echo 'NotInstalled'")
  if [[ $check_output == "NotInstalled" ]]; then
    messages+=("$(echo_message "Nginx Proxy Manager is not installed!" true)")
    end_script 1
  fi

  local RELEASE=$(curl -s https://api.github.com/repos/nginx-proxy-manager/nginx-proxy-manager/releases/latest |
    grep "tag_name" |
    awk '{print substr($2, 3, length($2)-4) }')

  messages+=("$(echo_message "Stopping Nginx Proxy Manager" false)")
  execute_command_on_container "systemctl stop npm"
  messages+=("$(echo_message "Nginx Proxy Manager Stopped" false)")

  messages+=("$(echo_message "Downloading Nginx Proxy Manager version $RELEASE" false)")
  execute_command_on_container "wget -q https://codeload.github.com/nginx-proxy-manager/nginx-proxy-manager/tar.gz/$RELEASE -O - | tar -xz &>/dev/null"
  messages+=("$(echo_message "Downloaded Nginx Proxy Manager version $RELEASE" false)")

  messages+=("$(echo_message "Updating Nginx Proxy Manager to version $RELEASE" false)")
  execute_command_on_container "mv nginx-proxy-manager-$RELEASE /opt/nginx-proxy-manager"
  execute_command_on_container "cd /opt/nginx-proxy-manager && npm ci --only=prod --no-audit &>/dev/null"
  messages+=("$(echo_message "Updated Nginx Proxy Manager to version $RELEASE" false)")

  messages+=("$(echo_message "Starting Nginx Proxy Manager" false)")
  execute_command_on_container "systemctl start npm"
  messages+=("$(echo_message "Nginx Proxy Manager Started" false)")

  messages+=("$(echo_message "Update Completed Successfully" false)")
}

# Run
update
end_script 0

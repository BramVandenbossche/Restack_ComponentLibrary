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
  local componentname="update-adguard"
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

  for ((i = 0; i < ${#messages[@]}; i++)); do
    echo "${messages[i]}"
  done

  exit $status
}

execute_command_on_container() {
  local command="$1"

  pct_exec_output=$(ssh -i "$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no "$USER"@"$PROXMOX_HOST" "pct exec $VM_CT_ID -- bash -c '$command' 2>&1")
  local exit_status=$?

  if [[ $exit_status -ne 0 ]]; then
    messages+=("$(echo_message "Error executing command on container ($exit_status): $command" true)")
    end_script 1
  else
    echo "$pct_exec_output"
  fi
}

update() {
  check_output=$(execute_command_on_container "[ -d /opt/AdGuardHome ] && echo 'Installed' || echo 'NotInstalled'")
  if [[ $check_output == "NotInstalled" ]]; then
    messages+=("$(echo_message "No AdGuardHome Installation Found!" true)")
    end_script 1
  fi

  messages+=("$(echo_message "Downloading AdGuardHome" false)")
  execute_command_on_container "wget -qL https://static.adguard.com/adguardhome/release/AdGuardHome_linux_amd64.tar.gz"

  messages+=("$(echo_message "Stopping AdguardHome" false)")
  execute_command_on_container "systemctl stop AdGuardHome"
  messages+=("$(echo_message "Stopped AdguardHome" false)")

  messages+=("$(echo_message "Updating AdguardHome" false)")
  execute_command_on_container "tar -xvf AdGuardHome_linux_amd64.tar.gz &>/dev/null"
  execute_command_on_container "mkdir -p adguard-backup"
  execute_command_on_container "cp -r /opt/AdGuardHome/AdGuardHome.yaml /opt/AdGuardHome/data adguard-backup/"
  execute_command_on_container "cp AdGuardHome/AdGuardHome /opt/AdGuardHome/AdGuardHome"
  execute_command_on_container " cp -r adguard-backup/* /opt/AdGuardHome/"
  messages+=("$(echo_message "Updated AdguardHome" false)")

  messages+=("$(echo_message "Starting AdguardHome" false)")
  execute_command_on_container "systemctl start AdGuardHome"
  messages+=("$(echo_message "Started AdguardHome" false)")

  messages+=("$(echo_message "Cleaning Up" false)")
  execute_command_on_container "rm -rf AdGuardHome_linux_amd64.tar.gz AdGuardHome /opt/AdGuardHome/adguard-backup"
  messages+=("$(echo_message "Cleaned" false)")
  messages+=("$(echo_message "Updated Successfully" false)")
}

# Run
update
end_script 0

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
  local componentname="update-technitium"
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
  check_output=$(execute_command_on_container "[ -d /etc/dns ] && echo 'Installed' || echo 'NotInstalled'")
  if [[ $check_output == "NotInstalled" ]]; then
    messages+=("$(echo_message "No Technitium Installation Found!" true)")
    end_script 1
  fi

  messages+=("$(echo_message "Updating Technitium" false)")

  check_output=$(execute_command_on_container "dpkg -s aspnetcore-runtime-7.0 > /dev/null 2>&1; echo \$?")
  if [[ $check_output -ne 0 ]]; then
    messages+=("$(echo_message "Package aspnetcore-runtime-7.0 Not Installed!" true)")
    end_script 1
  fi

  execute_command_on_container "wget -q https://packages.microsoft.com/config/debian/11/packages-microsoft-prod.deb"
  execute_command_on_container "dpkg -i packages-microsoft-prod.deb &>/dev/null"
  execute_command_on_container "apt-get update &>/dev/null"
  execute_command_on_container "apt-get install -y aspnetcore-runtime-7.0 &>/dev/null"
  execute_command_on_container "rm packages-microsoft-prod.deb"

  execute_command_on_container "bash <(curl -fsSL https://download.technitium.com/dns/install.sh) &>/dev/null"

  messages+=("$(echo_message "Updated Successfully" false)")
}

## Run
update
end_script 0

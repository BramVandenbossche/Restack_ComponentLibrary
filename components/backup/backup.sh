#!/bin/bash

# Parameters
VM_CT_ID="$1"                
PBS_STORAGE="$2"             
PROXMOX_HOST="$3"
USER="$4"
SSH_PRIVATE_KEY="${5:-id_rsa}"

# Vars
messages=()          

# Functions
echo_message() {
    local message="$1"
    local componentname="backup"
    local error="$2"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")

    echo '{
        "timestamp": "'"$timestamp"'",
        "componentName": "'"$componentname"'",
        "message": "'"$message"'",
        "error": '$error'
    }'
}

end_script(){
    local status="$1"

    for ((i=0; i<${#messages[@]}; i++)); do
        echo "${messages[i]}"
    done

    exit $status
}

# Run
if [[ -z $VM_CT_ID ]]; then
    messages+=("$(echo_message "Please provide the VM or CT ID." true)")
    end_script 1
fi

if [[ -z $PBS_STORAGE ]]; then
    messages+=("$(echo_message "Please specify the PBS storage name." true)")
    end_script 1
fi

if [[ -z $SSH_PRIVATE_KEY ]]; then
    messages+=("$(echo_message "Please provide the SSH private key file name.${NC}" true)")
    end_script 1
fi

if [[ -z $PROXMOX_HOST ]]; then
    messages+=("$(echo_message "Please specify the Proxmox host IP address or hostname." true)")
    end_script 1
fi

backup_output=$(ssh -i "$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no "$USER"@"$PROXMOX_HOST" "vzdump $VM_CT_ID --storage=\"$PBS_STORAGE\" 2>&1")
if echo "$backup_output" | grep -iq "error"; then
    messages+=("$(echo_message "Backup process failed. Error: $backup_output" true)")
    end_script 1
else
    messages+=("$(echo_message "Backup process completed." false)")
    end_script 0
fi



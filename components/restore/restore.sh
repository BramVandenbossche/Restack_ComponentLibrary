#!/bin/bash

# Parameters
VM_CT_ID="$1"                
PBS_STORAGE="$2"             
TARGET_STORAGE="$3"     
PROXMOX_HOST="$4"
USER="$5"
SSH_PRIVATE_KEY="${6:-id_rsa}"

# Vars
messages=()
if [[ $VM_CT_ID =~ ^q ]]; then
    RESTORE_CMD="qmrestore"
    STOP_CMD="qm stop"
    START_CMD="qm start"
else
    RESTORE_CMD="pct restore"
    STOP_CMD="pct stop"
    START_CMD="pct start"
fi        

# Functions
echo_message() {
    local message="$1"
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
        echo ","
    done

    exit $status
}

# Run
if [[ -z $VM_CT_ID ]]; then
    messages+=("$(echo_message  "Please provide the VM or CT ID." true)")
    end_script 1
fi

if [[ -z $PBS_STORAGE ]]; then
    messages+=("$(echo_message "Please specify the PBS storage name." true)")
    end_script 1
fi

if [[ -z $SSH_PRIVATE_KEY ]]; then
    messages+=("$(echo_message "Please provide the SSH private key file name." true)")
    end_script 1
fi

if [[ -z $PROXMOX_HOST ]]; then
    messages+=("$(echo_message "Please specify the Proxmox host IP address or hostname." true)")
    end_script 1
fi

stopctvm_output=$(ssh -i "$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no "$USER"@"$PROXMOX_HOST" "$STOP_CMD" "$VM_CT_ID" 2>&1)
if [[ $stopctvm_output =~ "error" ]]; then
    messages+=("$(echo_message -e  "Failed to stop the container/VM. Error: $stopctvm_output" true)")
    end_script 1
else
    messages+=("$(echo_message -e  "Container/VM stopped successfully." false)")
fi

# # Wait until the container/VM is turned off
# while ssh -i "$SSH_PRIVATE_KEY" root@"$PROXMOX_HOST" "pvesh get /nodes/$PROXMOX_HOST/$([ $VM_CT_ID =~ ^q ] && echo \"qemu\" || echo \"lxc\")/$VM_CT_ID/status" | grep -q '\"status\":\"stopped\"'""; do
#     sleep 1
# done

backup_entry=$(ssh -i "$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no "$USER"@"$PROXMOX_HOST" "pvesm list \"$PBS_STORAGE\" --vmid \"$VM_CT_ID\"" | tail -n 1 | cut -d ' ' -f 1)
if echo "$backup_entry" | grep -iq "error"; then
    messages+=("$(echo_message -e "No available backups found." true)")
    end_script 1
fi

restore_output=$(ssh -i "$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no "$USER"@"$PROXMOX_HOST" "$RESTORE_CMD" "$VM_CT_ID" "$BACKUP_ENTRY" "--storage" "$TARGET_STORAGE" "--force" 2>&1 )
if echo "$restore_output" | grep -iq "error"; then
    messages+=("$(echo_message -e  "Failed to restore container/VM. Error: $restore_output" true)")
    end_script 1
else
    messages+=("$(echo_message -e  "Container/VM restored successfully." false)")
fi

startctvm_output=$(ssh -i "$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no "$USER"@"$PROXMOX_HOST" "$START_CMD" "$VM_CT_ID" 2>&1 )
if echo "$startctvm_output" | grep -iq "error"; then
    messages+=("$(echo_message -e  "Failed to started container/VM. Error: $startctvm_output" true)")
    end_script 1
else
    messages+=("$(echo_message -e  "Container/VM started successfully." false)")
    end_script 0
fi


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
  local componentname="update-npm"
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

find_on_container() {
  local command="$1"
  local output=$(ssh -i "$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no "$USER"@"$PROXMOX_HOST" "pct exec $VM_CT_ID -- bash -c '$command' 2>&1")
  local exit_status=$?

  if [[ $exit_status -ne 0 ]]; then
    messages+=("$(echo_message "Error executing command on container ($exit_status): $command" true)")
    end_script 1
  fi

  echo "$output"
}

update() {
  local RELEASE=$(curl -s https://api.github.com/repos/NginxProxyManager/nginx-proxy-manager/releases/latest |
  grep "tag_name" |
  awk '{print substr($2, 3, length($2)-4) }')

  check_output=$(execute_command_on_container "[ -f /lib/systemd/system/npm.service ] && echo 'Installed' || echo 'NotInstalled'")
  if [[ $check_output == "NotInstalled" ]]; then
    messages+=("$(echo_message "No Nginx Proxy Manager Installation Found!" true)")
    end_script 1
  fi

  messages+=("$(echo_message "Stopping Services" false)")
  execute_command_on_container "systemctl stop openresty"
  execute_command_on_container "systemctl stop npm"
  messages+=("$(echo_message "Stopped Services" false)")

  messages+=("$(echo_message "Cleaning Old Files" false)")
  execute_command_on_container "rm -rf /app /var/www/html /etc/nginx /var/log/nginx /var/lib/nginx /var/cache/nginx"
  messages+=("$(echo_message "Cleaned Old Files" false)")

  messages+=("$(echo_message "Downloading NPM" false)")
  execute_command_on_container "wget -q https://codeload.github.com/NginxProxyManager/nginx-proxy-manager/tar.gz/v${RELEASE} -O - | tar -xz &>/dev/null"
  messages+=("$(echo_message "Downloaded NPM" false)")

  messages+=("$(echo_message "Setting up Environment" false)")
  messages+=("$(echo_message " test1" false)")
  execute_command_on_container "ln -sf /usr/bin/python3 /usr/bin/python"
  execute_command_on_container "ln -sf /usr/bin/certbot /opt/certbot/bin/certbot"
  execute_command_on_container "ln -sf /usr/local/openresty/nginx/sbin/nginx /usr/sbin/nginx"
  execute_command_on_container "ln -sf /usr/local/openresty/nginx/ /etc/nginx"
  execute_command_on_container "sed -i 's+0.0.0+${RELEASE}+g' nginx-proxy-manager-${RELEASE}/backend/package.json"
  messages+=("$(echo_message " test2" false)")
  execute_command_on_container "sed -i 's+0.0.0+${RELEASE}+g' nginx-proxy-manager-${RELEASE}/frontend/package.json"
  messages+=("$(echo_message " test3" false)")
  execute_command_on_container "sed -i 's+^daemon+#daemon+g' nginx-proxy-manager-${RELEASE}/docker/rootfs/etc/nginx/nginx.conf"
  messages+=("$(echo_message " test4" false)")

  local res=$(find_on_container 'find "$(pwd)" -type f -name "*.conf" -exec sed -i "s+include conf.d+include /etc/nginx/conf.d+g" {} +')


  messages+=("$(echo_message " test" false)")

  messages+=("$(echo_message " $res" false)")
  execute_command_on_container "mkdir -p /var/www/html /etc/nginx/logs"
  execute_command_on_container "cp -r nginx-proxy-manager-${RELEASE}/docker/rootfs/var/www/html/* /var/www/html/"
  execute_command_on_container "cp -r nginx-proxy-manager-${RELEASE}/docker/rootfs/etc/nginx/* /etc/nginx/"
  execute_command_on_container "cp nginx-proxy-manager-${RELEASE}/docker/rootfs/etc/letsencrypt.ini /etc/letsencrypt.ini"
  execute_command_on_container "cp nginx-proxy-manager-${RELEASE}/docker/rootfs/etc/logrotate.d/nginx-proxy-manager /etc/logrotate.d/nginx-proxy-manager"
  execute_command_on_container "ln -sf /etc/nginx/nginx.conf /etc/nginx/conf/nginx.conf"
  execute_command_on_container "rm -f /etc/nginx/conf.d/dev.conf"
  execute_command_on_container "mkdir -p /tmp/nginx/body /run/nginx /data/nginx /data/custom_ssl /data/logs /data/access /data/nginx/default_host /data/nginx/default_www /data/nginx/proxy_host /data/nginx/redirection_host /data/nginx/stream /data/nginx/dead_host /data/nginx/temp /var/lib/nginx/cache/public /var/lib/nginx/cache/private /var/cache/nginx/proxy_temp"
  execute_command_on_container "chmod -R 777 /var/cache/nginx"
  execute_command_on_container "chown root /tmp/nginx"
  messages+=("$(echo_message "Environment Set up" false)")

  messages+=("$(echo_message "Starting Services" false)")
  execute_command_on_container "sed -i -e 's/user npm/user root/g' -e 's/^pid/#pid/g' /usr/local/openresty/nginx/conf/nginx.conf"
  execute_command_on_container "sed -i 's/include-system-site-packages = false/include-system-site-packages = true/g' /opt/certbot/pyvenv.cfg"
  execute_command_on_container "systemctl enable -q --now openresty"
  execute_command_on_container "systemctl enable -q --now npm"
  messages+=("$(echo_message "Started Services" false)")

  messages+=("$(echo_message "Cleaning up" false)")
  execute_command_on_container "rm -rf ~/nginx-proxy-manager-*"
  messages+=("$(echo_message "Cleaned" false)")
  messages+=("$(echo_message "Updated Successfully" false)")
}

# Run
update
end_script 0
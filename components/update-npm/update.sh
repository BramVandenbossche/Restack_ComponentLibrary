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

  echo '{"timestamp": "'"$timestamp"'","componentName": "'"$componentname"'","message": "'"$message"'","error": '$error'}'
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

  pct_exec_output=$(ssh -i "$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no "$USER"@"$PROXMOX_HOST" "pct exec $VM_CT_ID -- bash -s" <<EOF
$command
EOF
  )
  
  local exit_status=$?

  if [[ $exit_status -ne 0 ]]; then
    messages+=("$(echo_message "Error executing command on container ($exit_status): $command" true)")
    end_script 1
  else
    echo "$pct_exec_output"
  fi
}

update() {
  check_output=$(execute_command_on_container "[ -d /etc/nginx ] && echo 'Installed' || echo 'NotInstalled'")
  if [[ $check_output == "NotInstalled" ]]; then
    messages+=("$(echo_message "No Nginx Proxy Manager Installation Found!" true)")
    end_script 1
  fi

  RELEASE=$(execute_command_on_container "curl -s https://api.github.com/repos/NginxProxyManager/nginx-proxy-manager/releases/latest | grep 'tag_name' | awk '{print substr(\$2, 3, length(\$2)-4)}'")

  messages+=("$(echo_message "Stopping Services" false)")
  execute_command_on_container "sudo systemctl stop openresty"
  execute_command_on_container "sudo systemctl stop npm"
  messages+=("$(echo_message "Stopped Services" false)")

  messages+=("$(echo_message "Cleaning Old Files" false)")
  execute_command_on_container "sudo rm -rf /app \
    /var/www/html \
    /etc/nginx \
    /var/log/nginx \
    /var/lib/nginx \
    /var/cache/nginx"
  messages+=("$(echo_message "Cleaned Old Files" false)")

  messages+=("$(echo_message "Downloading NPM v${RELEASE}" false)")
  execute_command_on_container "wget -q https://codeload.github.com/NginxProxyManager/nginx-proxy-manager/tar.gz/v${RELEASE} -O - | tar -xz"
  execute_command_on_container "cd nginx-proxy-manager-${RELEASE}"
  messages+=("$(echo_message "Downloaded NPM v${RELEASE}" false)")

  messages+=("$(echo_message "Setting up Environment" false)")
  execute_command_on_container "sudo ln -sf /usr/bin/python3 /usr/bin/python"
  execute_command_on_container "sudo ln -sf /usr/bin/certbot /opt/certbot/bin/certbot"
  execute_command_on_container "sudo ln -sf /usr/local/openresty/nginx/sbin/nginx /usr/sbin/nginx"
  execute_command_on_container "sudo ln -sf /usr/local/openresty/nginx/ /etc/nginx"
  execute_command_on_container "sudo sed -i 's+0.0.0+${RELEASE}+g' /root/nginx-proxy-manager-${RELEASE}/backend/package.json"
  execute_command_on_container "sudo sed -i 's+0.0.0+${RELEASE}+g' /root/nginx-proxy-manager-${RELEASE}/frontend/package.json"
  execute_command_on_container "sudo sed -i 's+^daemon+#daemon+g' /root/nginx-proxy-manager-${RELEASE}/docker/rootfs/etc/nginx/nginx.conf"

  execute_command_on_container "find /root/nginx-proxy-manager-${RELEASE} -type f -name '*.conf' -print0 | while IFS= read -r -d '' file; do sudo sed -i 's+include conf.d+include /etc/nginx/conf.d+g' \"\$file\"; done"

  execute_command_on_container "sudo mkdir -p /var/www/html /etc/nginx/logs"
  execute_command_on_container "sudo cp -r /root/nginx-proxy-manager-${RELEASE}/docker/rootfs/var/www/html/* /var/www/html/"
  execute_command_on_container "sudo cp -r /root/nginx-proxy-manager-${RELEASE}/docker/rootfs/etc/nginx/* /etc/nginx/"
  execute_command_on_container "sudo cp /root/nginx-proxy-manager-${RELEASE}/docker/rootfs/etc/letsencrypt.ini /etc/letsencrypt.ini"
  execute_command_on_container "sudo cp /root/nginx-proxy-manager-${RELEASE}/docker/rootfs/etc/logrotate.d/nginx-proxy-manager /etc/logrotate.d/nginx-proxy-manager"
  execute_command_on_container "sudo ln -sf /etc/nginx/nginx.conf /etc/nginx/conf/nginx.conf"
  execute_command_on_container "sudo rm -f /etc/nginx/conf.d/dev.conf"
  execute_command_on_container "sudo mkdir -p /tmp/nginx/body \
    /run/nginx \
    /data/nginx \
    /data/custom_ssl \
    /data/logs \
    /data/access \
    /data/nginx/default_host \
    /data/nginx/default_www \
    /data/nginx/proxy_host \
    /data/nginx/redirection_host \
    /data/nginx/stream \
    /data/nginx/dead_host \
    /data/nginx/temp \
    /var/lib/nginx/cache/public \
    /var/lib/nginx/cache/private \
    /var/cache/nginx/proxy_temp"
  execute_command_on_container "sudo chmod -R 777 /var/cache/nginx"
  execute_command_on_container "sudo chown root /tmp/nginx"
  execute_command_on_container 'echo "resolver $(awk "BEGIN{ORS=\" \"} \$1==\"nameserver\" {print (\$2 ~ \":\")? \"[\"\$2\"]\": \$2}" /etc/resolv.conf);" >/etc/nginx/conf.d/include/resolvers.conf'
  execute_command_on_container 'if [ ! -f /data/nginx/dummycert.pem ] || [ ! -f /data/nginx/dummykey.pem ]; then
    echo -e "${CHECKMARK} \e[1;92m Generating dummy SSL Certificate... \e[0m"
    openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 -subj "/O=Nginx Proxy Manager/OU=Dummy Certificate/CN=localhost" -keyout /data/nginx/dummykey.pem -out /data/nginx/dummycert.pem &>/dev/null
  fi'
  execute_command_on_container "sudo mkdir -p /app/global /app/frontend/images"
  execute_command_on_container "sudo cp -r /root/nginx-proxy-manager-${RELEASE}/backend/* /app"
  execute_command_on_container "sudo cp -r /root/nginx-proxy-manager-${RELEASE}/global/* /app/global"
  execute_command_on_container 'wget -q "https://github.com/just-containers/s6-overlay/releases/download/v3.1.5.0/s6-overlay-noarch.tar.xz"'
  execute_command_on_container 'wget -q "https://github.com/just-containers/s6-overlay/releases/download/v3.1.5.0/s6-overlay-x86_64.tar.xz"'
  execute_command_on_container 'sudo tar -C / -Jxpf s6-overlay-noarch.tar.xz'
  execute_command_on_container 'sudo tar -C / -Jxpf s6-overlay-x86_64.tar.xz'
  execute_command_on_container "sudo python3 -m pip install --no-cache-dir certbot-dns-cloudflare &>/dev/null"
  messages+=("$(echo_message "Setup Environment" false)")

  messages+=("$(echo_message "Building Frontend" false)")
  execute_command_on_container "cd ./frontend && \
    export NODE_ENV=development && \
    yarn install --network-timeout=30000 &>/dev/null && \
    yarn build &>/dev/null"
  execute_command_on_container "sudo cp -r dist/* /app/frontend"
  execute_command_on_container "sudo cp -r app-images/* /app/frontend/images"
  messages+=("$(echo_message "Built Frontend" false)")

  messages+=("$(echo_message "Initializing Backend" false)")
  execute_command_on_container 'if [ ! -f /app/config/production.json ]; then
    cat <<EOF > /app/config/production.json
{
  "database": {
    "engine": "knex-native",
    "knex": {
      "client": "sqlite3",
      "connection": {
        "filename": "/data/database.sqlite"
      }
    }
  }
}
EOF
  fi'
  execute_command_on_container "cd /app && \
    export NODE_ENV=development && \
    yarn install --network-timeout=30000 &>/dev/null"
  messages+=("$(echo_message "Initialized Backend" false)")

  messages+=("$(echo_message "Starting Services" false)")
  execute_command_on_container "sudo sed -i 's/user npm/user root/g; s/^pid/#pid/g' /usr/local/openresty/nginx/conf/nginx.conf"
  execute_command_on_container "sudo sed -i 's/include-system-site-packages = false/include-system-site-packages = true/g' /opt/certbot/pyvenv.cfg"
  execute_command_on_container "sudo systemctl enable -q --now openresty"
  execute_command_on_container "sudo systemctl enable -q --now npm"
  messages+=("$(echo_message "Started Services" false)")

  messages+=("$(echo_message "Cleaning up" false)")
  execute_command_on_container "sudo rm -rf ~/nginx-proxy-manager-* s6-overlay-noarch.tar.xz s6-overlay-x86_64.tar.xz"
  messages+=("$(echo_message "Cleaned" false)")

  messages+=("$(echo_message "Updated Successfully" false)")
}

# Run
update
end_script 0
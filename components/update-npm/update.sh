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
  check_output=$(execute_command_on_container "[ -f /lib/systemd/system/npm.service ] && echo 'Installed' || echo 'NotInstalled'")
  if [[ $check_output == "NotInstalled" ]]; then
    messages+=("$(echo_message "No Nginx Proxy Manager Installation Found!" true)")
    end_script 1
  fi

  RELEASE=$(curl -s https://api.github.com/repos/NginxProxyManager/nginx-proxy-manager/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')

  execute_command_on_container "systemctl stop openresty"
  execute_command_on_container "systemctl stop npm"

  execute_command_on_container "rm -rf /app /var/www/html /etc/nginx /var/log/nginx /var/lib/nginx /var/cache/nginx &>/dev/null"

  execute_command_on_container "wget -q https://codeload.github.com/NginxProxyManager/nginx-proxy-manager/tar.gz/v${RELEASE} -O - | tar -xz &>/dev/null"
  execute_command_on_container "cd nginx-proxy-manager-${RELEASE}"

  execute_command_on_container "ln -sf /usr/bin/python3 /usr/bin/python"
  execute_command_on_container "ln -sf /usr/bin/certbot /opt/certbot/bin/certbot"
  execute_command_on_container "ln -sf /usr/local/openresty/nginx/sbin/nginx /usr/sbin/nginx"
  execute_command_on_container "ln -sf /usr/local/openresty/nginx/ /etc/nginx"
  execute_command_on_container "sed -i \"s+0.0.0+${RELEASE}+g\" backend/package.json"
  execute_command_on_container "sed -i \"s+0.0.0+${RELEASE}+g\" frontend/package.json"
  execute_command_on_container "sed -i 's+^daemon+#daemon+g' docker/rootfs/etc/nginx/nginx.conf"

  NGINX_CONFS=$(execute_command_on_container "find \"\$(pwd)\" -type f -name \"*.conf\"")
  for NGINX_CONF in $NGINX_CONFS; do
    execute_command_on_container "sed -i 's+include conf.d+include /etc/nginx/conf.d+g' \"$NGINX_CONF\""
  done

  execute_command_on_container "mkdir -p /var/www/html /etc/nginx/logs"
  execute_command_on_container "cp -r docker/rootfs/var/www/html/* /var/www/html/"
  execute_command_on_container "cp -r docker/rootfs/etc/nginx/* /etc/nginx/"
  execute_command_on_container "cp docker/rootfs/etc/letsencrypt.ini /etc/letsencrypt.ini"
  execute_command_on_container "cp docker/rootfs/etc/logrotate.d/nginx-proxy-manager /etc/logrotate.d/nginx-proxy-manager"
  execute_command_on_container "ln -sf /etc/nginx/nginx.conf /etc/nginx/conf/nginx.conf"
  execute_command_on_container "rm -f /etc/nginx/conf.d/dev.conf"
  execute_command_on_container "mkdir -p /tmp/nginx/body /run/nginx /data/nginx /data/custom_ssl /data/logs /data/access /data/nginx/default_host /data/nginx/default_www /data/nginx/proxy_host /data/nginx/redirection_host /data/nginx/stream /data/nginx/dead_host /data/nginx/temp /var/lib/nginx/cache/public /var/lib/nginx/cache/private /var/cache/nginx/proxy_temp"
  execute_command_on_container "chmod -R 777 /var/cache/nginx"
  execute_command_on_container "chown root /tmp/nginx"
  execute_command_on_container "echo resolver \"\$(awk 'BEGIN{ORS=\" \"} \$1==\"nameserver\" {print (\$2 ~ \":\")? \"[\"\$2\"]\": \$2}' /etc/resolv.conf);\" >/etc/nginx/conf.d/include/resolvers.conf"

  execute_command_on_container "[ ! -f /data/nginx/dummycert.pem ] || [ ! -f /data/nginx/dummykey.pem ] && openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 -subj \"/O=Nginx Proxy Manager/OU=Dummy Certificate/CN=localhost\" -keyout /data/nginx/dummykey.pem -out /data/nginx/dummycert.pem &>/dev/null"

  execute_command_on_container "mkdir -p /app/global /app/frontend/images"
  execute_command_on_container "cp -r backend/* /app"
  execute_command_on_container "cp -r global/* /app/global"

  execute_command_on_container "wget -q \"https://github.com/just-containers/s6-overlay/releases/download/v3.1.5.0/s6-overlay-noarch.tar.xz\""
  execute_command_on_container "wget -q \"https://github.com/just-containers/s6-overlay/releases/download/v3.1.5.0/s6-overlay-x86_64.tar.xz\""
  execute_command_on_container "tar -C / -Jxpf s6-overlay-noarch.tar.xz"
  execute_command_on_container "tar -C / -Jxpf s6-overlay-x86_64.tar.xz"

  execute_command_on_container "python3 -m pip install --no-cache-dir certbot-dns-cloudflare &>/dev/null"

  execute_command_on_container "cd /app/frontend"
  execute_command_on_container "export NODE_ENV=development"
  execute_command_on_container "yarn install --network-timeout=30000 &>/dev/null"
  execute_command_on_container "yarn build &>/dev/null"
  execute_command_on_container "cp -r dist/* /app/frontend"
  execute_command_on_container "cp -r app-images/* /app/frontend/images"

  execute_command_on_container "rm -rf /app/config/default.json &>/dev/null"
  execute_command_on_container "[ ! -f /app/config/production.json ] && cat <<'EOF' >/app/config/production.json
{
  \"database\": {
    \"engine\": \"knex-native\",
    \"knex\": {
      \"client\": \"sqlite3\",
      \"connection\": {
        \"filename\": \"/data/database.sqlite\"
      }
    }
  }
}
EOF"

  execute_command_on_container "cd /app"
  execute_command_on_container "export NODE_ENV=development"
  execute_command_on_container "yarn install --network-timeout=30000 &>/dev/null"

  execute_command_on_container "sed -i 's/user npm/user root/g; s/^pid/#pid/g' /usr/local/openresty/nginx/conf/nginx.conf"
  execute_command_on_container "sed -i 's/include-system-site-packages = false/include-system-site-packages = true/g' /opt/certbot/pyvenv.cfg"
  execute_command_on_container "systemctl enable -q --now openresty"
  execute_command_on_container "systemctl enable -q --now npm"

  execute_command_on_container "rm -rf ~/nginx-proxy-manager-* s6-overlay-noarch.tar.xz s6-overlay-x86_64.tar.xz"

  msg_ok "Updated Successfully"
  exit
}

# Run
update
end_script 0
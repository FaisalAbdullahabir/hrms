#!/bin/bash
set -e

echo 'Waiting for database...'

# Wait for MariaDB
until mysqladmin ping -h mariadb -u root -pfrappe --silent; do
  echo 'Waiting for MariaDB...'
  sleep 5
done

cd /home/frappe/frappe-bench

# Create site if it doesn't exist
if [ ! -f sites/site1.local/site_config.json ]; then
  echo 'Creating new site...'
  bench new-site site1.local --db-host mariadb --db-port 3306 --mariadb-root-password frappe --admin-password admin --no-mariadb-socket
  
  echo 'Configuring Redis...'
  python3 -c 'import json; f=open("/home/frappe/frappe-bench/sites/common_site_config.json","r+"); cfg=json.load(f); cfg["redis_cache"]="redis://:lhRedis@2026@redis:6379/0"; cfg["redis_queue"]="redis://:lhRedis@2026@redis:6379/1"; cfg["redis_socketio"]="redis://:lhRedis@2026@redis:6379/2"; f.seek(0); json.dump(cfg,f,indent=2); f.truncate(); f.close()'
  
  echo 'Installing ERPNext...'
  bench --site site1.local install-app erpnext
  
  echo 'Installing HRMS...'
  bench get-app hrms --branch version-15
  bench --site site1.local install-app hrms
  
  echo 'Building assets...'
  bench build
fi

# Ensure apps.txt only lists apps that actually exist
echo 'Checking installed apps...'
APPS_TXT="sites/apps.txt"
for app in erpnext hrms lawnhive_branding license_control education drive; do
  if ! grep -q "^${app}$" "$APPS_TXT" 2>/dev/null; then
    if [ -d "apps/${app}" ]; then
      echo "Adding ${app} to apps.txt..."
      echo "${app}" >> "$APPS_TXT"
    fi
  fi
done

# Remove apps from apps.txt that don't have source code
TEMP_FILE=$(mktemp)
while IFS= read -r app; do
  # frappe and erpnext are built into the image
  if [ "$app" = "frappe" ] || [ "$app" = "erpnext" ]; then
    echo "$app" >> "$TEMP_FILE"
  elif [ -d "apps/${app}" ]; then
    echo "$app" >> "$TEMP_FILE"
  else
    echo "WARNING: Removing ${app} from apps.txt (source not found)"
  fi
done < "$APPS_TXT"
mv "$TEMP_FILE" "$APPS_TXT"

echo 'Setting site as default...'
bench use site1.local || true

echo 'Applying custom theme...'
python3 /home/frappe/frappe-bench/sites/apply_theme.py || echo 'Theme application skipped (not critical)'

echo 'Starting cron service...'
/usr/sbin/cron 2>/dev/null || service cron start 2>/dev/null || true

echo 'Starting Frappe server...'
bench serve --port 8000

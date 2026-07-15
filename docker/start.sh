#!/bin/bash
set -e

echo "=== HRMS Docker Startup ==="

# Wait for MariaDB
echo "Waiting for MariaDB..."
until mysqladmin ping -h"$DB_HOST" -P"$DB_PORT" -u root -p"$DB_ROOT_PASSWORD" --silent 2>/dev/null; do
    sleep 2
done
echo "MariaDB is ready."

# Wait for Redis
echo "Waiting for Redis..."
until redis-cli -h redis ping 2>/dev/null | grep -q PONG; do
    sleep 2
done
echo "Redis is ready."

# Check if site exists
if [ ! -d "/home/frappe/frappe-bench/sites/${SITE_NAME}" ]; then
    echo "Creating site ${SITE_NAME}..."
    cd /home/frappe/frappe-bench
    bench new-site ${SITE_NAME} \
        --mariadb-root-password ${DB_ROOT_PASSWORD} \
        --admin-password ${FRAPPE_USER_PWD} \
        --no-mariadb-socket
fi

cd /home/frappe/frappe-bench

# Set site config
bench --site ${SITE_NAME} set-config db_host ${DB_HOST}
bench --site ${SITE_NAME} set-config db_port ${DB_PORT}
bench --site ${SITE_NAME} set-config redis_cache "${REDIS_CACHE}"
bench --site ${SITE_NAME} set-config redis_queue "${REDIS_QUEUE}"
bench --site ${SITE_NAME} set-config redis_socketio "${REDIS_SOCKETIO}"

# Install apps if not already installed
bench --site ${SITE_NAME} list-apps | grep -q erpnext || bench --site ${SITE_NAME} install-app erpnext
bench --site ${SITE_NAME} list-apps | grep -q hrms || bench --site ${SITE_NAME} install-app hrms
bench --site ${SITE_NAME} list-apps | grep -q lawnhive_branding || bench --site ${SITE_NAME} install-app lawnhive_branding

# Ensure lawnhive_branding pip package is installed (needed for hooks discovery)
pip install -e ./apps/lawnhive_branding 2>/dev/null || true

# Set site as default
bench use ${SITE_NAME}

# Clear cache to ensure app hooks (web_include_css, etc.) are loaded
bench --site ${SITE_NAME} clear-cache || true

echo "=== Starting Frappe Server ==="
bench serve --port 8000

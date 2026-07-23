#!/bin/bash
set -e

# ── Fix HOME (Windows Docker Desktop leaks Windows HOME) ────────
export HOME=/home/frappe

# ── Ensure localhost resolves (required by wkhtmltopdf for PDF generation) ──
if ! grep -q "127.0.0.1 localhost" /etc/hosts 2>/dev/null; then
    echo "127.0.0.1 localhost" >> /etc/hosts
fi

echo '=========================================='
echo '  LawnHive Workspace - Starting...'
echo '=========================================='

# ── Required environment variables ───────────────────────────────
# DB_ROOT_PASSWORD  - MariaDB root password
# REDIS_PASSWORD    - Redis authentication password
# ADMIN_PASSWORD    - Frappe admin password (default: admin)
# SITE_NAME         - Site name (default: site1.local)

DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-frappe}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin}"
SITE_NAME="${SITE_NAME:-site1.local}"
DB_HOST="${DB_HOST:-mariadb}"
DB_PORT="${DB_PORT:-3306}"

# ── Build Redis URLs from password ──────────────────────────────
if [ -n "$REDIS_PASSWORD" ]; then
    REDIS_CACHE_URL="redis://:${REDIS_PASSWORD}@redis:6379/0"
    REDIS_QUEUE_URL="redis://:${REDIS_PASSWORD}@redis:6379/1"
    REDIS_SOCKETIO_URL="redis://:${REDIS_PASSWORD}@redis:6379/2"
else
    REDIS_CACHE_URL="redis://redis:6379/0"
    REDIS_QUEUE_URL="redis://redis:6379/1"
    REDIS_SOCKETIO_URL="redis://redis:6379/2"
fi

# ── Wait for MariaDB ────────────────────────────────────────────
echo 'Waiting for database...'
until mysqladmin ping -h "$DB_HOST" -u root -p"$DB_ROOT_PASSWORD" --silent 2>/dev/null; do
    echo "Waiting for MariaDB..."
    sleep 5
done
echo 'Database is ready.'

cd /home/frappe/frappe-bench

# ── Create site if it doesn't exist ─────────────────────────────
if [ ! -f "sites/${SITE_NAME}/site_config.json" ]; then
    echo "Creating new site: ${SITE_NAME}..."
    bench new-site "$SITE_NAME" \
        --db-host "$DB_HOST" \
        --db-port "$DB_PORT" \
        --mariadb-root-password "$DB_ROOT_PASSWORD" \
        --admin-password "$ADMIN_PASSWORD" \
        --no-mariadb-socket

    echo 'Configuring Redis...'
    python3 -c "
import json
with open('sites/common_site_config.json', 'r+') as f:
    cfg = json.load(f)
    cfg['redis_cache'] = '${REDIS_CACHE_URL}'
    cfg['redis_queue'] = '${REDIS_QUEUE_URL}'
    cfg['redis_socketio'] = '${REDIS_SOCKETIO_URL}'
    f.seek(0)
    json.dump(cfg, f, indent=2)
    f.truncate()
"

    echo 'Configuring wkhtmltopdf for PDF generation...'
    python3 -c "
import json, os
site_cfg_path = 'sites/${SITE_NAME}/site_config.json'
if os.path.exists(site_cfg_path):
    with open(site_cfg_path, 'r+') as f:
        cfg = json.load(f)
        cfg['host_name'] = 'http://localhost:8000'
        cfg['allow_wkhtmltopdf'] = True
        cfg['enable_print_server'] = True
        f.seek(0)
        json.dump(cfg, f, indent=2)
        f.truncate()
"

    echo 'Installing ERPNext...'
    bench --site "$SITE_NAME" install-app erpnext

    echo 'Installing HRMS...'
    bench --site "$SITE_NAME" install-app hrms

    echo 'Installing Education...'
    bench --site "$SITE_NAME" install-app education

    echo 'Installing Drive...'
    bench --site "$SITE_NAME" install-app drive

    echo 'Installing LawnHive Branding...'
    bench --site "$SITE_NAME" install-app lawnhive_branding

    echo 'Installing License Control...'
    bench --site "$SITE_NAME" install-app license_control

    echo 'Building assets...'
    bench build 2>&1 || true

    echo 'Applying LawnHive branding...'
    bench --site "$SITE_NAME" execute lawnhive_branding.setup.after_install 2>&1 || true

    echo 'Setting up Student Health Record feature...'
    bench --site "$SITE_NAME" execute lawnhive_branding.education_health.setup.setup_all 2>&1 || true

    echo 'Setting default workspace...'
    bench --site "$SITE_NAME" execute "
import frappe
frappe.db.set_single_value('System Settings', 'app_name', 'LawnHive Workspace')
frappe.db.commit()
" 2>&1 || true
fi

# ── Ensure apps.txt is correct ──────────────────────────────────
cat > sites/apps.txt << 'EOF'
frappe
erpnext
hrms
lawnhive_branding
license_control
education
drive
EOF

# ── Update Redis config (in case password changed) ──────────────
python3 -c "
import json, os
with open('sites/common_site_config.json', 'r+') as f:
    cfg = json.load(f)
    changed = False
    for key, val in [('redis_cache', '${REDIS_CACHE_URL}'), ('redis_queue', '${REDIS_QUEUE_URL}'), ('redis_socketio', '${REDIS_SOCKETIO_URL}')]:
        if cfg.get(key) != val:
            cfg[key] = val
            changed = True
    if changed:
        f.seek(0)
        json.dump(cfg, f, indent=2)
        f.truncate()
" 2>/dev/null || true

# ── Set default site ────────────────────────────────────────────
echo 'Setting site as default...'
bench use "$SITE_NAME" || true

# ── Ensure assets are built ─────────────────────────────────────
# On first boot the named volume is empty, hiding image-baked assets.
# If assets.json is missing we must rebuild so CSS/JS are served.
# Must run as frappe user for correct hashes/ownership.
if [ ! -f "sites/assets/assets.json" ] || [ "$(find sites/assets -name '*.js' 2>/dev/null | wc -l)" -lt 10 ]; then
    echo 'Assets missing or incomplete — running bench build...'
    chown -R frappe:frappe sites/assets/ 2>/dev/null || true
    su -s /bin/bash frappe -c "HOME=/home/frappe bench build" 2>&1 || true
    echo 'Assets built.'
fi

# ── Clear website cache only (keep desk asset hashes intact) ─────
bench --site "$SITE_NAME" clear-website-cache 2>&1 || true

# ── Ensure Education sub-workspaces exist (idempotent) ──────────
echo 'Ensuring Education sub-workspaces...'
bench --site "$SITE_NAME" execute lawnhive_branding.education_health.workspace_setup.setup_education_workspaces 2>&1 || true

# ── Ensure Student mandatory fields are correct (idempotent) ───
echo 'Ensuring Student field settings...'
bench --site "$SITE_NAME" execute lawnhive_branding.patches.v1_0.fix_student_mandatory_fields.execute 2>&1 || true

# ── Start cron service (must run as root) ────────────────────────
echo 'Starting cron service...'
/usr/sbin/cron 2>/dev/null || true

# ── Start background worker + scheduler (as frappe user) ─────────
echo 'Starting background worker (scheduler + job processor)...'
su -s /bin/bash frappe -c "HOME=/home/frappe bench worker --queue default,long,short > /tmp/worker.log 2>&1 &"
sleep 2
echo "Worker started (PID $(cat /tmp/worker.pid 2>/dev/null || echo '?'))"

# ── Start Frappe server (as frappe user) ─────────────────────────
echo '=========================================='
echo '  LawnHive Workspace is ready!'
echo '  http://localhost:8000'
echo '=========================================='
exec su -s /bin/bash frappe -c "HOME=/home/frappe bench serve --port 8000"

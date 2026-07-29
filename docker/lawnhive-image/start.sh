#!/bin/bash
set -uo pipefail

export HOME=/home/frappe
LOGFILE="/home/frappe/frappe-bench/startup.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"; }

if ! grep -q "127.0.0.1 localhost" /etc/hosts 2>/dev/null; then
    echo "127.0.0.1 localhost" >> /etc/hosts
fi

log '=========================================='
log '  LawnHive Workspace - Starting...'
log '=========================================='

DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-frappe}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin}"
SITE_NAME="${SITE_NAME:-site1.local}"
DB_HOST="${DB_HOST:-mariadb}"
DB_PORT="${DB_PORT:-3306}"

if [ -n "$REDIS_PASSWORD" ]; then
    REDIS_CACHE_URL="redis://:${REDIS_PASSWORD}@redis:6379/0"
    REDIS_QUEUE_URL="redis://:${REDIS_PASSWORD}@redis:6379/1"
    REDIS_SOCKETIO_URL="redis://:${REDIS_PASSWORD}@redis:6379/2"
else
    REDIS_CACHE_URL="redis://redis:6379/0"
    REDIS_QUEUE_URL="redis://redis:6379/1"
    REDIS_SOCKETIO_URL="redis://redis:6379/2"
fi

log 'Waiting for database...'
WAIT_COUNT=0
until mysqladmin ping -h "$DB_HOST" -u root -p"$DB_ROOT_PASSWORD" --silent 2>/dev/null; do
    WAIT_COUNT=$((WAIT_COUNT + 1))
    if [ "$WAIT_COUNT" -gt 60 ]; then
        log 'FATAL: MariaDB not ready after 5 minutes. Exiting.'
        exit 1
    fi
    log "Waiting for MariaDB... ($WAIT_COUNT)"
    sleep 5
done
log 'Database is ready.'

cd /home/frappe/frappe-bench

# ── Retry counter (max 3 attempts to prevent infinite loop) ─────
MAX_ATTEMPTS=3
ATTEMPT_FILE="sites/.setup_attempts"
ATTEMPT=1
if [ -f "$ATTEMPT_FILE" ]; then
    ATTEMPT=$(cat "$ATTEMPT_FILE")
fi

# If no site directory exists, counter is stale from previous cleanup — reset
if [ ! -d "sites/${SITE_NAME}" ] && [ "$ATTEMPT" -gt 1 ]; then
    log "Site directory gone but counter shows attempt ${ATTEMPT}. Resetting counter."
    ATTEMPT=1
    echo "1" > "$ATTEMPT_FILE"
fi

cleanup_partial_site() {
    log "Cleaning up partial site data..."

    # Step 1: Try bench drop-site (correctly drops database + filesystem)
    log "Attempting bench drop-site..."
    DROP_OUTPUT=$(bench drop-site "$SITE_NAME" --root-password "$DB_ROOT_PASSWORD" 2>&1) || true
    log "bench drop-site output: $DROP_OUTPUT"

    # Step 2: Check if database still exists (bench drop-site may fail if DB name doesn't match site name)
    SITE_DB=$(mysql -h "$DB_HOST" -u root -p"$DB_ROOT_PASSWORD" -N -e "SHOW DATABASES" 2>/dev/null | grep -i "$SITE_NAME" || true)
    if [ -n "$SITE_DB" ]; then
        log "WARNING: Database '$SITE_DB' still exists after bench drop-site. Dropping manually..."
        mysql -h "$DB_HOST" -u root -p"$DB_ROOT_PASSWORD" -e "DROP DATABASE IF EXISTS \`$SITE_DB\`" 2>/dev/null || true
        log "Dropped database: $SITE_DB"
    fi

    # Step 3: Also check for orphaned databases from previous failed attempts (hash-based names)
    ORPHAN_DBS=$(mysql -h "$DB_HOST" -u root -p"$DB_ROOT_PASSWORD" -N -e "SHOW DATABASES" 2>/dev/null | grep -E '^_[a-f0-9]{16}$' || true)
    if [ -n "$ORPHAN_DBS" ]; then
        log "Found orphaned databases: $ORPHAN_DBS"
        for orphan_db in $ORPHAN_DBS; do
            log "Dropping orphaned database: $orphan_db"
            mysql -h "$DB_HOST" -u root -p"$DB_ROOT_PASSWORD" -e "DROP DATABASE IF EXISTS \`$orphan_db\`" 2>/dev/null || true
        done
    fi

    # Step 4: Remove site directory (preserve backups volume mount point)
    if [ -d "sites/${SITE_NAME}" ]; then
        log "Removing site directory: sites/${SITE_NAME}"
        find "sites/${SITE_NAME}" -mindepth 1 -not -path "*/private/backups*" -delete 2>/dev/null || true
        # Remove the directory itself (backups mount point survives since it's a volume)
        rmdir "sites/${SITE_NAME}" 2>/dev/null || true
        rmdir "sites/${SITE_NAME}/private" 2>/dev/null || true
        rmdir "sites/${SITE_NAME}/private/backups" 2>/dev/null || true
    fi

    # Step 5: Clean up attempt counter
    rm -f "$ATTEMPT_FILE" 2>/dev/null || true

    # Step 6: Verify cleanup
    if [ -d "sites/${SITE_NAME}" ]; then
        log "WARNING: Site directory still exists (backups volume mount point - this is expected)"
    else
        log "Site directory successfully removed"
    fi
    REMAINING_DB=$(mysql -h "$DB_HOST" -u root -p"$DB_ROOT_PASSWORD" -N -e "SHOW DATABASES" 2>/dev/null | grep -i "$SITE_NAME" || true)
    if [ -n "$REMAINING_DB" ]; then
        log "WARNING: Database '$REMAINING_DB' still exists after cleanup"
    else
        log "No leftover site databases found"
    fi

    log "Cleanup complete."
}

if [ -d "sites/${SITE_NAME}" ] && [ ! -f "sites/${SITE_NAME}/site_config.json" ]; then
    log "WARNING: Partial site directory exists without site_config.json (attempt ${ATTEMPT}/${MAX_ATTEMPTS})."
    if [ "$ATTEMPT" -ge "$MAX_ATTEMPTS" ]; then
        log "FATAL: Max retry attempts (${MAX_ATTEMPTS}) reached. Manual intervention required."
        log "Run: docker exec <container> rm -rf /home/frappe/frappe-bench/sites/${SITE_NAME}"
        log "Then restart the container."
        echo "$MAX_ATTEMPTS" > "$ATTEMPT_FILE"
        exec tail -f /dev/null
    fi
    ATTEMPT=$((ATTEMPT + 1))
    echo "$ATTEMPT" > "$ATTEMPT_FILE"
    cleanup_partial_site
fi

if [ ! -f "sites/${SITE_NAME}/site_config.json" ]; then
    echo "$ATTEMPT" > "$ATTEMPT_FILE"
    
    # Pre-flight: if site dir still exists (e.g. backups mount point), force drop first
    if [ -d "sites/${SITE_NAME}" ]; then
        log "Site directory still exists after cleanup. Attempting bench drop-site as pre-flight..."
        bench drop-site "$SITE_NAME" --root-password "$DB_ROOT_PASSWORD" 2>&1 | while IFS= read -r line; do log "  $line"; done || true
    fi
    
    log "Creating new site: ${SITE_NAME} (attempt ${ATTEMPT}/${MAX_ATTEMPTS})..."
    NEW_SITE_LOG="/home/frappe/frappe-bench/new-site-output.log"
    su -s /bin/bash frappe -c "HOME=/home/frappe bench new-site $SITE_NAME --db-host $DB_HOST --db-port $DB_PORT --mariadb-root-password '$DB_ROOT_PASSWORD' --admin-password '$ADMIN_PASSWORD' --no-mariadb-socket" > "$NEW_SITE_LOG" 2>&1
    NEW_SITE_EXIT=$?
    cat "$NEW_SITE_LOG" >> "$LOGFILE"

    log "bench new-site exit code: ${NEW_SITE_EXIT}"
    log "bench new-site output lines: $(wc -l < "$NEW_SITE_LOG")"

    if [ $NEW_SITE_EXIT -ne 0 ]; then
        log 'ERROR: bench new-site returned non-zero exit code!'
        log '--- RAW bench new-site output (last 50 lines) ---'
        tail -50 "$NEW_SITE_LOG" | while IFS= read -r line; do log "  $line"; done
        log '--- END RAW output ---'
    fi

    if [ ! -f "sites/${SITE_NAME}/site_config.json" ]; then
        log 'FATAL: bench new-site failed — site_config.json not found after creation.'
        log '--- FULL bench new-site output ---'
        cat "$NEW_SITE_LOG" >> "$LOGFILE"
        log '--- END FULL output ---'
        log 'Attempting cleanup of partial database and directory...'
        cleanup_partial_site
        if [ "$ATTEMPT" -ge "$MAX_ATTEMPTS" ]; then
            log "FATAL: Max retry attempts (${MAX_ATTEMPTS}) reached. Manual intervention required."
            exec tail -f /dev/null
        fi
        ATTEMPT=$((ATTEMPT + 1))
        echo "$ATTEMPT" > "$ATTEMPT_FILE"
        log "Will retry on next container restart."
        exit 1
    fi
    echo "0" > "$ATTEMPT_FILE"
    log 'Site created successfully.'

    log 'Configuring Redis...'
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
" 2>&1 | tee -a "$LOGFILE"

    log 'Configuring wkhtmltopdf for PDF generation...'
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
" 2>&1 | tee -a "$LOGFILE"

    APPS=("erpnext" "hrms" "education" "drive" "lawnhive_branding" "license_control")
    for app in "${APPS[@]}"; do
        log "Installing ${app}..."
        bench --site "$SITE_NAME" install-app "$app" 2>&1 | tee -a "$LOGFILE"
        if [ $? -ne 0 ]; then
            log "WARNING: install-app ${app} failed (non-fatal, continuing)"
        fi
    done

    log 'Building assets...'
    bench build 2>&1 | tee -a "$LOGFILE" || true

    log 'Applying LawnHive branding...'
    bench --site "$SITE_NAME" execute lawnhive_branding.setup.after_install 2>&1 | tee -a "$LOGFILE" || true

    log 'Setting up Student Health Record feature...'
    bench --site "$SITE_NAME" execute lawnhive_branding.education_health.setup.setup_all 2>&1 | tee -a "$LOGFILE" || true

    log 'Setting default workspace...'
    bench --site "$SITE_NAME" execute "
import frappe
frappe.db.set_single_value('System Settings', 'app_name', 'LawnHive Workspace')
frappe.db.commit()
" 2>&1 | tee -a "$LOGFILE" || true

    log 'Initial setup complete.'
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

#!/bin/bash
# Automated backup script for LawnHive Workspace
# Runs daily via cron inside the Frappe container

set -e

SITE="site1.local"
BACKUP_DIR="/home/frappe/frappe-bench/sites/${SITE}/private/backups"
LOG_FILE="/home/frappe/frappe-bench/logs/backup.log"
MAX_BACKUPS=7  # Keep last 7 backups

mkdir -p "$BACKUP_DIR"

echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting backup..." >> "$LOG_FILE"

cd /home/frappe/frappe-bench

bench --site "$SITE" backup --compress 2>> "$LOG_FILE"

# Remove old backups older than MAX_BACKUPS days
find "$BACKUP_DIR" -name "*.sql.gz" -mtime +${MAX_BACKUPS} -delete 2>/dev/null
find "$BACKUP_DIR" -name "*.json" -mtime +${MAX_BACKUPS} -delete 2>/dev/null
find "$BACKUP_DIR" -name "*.tar" -mtime +${MAX_BACKUPS} -delete 2>/dev/null

echo "$(date '+%Y-%m-%d %H:%M:%S') - Backup completed." >> "$LOG_FILE"

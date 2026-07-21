#!/bin/bash
set -e

SITE="site1.local"
BACKUP_DIR="/home/frappe/frappe-bench/sites/${SITE}/private/backups"
MAX_BACKUPS=7

mkdir -p "$BACKUP_DIR"

echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting backup..."

cd /home/frappe/frappe-bench
bench --site "$SITE" backup --compress

# Remove old backups older than MAX_BACKUPS days
find "$BACKUP_DIR" -name "*.sql.gz" -mtime +${MAX_BACKUPS} -delete 2>/dev/null || true
find "$BACKUP_DIR" -name "*.json" -mtime +${MAX_BACKUPS} -delete 2>/dev/null || true
find "$BACKUP_DIR" -name "*.tar" -mtime +${MAX_BACKUPS} -delete 2>/dev/null || true

echo "$(date '+%Y-%m-%d %H:%M:%S') - Backup completed."

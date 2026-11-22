#!/usr/bin/env bash
# Nightly backup of the Notesnook sync server.
# Saves a compressed MongoDB dump plus a copy of the attachments folder, and
# keeps the last KEEP_DAYS days. Run from cron (see the guide).
#
# Note: notes and attachments are end-to-end encrypted, so these backups are
# only readable together with your Notesnook password. They protect you from
# a broken server, not from a forgotten password.
#
# Database dumps are kept for KEEP_DAYS days. Attachments are a single mirror
# (backups/s3/current/) that follows the live folder, so an attachment deleted
# in the apps disappears from the mirror at the next run.
#
# Needs rsync:  sudo apt install -y rsync

set -euo pipefail

STACK_DIR="$(cd "$(dirname "$0")" && pwd)"   # folder with docker-compose.yml and .env
cd "$STACK_DIR"

# Read NOTESNOOK_DATA_DIR from .env
NOTESNOOK_DATA_DIR="$(grep -E '^NOTESNOOK_DATA_DIR=' .env | cut -d= -f2-)"
BACKUP_DIR="${BACKUP_DIR:-$NOTESNOOK_DATA_DIR/backups}"
KEEP_DAYS="${KEEP_DAYS:-14}"
STAMP="$(date +%Y-%m-%d_%H%M)"

command -v rsync >/dev/null || { echo "Backup FAILED: rsync is not installed (sudo apt install -y rsync)" >&2; exit 1; }

mkdir -p "$BACKUP_DIR/db" "$BACKUP_DIR/s3"

# 1. Database dump (consistent snapshot while the server keeps running)
docker compose exec -T notesnook-db mongodump --quiet --archive --gzip \
  > "$BACKUP_DIR/db/notesnook-db_$STAMP.archive.gz"

# Refuse to keep an empty/failed dump
if [ ! -s "$BACKUP_DIR/db/notesnook-db_$STAMP.archive.gz" ]; then
  echo "Backup FAILED: database dump is empty" >&2
  rm -f "$BACKUP_DIR/db/notesnook-db_$STAMP.archive.gz"
  exit 1
fi

# 2. Attachments (mirror of the Silo data folder)
rsync -a --delete "$NOTESNOOK_DATA_DIR/s3/" "$BACKUP_DIR/s3/current/"

# 3. Remove database dumps older than KEEP_DAYS
find "$BACKUP_DIR/db" -name 'notesnook-db_*.archive.gz' -mtime +"$KEEP_DAYS" -delete

echo "Backup OK: $BACKUP_DIR/db/notesnook-db_$STAMP.archive.gz"

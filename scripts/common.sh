#!/usr/bin/env bash
# Shared settings and helpers. Sourced by every script in this folder.
# Settings come from /etc/pg-backup/backup.env if it exists, otherwise the defaults below.
# Any setting can also be overridden with an environment variable for a single run.

CONFIG_FILE="${CONFIG_FILE:-/etc/pg-backup/backup.env}"
if [[ -f "$CONFIG_FILE" ]]; then
    # Read KEY=value lines, but don't overwrite a variable that is already set in the environment.
    # That way "DATABASES=testdb ./pg_logical_backup.sh" works for a one-off run.
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]] || continue      # skip comments and blank lines
        [[ -n "${!key+set}" ]] && continue
        eval "$key=$value"
    done < "$CONFIG_FILE"
fi

BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/postgres}"
WAL_ARCHIVE="${WAL_ARCHIVE:-/var/lib/pgsql/wal_archive}"
DATABASES="${DATABASES:-shopdb}"
LOGICAL_RETENTION_DAYS="${LOGICAL_RETENTION_DAYS:-7}"
BASE_BACKUPS_TO_KEEP="${BASE_BACKUPS_TO_KEEP:-2}"
MAX_BACKUP_AGE_HOURS="${MAX_BACKUP_AGE_HOURS:-26}"
METRICS_DIR="${METRICS_DIR:-}"          # set to node_exporter's textfile dir in project 4
LOG_FILE="${LOG_FILE:-$BACKUP_ROOT/logs/backup.log}"

export PGHOST="${PGHOST:-/var/run/postgresql}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-postgres}"

mkdir -p "$(dirname "$LOG_FILE")"

log() {
    local level="$1"; shift
    printf '%s [%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$(basename "$0")" "$*" | tee -a "$LOG_FILE" >&2
}

die() {
    log ERROR "$*"
    exit 1
}

timestamp() {
    date '+%Y%m%d_%H%M%S'
}

# Write one Prometheus metric line to a .prom file (used by node_exporter's textfile collector).
# Does nothing unless METRICS_DIR is set.
write_metric() {
    local file="$1" name="$2" value="$3" help="$4"
    [[ -z "$METRICS_DIR" ]] && return 0
    local base="${name%%\{*}"            # HELP/TYPE lines take the name without {labels}
    mkdir -p "$METRICS_DIR"
    {
        echo "# HELP $base $help"
        echo "# TYPE $base gauge"
        echo "$name $value"
    } > "$METRICS_DIR/$file.tmp"
    mv "$METRICS_DIR/$file.tmp" "$METRICS_DIR/$file"   # atomic swap so node_exporter never reads half a file
}

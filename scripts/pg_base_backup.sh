#!/usr/bin/env bash
# Physical base backup of the whole cluster with pg_basebackup.
#
# A base backup + the archived WAL files after it = point-in-time recovery (PITR).
# This script:
#   1. takes a compressed tar-format base backup into $BACKUP_ROOT/base/<timestamp>/
#   2. keeps only the newest $BASE_BACKUPS_TO_KEEP base backups
#   3. removes archived WAL that is older than the oldest base backup still kept
#      (that WAL can no longer be used by any backup we have)

set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/common.sh"

ts="$(timestamp)"
target="$BACKUP_ROOT/base/$ts"
mkdir -p "$BACKUP_ROOT/base"

log INFO "Starting base backup into $target"
start=$(date +%s)

# -Ft   tar format          -z  gzip compressed
# -Xs   stream the WAL needed to make this backup consistent on its own
# --checkpoint=fast  start right away instead of waiting for the next scheduled checkpoint
if ! pg_basebackup -D "$target.partial" -Ft -z -Xs --checkpoint=fast --label="base_$ts"; then
    rm -rf "$target.partial"
    die "pg_basebackup failed"
fi
mv "$target.partial" "$target"
(cd "$target" && sha256sum ./*.tar.gz > SHA256SUMS)

secs=$(( $(date +%s) - start ))
log INFO "Base backup finished: $target ($(du -sh "$target" | cut -f1), ${secs}s)"

# --- Retention for base backups ---
mapfile -t backups < <(find "$BACKUP_ROOT/base" -mindepth 1 -maxdepth 1 -type d ! -name '*.partial' | sort)
count=${#backups[@]}
if (( count > BASE_BACKUPS_TO_KEEP )); then
    for old in "${backups[@]:0:count-BASE_BACKUPS_TO_KEEP}"; do
        rm -rf "$old"
        log INFO "Retention removed base backup $old"
    done
fi

# --- WAL cleanup ---
# Each base backup leaves a small "*.backup" history file in the WAL archive.
# The oldest base backup we still keep matches the N-th newest of those files.
# pg_archivecleanup removes every WAL segment older than it.
if [[ -d "$WAL_ARCHIVE" ]]; then
    mapfile -t history < <(find "$WAL_ARCHIVE" -maxdepth 1 -name '*.backup' -printf '%f\n' | sort)
    hcount=${#history[@]}
    if (( hcount >= BASE_BACKUPS_TO_KEEP )); then
        keep_from="${history[hcount-BASE_BACKUPS_TO_KEEP]}"
        log INFO "Removing archived WAL older than $keep_from"
        pg_archivecleanup "$WAL_ARCHIVE" "$keep_from"
        # also drop the history files of backups we deleted
        for h in "${history[@]:0:hcount-BASE_BACKUPS_TO_KEEP}"; do rm -f "$WAL_ARCHIVE/$h"; done
    fi
else
    log WARN "WAL archive $WAL_ARCHIVE not found. Is archive_mode on? (see labs/03)"
fi

write_metric "pg_base_backup.prom" "pg_base_backup_last_success_timestamp_seconds" \
    "$(date +%s)" "Unix time of the last successful base backup"

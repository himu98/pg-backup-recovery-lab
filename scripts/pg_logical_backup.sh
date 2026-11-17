#!/usr/bin/env bash
# Logical backup of each database with pg_dump (custom format).
#
# For every database in $DATABASES it:
#   1. records row counts per table (the restore drill compares against these)
#   2. dumps the database to <db>_<timestamp>.dump
#   3. writes a sha256 checksum next to the dump
#   4. checks the dump is readable with pg_restore --list
#   5. deletes dumps older than $LOGICAL_RETENTION_DAYS
#
# Exit code is non-zero if any database fails, so systemd marks the run as failed.

set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/common.sh"

failures=0
current_dump=""

backup_one() {
    local db="$1"
    local dir="$BACKUP_ROOT/logical/$db"
    local ts; ts="$(timestamp)"
    local dump="$dir/${db}_${ts}.dump"
    current_dump="$dump"          # global, so the caller can clean up if this run fails
    mkdir -p "$dir"

    log INFO "Starting logical backup of '$db'"
    local start; start=$(date +%s)

    # Note: because backup_one is called inside "if !", bash switches off set -e in here.
    # So every step that can fail has its own "|| return 1". Learned this the hard way in testing.

    psql -X -At -d "$db" -c "SELECT 1" > /dev/null || { log ERROR "Cannot connect to '$db'"; return 1; }

    # Row counts at backup time. There is a small gap between this query and pg_dump's snapshot,
    # so on a busy database the numbers can be slightly off. Fine for a lab; see docs/CONCEPTS.md.
    local tables
    tables=$(psql -X -At -d "$db" -c "SELECT format('%s.%s', schemaname, relname) FROM pg_stat_user_tables ORDER BY 1") || return 1
    : > "$dump.counts"
    for table in $tables; do
        printf '%s %s\n' "$table" "$(psql -X -At -d "$db" -c "SELECT count(*) FROM $table")" >> "$dump.counts" || return 1
    done

    # Dump to a temp name first, rename only on success, so a half-written file never looks like a backup.
    pg_dump -d "$db" -Fc -f "$dump.partial" || return 1
    mv "$dump.partial" "$dump" || return 1

    (cd "$dir" && sha256sum "$(basename "$dump")" > "$(basename "$dump").sha256") || return 1

    pg_restore --list "$dump" > /dev/null || { log ERROR "pg_restore cannot read $dump"; return 1; }

    local secs=$(( $(date +%s) - start ))
    local size; size=$(du -h "$dump" | cut -f1)
    log INFO "Finished '$db': $dump ($size, ${secs}s)"

    # Retention: remove dumps (and their sidecar files) older than N days.
    find "$dir" -name "${db}_*.dump*" -mtime +"$LOGICAL_RETENTION_DAYS" -print -delete |
        while read -r f; do log INFO "Retention removed $f"; done

    write_metric "pg_logical_backup_${db}.prom" "pg_logical_backup_last_success_timestamp_seconds{db=\"$db\"}" \
        "$(date +%s)" "Unix time of the last successful logical backup"
}

for db in $DATABASES; do
    if ! backup_one "$db"; then
        log ERROR "Backup of '$db' FAILED"
        # remove the leftovers of the failed run so they never look like a backup
        rm -f "$current_dump" "$current_dump.partial" "$current_dump.counts" "$current_dump.sha256"
        rmdir "$BACKUP_ROOT/logical/$db" 2>/dev/null || true
        failures=$((failures + 1))
    fi
done

if (( failures > 0 )); then
    die "$failures database(s) failed to back up"
fi
log INFO "All logical backups completed"

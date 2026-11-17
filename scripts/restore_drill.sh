#!/usr/bin/env bash
# Restore drill: prove the latest logical backup actually restores.
#
# A backup you have never restored is a hope, not a backup. For each database this:
#   1. finds the newest dump and verifies its sha256 checksum
#   2. restores it into a throwaway database (drill_<db>)
#   3. compares row counts per table with the counts recorded at backup time
#   4. measures how long the restore took (your real RTO for this database size)
#   5. writes a markdown report to $BACKUP_ROOT/reports/ and drops the throwaway database
#
# It never touches the real database.

set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/common.sh"

export PGOPTIONS="-c client_min_messages=warning"   # hide harmless NOTICE lines
report_dir="$BACKUP_ROOT/reports"
mkdir -p "$report_dir"
report="$report_dir/drill_$(timestamp).md"
overall=PASS

{
    echo "# Restore drill report"
    echo
    echo "- Host: $(hostname)"
    echo "- Started: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo
} > "$report"

drill_one() {
    local db="$1"
    local dir="$BACKUP_ROOT/logical/$db"
    local dump
    dump=$(find "$dir" -maxdepth 1 -name "${db}_*.dump" 2>/dev/null | sort | tail -n 1)
    [[ -n "$dump" ]] || { log ERROR "No dump found for '$db' in $dir"; echo "## $db: FAIL (no backup found)" >> "$report"; return 1; }

    log INFO "Drill for '$db' using $dump"

    (cd "$dir" && sha256sum --quiet -c "$(basename "$dump").sha256") ||
        { echo "## $db: FAIL (checksum mismatch, backup file is damaged)" >> "$report"; return 1; }

    local scratch="drill_${db}"
    psql -X -q -d postgres -c "DROP DATABASE IF EXISTS $scratch" -c "CREATE DATABASE $scratch"

    local start end
    start=$(date +%s.%N)
    pg_restore -d "$scratch" --no-owner --exit-on-error "$dump"
    end=$(date +%s.%N)
    local secs; secs=$(awk -v a="$start" -v b="$end" 'BEGIN { printf "%.1f", b - a }')

    local status=PASS
    {
        echo "## $db"
        echo
        echo "- Backup file: \`$(basename "$dump")\` ($(du -h "$dump" | cut -f1))"
        echo "- Backup age: $(( ( $(date +%s) - $(stat -c %Y "$dump") ) / 3600 )) hours"
        echo "- Restore time: **${secs}s**"
        echo
        echo "| Table | Rows at backup | Rows restored | Match |"
        echo "|---|---|---|---|"
    } >> "$report"

    while read -r table expected; do
        local actual
        actual=$(psql -X -At -d "$scratch" -c "SELECT count(*) FROM $table")
        local ok="yes"
        if [[ "$actual" != "$expected" ]]; then ok="**NO**"; status=FAIL; fi
        echo "| $table | $expected | $actual | $ok |" >> "$report"
    done < "$dump.counts"

    echo >> "$report"
    echo "Result: **$status**" >> "$report"
    echo >> "$report"

    psql -X -q -d postgres -c "DROP DATABASE $scratch"
    log INFO "Drill for '$db': $status (restore took ${secs}s)"

    write_metric "pg_restore_drill_${db}.prom" "pg_restore_drill_seconds{db=\"$db\"}" "$secs" \
        "Seconds the last restore drill took"
    [[ "$status" == PASS ]]
}

for db in $DATABASES; do
    drill_one "$db" || overall=FAIL
done

echo "**Overall: $overall**" >> "$report"
log INFO "Report written to $report"
cat "$report"
[[ "$overall" == PASS ]] || die "Restore drill FAILED, read $report"

#!/usr/bin/env bash
# Alert when backups STOP happening.
#
# The most common backup failure is not a crash. The cron job or timer quietly stops running
# (disk full, password changed, someone disabled it) and nobody notices until the restore day.
# Same idea as silent-failure-monitor: watch for the thing that should happen and didn't.
#
# Exit 0 = every database has a dump newer than $MAX_BACKUP_AGE_HOURS. Exit 1 = at least one is stale.

set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/common.sh"

stale=0
now=$(date +%s)

for db in $DATABASES; do
    newest=$(find "$BACKUP_ROOT/logical/$db" -maxdepth 1 -name "${db}_*.dump" -printf '%T@ %p\n' 2>/dev/null |
             sort -n | tail -n 1)
    if [[ -z "$newest" ]]; then
        log ERROR "STALE: no backup at all for '$db'"
        stale=1
        continue
    fi
    age_h=$(( (now - ${newest%%.*}) / 3600 ))
    if (( age_h > MAX_BACKUP_AGE_HOURS )); then
        log ERROR "STALE: newest backup for '$db' is ${age_h}h old (limit ${MAX_BACKUP_AGE_HOURS}h)"
        stale=1
    else
        log INFO "OK: '$db' newest backup is ${age_h}h old"
    fi
done

write_metric "pg_backup_freshness.prom" "pg_backup_stale" "$stale" "1 if any database backup is older than the limit"
exit $stale

#!/usr/bin/env bash
# Point-in-time recovery into a SEPARATE data directory, started on a separate port.
#
# Usage:
#   sudo -u postgres ./pitr_restore.sh <base_backup_dir> "<target time>" [new_datadir] [port]
#   sudo -u postgres ./pitr_restore.sh /var/backups/postgres/base/20261118_101500 "2026-11-18 10:42:00"
#
# Why a separate directory: you never overwrite the live server while you are still working out
# what happened. You restore beside it, check the data, and only then decide what to do.
# (Do this by hand first, labs/04 walks through it, then use this script.)

set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/common.sh"

base_dir="${1:?base backup directory required}"
target_time="${2:?target time required, e.g. \"2026-11-18 10:42:00\"}"
new_datadir="${3:-/var/lib/pgsql/pitr_restore}"
port="${4:-5433}"
PG_BIN="${PG_BIN:-$(dirname "$(command -v pg_ctl)")}"

[[ -f "$base_dir/base.tar.gz" ]] || die "$base_dir/base.tar.gz not found"
[[ -d "$WAL_ARCHIVE" ]] || die "WAL archive $WAL_ARCHIVE not found"
if [[ -e "$new_datadir" && -n "$(ls -A "$new_datadir" 2>/dev/null)" ]]; then
    die "$new_datadir is not empty. Stop any server using it and remove it first."
fi

(cd "$base_dir" && sha256sum --quiet -c SHA256SUMS) || die "Base backup checksum mismatch"

log INFO "Extracting base backup into $new_datadir"
mkdir -p "$new_datadir"
chmod 700 "$new_datadir"
tar -xzf "$base_dir/base.tar.gz" -C "$new_datadir"
tar -xzf "$base_dir/pg_wal.tar.gz" -C "$new_datadir/pg_wal"

# The restored copy must not archive into the real archive (it would mix two timelines' files)
# and must listen on its own port.
cat >> "$new_datadir/postgresql.auto.conf" <<EOF

# ---- added by pitr_restore.sh ----
port = $port
archive_mode = off
restore_command = 'cp $WAL_ARCHIVE/%f %p'
recovery_target_time = '$target_time'
recovery_target_action = 'promote'
EOF

# recovery.signal tells PostgreSQL: start in recovery mode and replay WAL up to the target.
touch "$new_datadir/recovery.signal"

log INFO "Starting recovered server on port $port (target: $target_time)"
"$PG_BIN/pg_ctl" -D "$new_datadir" -l "$new_datadir/recovery.log" -o "-c unix_socket_directories=$PGHOST" -w -t 120 start

# Wait until recovery finishes and the server is promoted to read-write.
for _ in $(seq 1 60); do
    if [[ "$(psql -X -At -p "$port" -d postgres -c 'SELECT pg_is_in_recovery()' 2>/dev/null)" == "f" ]]; then
        log INFO "Recovery complete. Inspect with: psql -p $port -d <db>"
        log INFO "Stop it with: $PG_BIN/pg_ctl -D $new_datadir stop"
        exit 0
    fi
    sleep 2
done
die "Server did not finish recovery, read $new_datadir/recovery.log"

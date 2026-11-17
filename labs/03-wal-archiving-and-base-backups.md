# Lab 03: WAL archiving and base backups

**Time:** about 1 hour  **Concepts:** section 3 of `docs/CONCEPTS.md` (read it again now)

**Goal:** every finished WAL segment gets copied to `/var/lib/pgsql/wal_archive`, and you have a base backup to replay it onto.

---

## 1. Create the archive directory

```bash
sudo -u postgres mkdir -p /var/lib/pgsql/wal_archive
sudo -u postgres chmod 700 /var/lib/pgsql/wal_archive
```

**Why inside `/var/lib/pgsql` and not `/var/backups`?** On AlmaLinux, SELinux confines the PostgreSQL server process. It's allowed to write to locations labelled `postgresql_db_t`, which includes `/var/lib/pgsql`. Check it:
```bash
ls -Zd /var/lib/pgsql /var/lib/pgsql/wal_archive /var/backups/postgres
```
(Optional, after the lab: point archive_command at `/var/backups/postgres/wal` instead, watch it fail, and find the denial with `sudo ausearch -m avc -ts recent`. That's a great "what broke" entry.)

## 2. Turn archiving on

Read `config/postgresql-archiving.conf`, every comment. Then add it to the end of the config:
```bash
sudo bash -c 'cat /opt/pg-backup-recovery-lab/config/postgresql-archiving.conf >> /var/lib/pgsql/data/postgresql.conf'
```

**Predict:** will `sudo systemctl reload postgresql` be enough? Try it and check:
```bash
sudo systemctl reload postgresql
sudo -u postgres psql -c "SHOW archive_mode;"
sudo -u postgres psql -c "SELECT name, setting, pending_restart FROM pg_settings WHERE name LIKE 'archive%';"
```
Read `pending_restart`. Then:
```bash
sudo systemctl restart postgresql
sudo -u postgres psql -c "SHOW archive_mode;"
```

## 3. Watch it work

```bash
sudo -u postgres psql -c "SELECT pg_switch_wal();"     # finish the current segment now
sudo ls -la /var/lib/pgsql/wal_archive/
sudo -u postgres psql -x -c "SELECT * FROM pg_stat_archiver;"
```
`pg_stat_archiver` is what you'd monitor in production: `failed_count` and `last_failed_time` should stay empty. Remember this view for the observability project.

## 4. Base backup by hand

```bash
sudo -u postgres pg_basebackup -D /var/backups/postgres/manual/base1 -Ft -z -Xs -P --checkpoint=fast
sudo ls -lh /var/backups/postgres/manual/base1/
sudo ls /var/lib/pgsql/wal_archive/ | grep backup
sudo cat /var/lib/pgsql/wal_archive/*.backup
```
Explain each file in `base1/`, and what the `.backup` file in the archive records (START WAL LOCATION, STOP WAL LOCATION).

## 5. The script

Read `scripts/pg_base_backup.sh`, especially the WAL cleanup part. Answer: **why is it safe to delete WAL older than the oldest base backup we keep, and dangerous to delete anything newer?**

```bash
sudo -u postgres /opt/pg-backup-recovery-lab/scripts/pg_base_backup.sh
sudo -u postgres /opt/pg-backup-recovery-lab/scripts/pg_base_backup.sh
sudo -u postgres /opt/pg-backup-recovery-lab/scripts/pg_base_backup.sh
sudo ls /var/backups/postgres/base/
sudo ls /var/lib/pgsql/wal_archive/
```
With `BASE_BACKUPS_TO_KEEP=2`, how many base backups remain? Which WAL files were removed? Does that match what you predicted?

---

### Break it

**Make archiving fail on purpose.** It's the most important failure to understand.
```bash
sudo chmod 000 /var/lib/pgsql/wal_archive
sudo -u postgres psql -c "SELECT pg_switch_wal();"
sudo -u postgres psql -x -c "SELECT archived_count, failed_count, last_failed_wal FROM pg_stat_archiver;"
sudo journalctl -u postgresql --since "5 min ago" | tail -20
sudo ls /var/lib/pgsql/data/pg_wal/archive_status/
```
What do the `.ready` files in `archive_status/` mean? Switch WAL a few more times and watch `pg_wal/` grow. **Has any data been lost?** (Answer from CONCEPTS.md question 3.) Then fix it:
```bash
sudo chmod 700 /var/lib/pgsql/wal_archive
```
and watch PostgreSQL catch up by itself.

**Done when:** `pg_stat_archiver` shows archived files and 0 recent failures, you have 2 base backups from the script, and you saw (and fixed) a failing archive.

# Lab 04: Point-in-time recovery. Undo a DELETE that was run by mistake

**Time:** about 1.5 hours  **Concepts:** sections 3 and 4 of `docs/CONCEPTS.md`

**The scenario:** live orders keep coming in. At some moment, someone runs `DELETE FROM orders;` without a WHERE clause. You need every order up to the second before the DELETE, including the ones placed *after* the last backup. `pg_dump` can't do that. Only PITR can.

You'll restore **beside** the live server (new data directory, port 5433). You never overwrite production while you're still investigating.

---

## 1. Set the stage

Make sure there's a recent base backup (Lab 03). Then generate live traffic for about a minute:
```bash
cd /opt/pg-backup-recovery-lab
for i in $(seq 1 30); do sudo -u postgres psql -q -d shopdb -f sql/03_live_orders.sql; sleep 2; done
```

Note the last good state:
```bash
sudo -u postgres psql -d shopdb -c "SELECT count(*), max(order_id), now() FROM orders;"
```
**Write down the count, max(order_id) and the time.** Wait 10 seconds.

## 2. The disaster

```bash
sudo -u postgres psql -d shopdb -c "DELETE FROM orders;"
sudo -u postgres psql -d shopdb -c "SELECT count(*) FROM orders;"
sudo -u postgres psql -c "SELECT pg_switch_wal();"
```
Why switch WAL here? (The segment containing the minutes *before* the DELETE must be in the archive, or recovery can't reach them.)

## 3. Recover by hand

Use the newest base backup:
```bash
sudo ls /var/backups/postgres/base/
BASE=/var/backups/postgres/base/<newest>
NEW=/var/lib/pgsql/pitr_manual
```

```bash
sudo -u postgres mkdir -p $NEW
sudo -u postgres chmod 700 $NEW
sudo -u postgres tar -xzf $BASE/base.tar.gz -C $NEW
sudo -u postgres tar -xzf $BASE/pg_wal.tar.gz -C $NEW/pg_wal
```

Add recovery settings. Use the time you wrote down in step 1 (a few seconds **before** the DELETE):
```bash
sudo -u postgres bash -c "cat >> $NEW/postgresql.auto.conf" <<'EOF'
port = 5433
archive_mode = off
restore_command = 'cp /var/lib/pgsql/wal_archive/%f %p'
recovery_target_time = '2026-11-18 10:41:59'
recovery_target_action = 'promote'
EOF
sudo -u postgres touch $NEW/recovery.signal
```
Before starting, answer: **why `archive_mode = off` on the restored copy?** (Hint: which directory would it archive into, and on which timeline?)

Start it:
```bash
sudo -u postgres pg_ctl -D $NEW -l $NEW/recovery.log start
sudo -u postgres tail -30 $NEW/recovery.log
```
Find the lines `starting point-in-time recovery to ...`, `restored log file ... from archive`, `recovery stopping before commit of transaction ...` and `selected new timeline ID: 2`. Explain each one.

Check:
```bash
sudo -u postgres psql -p 5433 -d shopdb -c "SELECT count(*), max(order_id) FROM orders;"
```
**Does it match what you wrote down?** Orders placed after the base backup and before the DELETE should be there. That's WAL replay at work.

## 4. Getting the data back into production

You have three options. Write down the trade-off of each in your results:
1. **Copy the rows back:** `pg_dump -p 5433 -t orders --data-only` and then load them into the live DB. Keeps orders placed after the DELETE. You have to handle duplicate keys.
2. **Swap servers:** stop the live server, make the restored copy the new primary. Loses anything written after your target time.
3. **Point the app at 5433** temporarily. The fastest RTO, but messy.

Do option 1 for real:
```bash
sudo -u postgres pg_dump -p 5433 -d shopdb -t orders --data-only -Fc -f /tmp/orders_recovered.dump
sudo -u postgres pg_restore -d shopdb --data-only /tmp/orders_recovered.dump
sudo -u postgres psql -d shopdb -c "SELECT count(*) FROM orders;"
sudo -u postgres psql -d shopdb -c "SELECT setval('orders_order_id_seq', (SELECT max(order_id) FROM orders));"
```
Why the `setval`? What would the next INSERT do without it?

Clean up:
```bash
sudo -u postgres pg_ctl -D $NEW stop
sudo -u postgres rm -rf $NEW
```

## 5. Time the whole thing

Do the scenario again from step 1, this time with the script, and **time it from DELETE to verified data**:
```bash
sudo -u postgres /opt/pg-backup-recovery-lab/scripts/pitr_restore.sh $BASE "<target time>"
```
Record both times (by hand and with the script) in `results/RESULTS.md`. That's your measured PITR RTO.

---

### Break it

- Set `recovery_target_time` to a time **before** the base backup was taken. Read the error in `recovery.log`. Why is that impossible?
- Hide one WAL file from the archive (`mv` it away) before recovering. What does recovery do when the chain has a gap? Put it back after.
- If the server fails to start on 5433 with a permission error, check SELinux: `sudo ausearch -m avc -ts recent`. (Port 5433 isn't labelled for PostgreSQL by default. Look up `semanage port`.)

**Done when:** you recovered the deleted orders to the exact second, got them back into the live DB, and have timed RTO numbers.

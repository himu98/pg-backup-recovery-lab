# Lab 02: Logical backups with pg_dump, and a real restore

**Time:** about 1 hour  **Concepts:** section 2 of `docs/CONCEPTS.md`

**Goal:** take a backup by hand, lose a table, get it back. Then do the same with `pg_logical_backup.sh` and `restore_drill.sh`, and understand every line of both.

---

## 1. By hand first

```bash
sudo mkdir -p /var/backups/postgres/manual
sudo chown -R postgres:postgres /var/backups/postgres
sudo chmod 700 /var/backups/postgres

sudo -u postgres pg_dump -d shopdb -Fc -f /var/backups/postgres/manual/shopdb.dump
ls -lh /var/backups/postgres/manual/
```
**Predict first:** the database is about 10 MB. Will the dump be bigger or smaller? Why?

See what's inside without restoring:
```bash
sudo -u postgres pg_restore --list /var/backups/postgres/manual/shopdb.dump | head -30
```

## 2. Disaster: someone drops a table

```bash
sudo -u postgres psql -d shopdb -c "DROP TABLE orders;"
sudo -u postgres psql -d shopdb -c "\dt"
```

## 3. Restore only that table

```bash
sudo -u postgres pg_restore -d shopdb -t orders /var/backups/postgres/manual/shopdb.dump
sudo -u postgres psql -d shopdb -c "SELECT count(*) FROM orders;"
sudo -u postgres psql -d shopdb -c "\d orders"
```

Look closely at the `\d orders` output. **Are the indexes and the foreign keys back?** (`-t` restores the table and its data, but not everything attached to it.) Write down what's missing. Then fix it properly: drop the table again and restore with
```bash
sudo -u postgres pg_restore -l /var/backups/postgres/manual/shopdb.dump | grep -i orders
```
Use that list to work out which items you need, and look up `pg_restore -L` (restore from an edited list). This is a real-world gotcha, and a good interview story.

## 4. Now the script

Read `scripts/common.sh` and `scripts/pg_logical_backup.sh` top to bottom **before** running them. For each step, answer:
- Why does the dump go to `.partial` first and get renamed afterwards?
- Why record row counts *before* the dump?
- What is `pg_restore --list` proving?
- Why does the script exit with a non-zero code when one database fails? Who reads that exit code? (Lab 05)

Set up the config, then run it:
```bash
sudo mkdir -p /etc/pg-backup
sudo cp /opt/pg-backup-recovery-lab/config/backup.env.example /etc/pg-backup/backup.env
sudo -u postgres /opt/pg-backup-recovery-lab/scripts/pg_logical_backup.sh
sudo ls -la /var/backups/postgres/logical/shopdb/
sudo cat /var/backups/postgres/logical/shopdb/*.counts
```

## 5. Restore drill

```bash
sudo -u postgres /opt/pg-backup-recovery-lab/scripts/restore_drill.sh
```
Read the report. Copy the restore time into `results/RESULTS.md`.

Make the database bigger and measure again (run the seed 3–4 more times, then back up and drill again). Does restore time grow in a straight line with size? Record each size and time in the results table. **This is your measured RTO for a logical restore.**

---

### Break it

1. **Corrupt a backup.** Append junk to the newest dump:
   `sudo -u postgres bash -c 'echo garbage >> /var/backups/postgres/logical/shopdb/<newest>.dump'`
   Run the drill. Which check catches it? Would `pg_restore --list` alone have caught it?
2. **Back up a database that doesn't exist.** `sudo -u postgres env DATABASES="shopdb nosuchdb" /opt/pg-backup-recovery-lab/scripts/pg_logical_backup.sh; echo "exit code: $?"`
   Did `shopdb` still get backed up? What exit code did you get? Are there leftover files for `nosuchdb`?
3. Delete the bad dump from step 1 when you're done, then take a fresh backup.

**Done when:** you have restored a dropped table, know what `-t` leaves out, and have at least three size/time rows in your results.

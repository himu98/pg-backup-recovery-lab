# Lab 01: Install PostgreSQL 16 on AlmaLinux 9 and load sample data

**Time:** about 45 minutes  **VM:** AlmaLinux (`ssh -p 2223 <you>@localhost` from Windows Terminal)

**Goal:** a running PostgreSQL 16 server with a `shopdb` database holding about 52,000 rows, and an understanding of where PostgreSQL keeps its files.

> How to work through every lab: **type the commands yourself**, one at a time. Before each one, say what you expect to happen. When the result surprises you, that's the part to write down in `results/RESULTS.md`.

---

## 1. Install

```bash
sudo dnf module list postgresql
```
**Predict:** which versions will you see, and which is marked `[d]` (default)?

AlmaLinux ships several PostgreSQL versions as *modules*. We pick 16 explicitly instead of taking the default:

```bash
sudo dnf module enable -y postgresql:16
sudo dnf install -y postgresql-server postgresql-contrib git
```

`postgresql-contrib` gives us extra tools, including `pg_archivecleanup`, which Lab 03 needs.

## 2. Create the cluster and start it

```bash
sudo postgresql-setup --initdb
sudo systemctl enable --now postgresql
systemctl status postgresql
```

`initdb` creates a **cluster**: one data directory serving many databases. Find it:

```bash
sudo -u postgres psql -c "SHOW data_directory;"
sudo ls -la /var/lib/pgsql/data
```

Find these and write one line in your notes on what each is for: `postgresql.conf`, `pg_hba.conf`, `pg_wal/`, `base/`, `PG_VERSION`.

**Why `sudo -u postgres`?** On a fresh install, PostgreSQL trusts the Linux user `postgres` through "peer" authentication. Look at the `local` lines in `pg_hba.conf` to see it.

## 3. Get this repo onto the VM

```bash
sudo git clone https://github.com/himu98/pg-backup-recovery-lab.git /opt/pg-backup-recovery-lab
ls -la /opt/pg-backup-recovery-lab/scripts
```
Check that the scripts are executable (`x` in the permissions). If they aren't, think about why git might lose that, and fix it with `sudo chmod +x`.

## 4. Create and fill the database

```bash
sudo -u postgres createdb shopdb
sudo -u postgres psql -d shopdb -f /opt/pg-backup-recovery-lab/sql/01_schema.sql
sudo -u postgres psql -d shopdb -f /opt/pg-backup-recovery-lab/sql/02_seed.sql
```

Look around:
```bash
sudo -u postgres psql -d shopdb
```
```sql
\dt
\di
SELECT count(*) FROM orders;
SELECT pg_size_pretty(pg_database_size('shopdb'));
SELECT city, count(*), sum(amount) FROM orders JOIN customers USING (customer_id) GROUP BY city ORDER BY 3 DESC;
\q
```

## 5. Write it down

In `results/RESULTS.md`, fill in the "Environment" section: OS version (`cat /etc/os-release`), PostgreSQL version (`psql --version`), database size, row counts.

---

### Break it (do at least one)

- Stop PostgreSQL (`sudo systemctl stop postgresql`) and try `psql`. Read the exact error. What file is it looking for? Start it again.
- Run `psql -d shopdb` as your normal user, without `sudo -u postgres`. Read the error and explain it using `pg_hba.conf`.

**Done when:** you can explain what a "cluster" is and where its WAL lives, and `SELECT count(*) FROM orders` returns 50000.

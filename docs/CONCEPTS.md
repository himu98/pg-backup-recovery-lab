# Concepts: PostgreSQL backup and recovery

Read this before you touch the VM. Every lab assumes you know these ideas. You should be able to explain each section out loud in your own words. That's what an interviewer will ask you to do.

---

## 1. The two numbers every backup plan is judged by

**RPO (Recovery Point Objective):** how much data can you afford to lose? If the server dies at 14:00 and your last backup was 01:30, you lost 12.5 hours of orders. Your RPO is 12.5 hours.

**RTO (Recovery Time Objective):** how long until you're back up? It's the time from "the database is gone" to "users can work again". It includes noticing the failure, finding the right backup, restoring it and checking it.

A business picks the numbers ("we can lose at most 5 minutes of data and be down at most 1 hour"). The DBA designs a setup that meets them **and proves it with drills**. A promised RTO you've never measured is a guess.

> In this project you'll **measure** both and write the real numbers in the README.

---

## 2. Logical vs physical backups

| | Logical (`pg_dump`) | Physical (`pg_basebackup`) |
|---|---|---|
| What it copies | SQL-level objects: tables, rows, indexes as definitions | The raw data files of the whole cluster, byte for byte |
| Scope | One database (or one table) | Every database in the cluster |
| Restore | `pg_restore` into any server, even a newer PostgreSQL version | Only into the same major version, same architecture |
| Point-in-time recovery? | **No.** You get the moment the dump ran | **Yes**, combined with archived WAL |
| Restore speed on big DBs | Slow (rebuilds every index) | Fast (just copy files back) |
| Good for | Moving data, restoring one table, upgrades, small DBs | Disaster recovery, big DBs, low RPO |

Real setups use **both**, and so does this project:
- nightly `pg_dump`, so that "restore just the `customers` table from yesterday" is easy
- weekly `pg_basebackup` + continuous WAL archiving, so you can recover to any second

**`pg_dump` formats:** `-Fp` is plain SQL text. `-Fc` is custom format: compressed, and `pg_restore` can pick single tables out of it or restore in parallel. We use `-Fc`.

---

## 3. WAL: the idea that makes everything work

**WAL = Write-Ahead Log.** Before PostgreSQL changes a data file, it first writes a record of the change into the WAL. The rule is *log first, data later*.

Why? If the power cuts mid-write, the data files may be half-updated. On restart, PostgreSQL replays the WAL from the last **checkpoint** and the data files become consistent again. That's crash recovery, and it happens every time PostgreSQL starts after a crash.

WAL lives in `pg_wal/` as **16 MB segment files** with names like `000000010000000000000007`:
- the first 8 hex digits are the **timeline** (more on that below)
- the rest is the position in the log, and it only ever counts up

Once a checkpoint has passed, old segments aren't needed for crash recovery, so PostgreSQL recycles them.

**The big idea:** if instead of recycling them you *copy every segment somewhere safe* (that's **WAL archiving**), you have a complete record of every change ever made. Take one physical copy of the data files (a **base backup**), replay archived WAL on top of it, and you can roll forward to **any moment you choose**. That's **Point-In-Time Recovery (PITR)**.

```
base backup (Sunday 02:30)
      |
      +-- WAL seg 07 -- WAL seg 08 -- WAL seg 09 -- ... -- WAL seg 2F
                                         ^
                                         |
                    "replay up to Tue 10:41:59, the second before someone ran DELETE"
```

### Settings involved
- `wal_level = replica`: write enough detail into WAL to rebuild data (the default since PG 10)
- `archive_mode = on`: turn archiving on. **Needs a restart**, because it changes which processes the server starts (the archiver process).
- `archive_command`: the shell command PostgreSQL runs for every finished segment. **Exit 0 = archived, safe to recycle. Non-zero = keep the file and retry.** So a broken archive command doesn't lose data. Instead, `pg_wal` keeps growing until the disk is full and the database stops. *That* is the real-world failure to watch for.
- `archive_timeout`: a quiet database might take hours to fill a 16 MB segment, and an unarchived segment is data you'd lose. This forces a switch every N seconds, so it caps your RPO.

### Timelines
After a PITR, the recovered server can't keep writing on the old history, because the old history continues past your recovery point (that's where the DELETE is). So it starts **timeline 2**. New WAL files start with `00000002...`, and a small `00000002.history` file records where the branch happened. Think of git: recovery creates a branch.

---

## 4. Recovery mode, step by step

To recover a base backup to a point in time (PostgreSQL 12+):

1. Extract the base backup into an empty data directory.
2. Set `restore_command` (the reverse of archive_command: how to fetch an archived WAL file back).
3. Set `recovery_target_time` (where to stop).
4. Create an empty file `recovery.signal` in the data directory. This is what tells PostgreSQL to start in *targeted recovery* instead of normal startup.
5. Start the server. It replays WAL until the target, then (with `recovery_target_action = 'promote'`) becomes a normal read-write server on a new timeline.

Before PostgreSQL 12 this was a `recovery.conf` file. Old blog posts still show it, and it doesn't work on 16.

---

## 5. Why backups fail in real life

Almost never because `pg_dump` has a bug. Usually because of:

1. **The job stopped running and nobody noticed.** Cron was edited, a password changed, the disk filled up. → `check_backup_freshness.sh`
2. **The backup exists but can't be restored.** It's truncated, half-written or corrupted. → checksums, writing to `.partial` then renaming, and `restore_drill.sh`
3. **Nobody knows the restore steps.** It's 3am, the person who set it up has left, and the steps are in their head. → the labs in this repo become the runbook
4. **Backups sit on the same disk as the database.** The disk dies and takes both. → offsite copy (next step, once you have cloud storage)
5. **Retention ate the one backup you needed.** → keep enough history, and know how far back you can go

This is the same idea as silent-failure-monitor: **watch for the thing that should happen and didn't.**

---

## 6. The 3-2-1 rule

3 copies of the data, on 2 different kinds of storage, with 1 copy offsite. On the VM we cover "2 copies, same machine". The cloud step later (S3 or GCS) fills in the offsite part. Say this honestly in interviews: "this lab doesn't do offsite yet, and here's how I'd add it."

---

## Check yourself before Lab 01

Answer these without looking. If you can't, re-read the section.

1. Your database gets 10 orders a minute. With `archive_timeout = 300` and no other activity, what's the worst-case data loss if the server's disk dies? (Hint: what has been archived, and what hasn't?)
2. Why can't `pg_dump` alone recover to 10:41:59?
3. `archive_command` has been failing for 6 hours. Is any data lost yet? What will happen if it keeps failing?
4. Why does `archive_mode` need a restart, while `archive_command` only needs a reload?
5. After a PITR, why does the server switch to a new timeline instead of continuing on timeline 1?

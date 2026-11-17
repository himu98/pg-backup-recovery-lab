# Results

Everything on this page was measured on my own VM. Fill it in as you work through the labs.

## Environment

| | |
|---|---|
| OS | |
| PostgreSQL | |
| VM resources (CPU / RAM / disk) | |
| shopdb size after seed | |

## Logical restore time vs database size (Lab 02)

| Database size | Dump file size | Backup time | Restore time (drill) |
|---|---|---|---|
| | | | |
| | | | |
| | | | |

What I noticed:

## Point-in-time recovery (Lab 04)

| | By hand | With `pitr_restore.sh` |
|---|---|---|
| Time from DELETE to verified data | | |
| Orders expected / recovered | | |

## RPO and RTO for this setup

- **RPO** (worst-case data loss), and why:
- **RTO, single table** (logical restore):
- **RTO, whole cluster** (PITR):

## What broke and how I fixed it

<!-- Write these in your own words. This section is the reason this repo exists. -->

1.
2.
3.

## Options for getting recovered data back into production (Lab 04, step 4)

1. Copy rows back:
2. Swap servers:
3. Point the app at the restored copy:

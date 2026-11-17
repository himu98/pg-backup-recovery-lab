# Lab 05: Automate with systemd timers, and catch backups that stop

**Time:** about 45 minutes

**Goal:** backups, drills and freshness checks run on a schedule without you, and a failure is visible.

---

## 1. Why systemd timers instead of cron

| | cron | systemd timer |
|---|---|---|
| Logs | wherever you redirect them (often nowhere) | `journalctl -u <unit>`, automatically |
| Did the last run fail? | you have to build that | `systemctl status` shows it, `systemctl --failed` lists it |
| VM was off at 01:30 | the run is skipped | `Persistent=true` runs it at boot |
| Run it once by hand, exactly like the schedule does | hard to get the same env | `systemctl start <unit>.service` |

Read the four `.service` and `.timer` files in `systemd/`. What do `Type=oneshot`, `Nice=10`, `Persistent=true` and `RandomizedDelaySec` each do?

## 2. Install

```bash
sudo cp /opt/pg-backup-recovery-lab/systemd/* /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now pg-logical-backup.timer pg-base-backup.timer pg-restore-drill.timer pg-backup-freshness.timer
systemctl list-timers 'pg-*'
```
Read the NEXT and LEFT columns.

## 3. Run each one now, the way the timer would

```bash
sudo systemctl start pg-logical-backup.service
systemctl status pg-logical-backup.service
journalctl -u pg-logical-backup.service -n 20
```
Do the same for the restore drill and the freshness check.

## 4. Break it: the silent failure

The most realistic backup failure: the backup stops running and nobody notices.

```bash
sudo systemctl disable --now pg-logical-backup.timer
```
Now pretend a day has passed. Make the newest dump look 30 hours old:
```bash
sudo -u postgres touch -d '30 hours ago' /var/backups/postgres/logical/shopdb/*.dump
sudo systemctl start pg-backup-freshness.service
systemctl status pg-backup-freshness.service
systemctl --failed
```
That red `failed` is the signal. Right now only someone who logs in will see it. In the next project (observability-stack), `METRICS_DIR` gets set, Prometheus reads `pg_backup_stale`, and you get alerted on your phone. **Write down: who would have noticed this failure today, and when?**

Fix it:
```bash
sudo systemctl enable --now pg-logical-backup.timer
sudo systemctl start pg-logical-backup.service
sudo systemctl start pg-backup-freshness.service
systemctl --failed
```

## 5. Break it: the backup job fails

```bash
sudo sed -i 's/^DATABASES=.*/DATABASES="shopdb typo_db"/' /etc/pg-backup/backup.env
sudo systemctl start pg-logical-backup.service
systemctl status pg-logical-backup.service
journalctl -u pg-logical-backup.service -n 15
```
Was `shopdb` still backed up? Fix the config back afterwards.

**Done when:** `systemctl list-timers 'pg-*'` shows 4 timers, you've seen both failure modes in `systemctl --failed`, and you can explain why the freshness check exists separately from the backup job's own exit code.

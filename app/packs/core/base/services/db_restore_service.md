# DbRestoreService

`DbRestoreService` is a Ruby service class responsible for restoring MySQL databases using a dynamic EC2 instance on AWS. It orchestrates launching an instance, uploading backup scripts, verifying the restore, and tearing down unnecessary services.

---

## 📦 Responsibilities

- Ensure the backup script is present locally (generate if needed).
- Create or reuse an EC2 instance for restoration.
- Upload and execute a backup restore script remotely.
- Clean up unnecessary services on the remote host (Redis, Elasticsearch, Docker, etc.).
- Verify the restore by querying MySQL **on the restored instance** directly (user count > 0).
- Terminate a stale/disk-full restore instance so a fresh one can be launched (`terminate_instance!`).
- Automatically create required IAM role and policy (`DbCheckInstanceRole`).
- Send email notifications and error alerts as needed.

---

## 🚀 Usage

```ruby
DbRestoreService.run!
```

Optionally:

```ruby
DbRestoreService.run!(instance_name: "CustomDbRestoreInstance")
```

Terminate the restore instance (e.g. when its disk has filled up):

```ruby
DbRestoreService.terminate_instance!
```

> ⚠️ `terminate_instance!` is an **allowlist**: it only ever terminates `DbCheckInstance`.
> It explicitly refuses the production primary (`DB-Redis-ES`) and any other name.

Typically you don't call these directly — `DbRestoreJob` orchestrates the run and the
disk-full retry (see [Failure Recovery](#-failure-recovery)).

---

## 🔧 Required Environment Variables

| Variable | Description |
|----------|-------------|
| `AWS_REGION` | AWS region to operate in |
| `KEYNAME` | Name of the `.pem` SSH key without `.pem` extension |
| `PRIVATE_SUBNET_ID` | Private subnet ID in which to launch the instance |
| `DB_CHECK_STORAGE` | Volume size (in GB) for the EBS root volume |
| `AWS_S3_BUCKET` | Base bucket name; the backup-xtra bucket ARN is derived from it |
| `DB_RESTORE_AMI_NAME` | Name of the AMI used for launching the instance (default: `DB-Redis-ES`) |
| `BASE_DOMAIN` | Included in the subject line of PASSED/FAILED notification emails |

---

## 🗂 Dependencies

- AWS SDK v3 (`aws-sdk-ec2`, `aws-sdk-iam`)
- `net-ssh`, `net-scp` for remote command execution and file transfer
- `rake` for generating the backup script
- `Rails.logger`, `Rails.application.credentials`
- `ReplicationHealthJob`, `ExceptionNotifier`, and `EntityMailer`

---

## 🔁 High-Level Flow

1. **Check Script**:
   - If the local backup script doesn't exist, generate it using `xtrabackup:generate_backup_script`.

2. **Find/Launch EC2 Instance**:
   - Try to find an instance tagged with the given name.
   - If not found
      - Fetch the Latest AMI with given name
      - Make sure there is a role and policy attached to this role for creating a new instance
      - If not create policy, create role and attach policy to role
      - Launch the new instance with this role attached
   - Ensure the instance is running and passes status checks.

3. **Stop All other services on DB Restore Instance**
   - Stops and disables services like `redis`, `docker`, `node_exporter`, and `elasticsearch`.
   - Removes all docker containers.

4. **Upload & Execute Restore Script**:
   - SCP the backup script to `/home/ubuntu/db_backup.sh`.
   - SSH and run `sudo bash db_backup.sh restore_primary`.

5. **Verify Restored Instance**:
   - SSHes into the restored instance and runs `SELECT COUNT(*) FROM users` directly against its MySQL.
   - A count `> 0` means the restore landed real data → PASSED; `0` or a query failure → FAILED (raises).
   - This is the authoritative check. `verify_timestamp` (which reads the *live primary*, not the
     restored box) is kept for reference but is **no longer** called from `run!`.

6. **Cleanup & Stop**:
   - Deletes `/tmp/xb*` files on the instance.
   - Disarms the baked backup cron (`/etc/db_backup_enabled`) for every target **except** the real
     primary, so a throwaway verifier can't corrupt the primary's S3 backup lineage.
   - Stops the instance (does **not** terminate it — see [Failure Recovery](#-failure-recovery)).
   - Sends a PASSED email notification.
---

## 📤 IAM Configuration

- **Role**: `DbCheckInstanceRole`
- **Policy**: `DbCheckInstancePolicy`

### 🔐 IAM Permissions

#### Trust Relationship (Assume Role):
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "ec2.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
```

#### Inline Policy Actions:
```json
{
  "Action": [
    "ssm:*",
    "logs:*",
    "ec2messages:*",
    "s3:GetObject",
    "ses:SendEmail"
  ],
  "Resource": "*",
  "Effect": "Allow"
}
```

---

## ⚠️ Error Handling & Notifications

- Logs all major steps and failures.
- On a failed verification (0 users) or any raised error, the run raises; `DbRestoreJob` catches it.
- A FAILED email is sent via `EntityMailer` only after the retry attempt also fails (see below).

---

## 🔁 Failure Recovery

The restore instance is only **stopped** between runs, never terminated, so it is reused day after
day. Its disk gradually fills up, and eventually `scp`/restore fails on a full disk. `DbRestoreJob`
handles this automatically:

1. **Attempt 1** — `DbRestoreService.run!`.
2. On any failure → **`terminate_instance!`**, which destroys the stale `DbCheckInstance`
   (its root volume has `delete_on_termination: true`, so the full disk goes with it).
3. **Attempt 2** — `run!` again. Because `find_instance` ignores terminated instances, this launches
   a brand-new instance with a **clean disk**.
4. If attempt 2 also fails → send the FAILED notification email.

**Host-key handling.** A freshly launched instance frequently **reuses a subnet private IP** from a
previously terminated one. The old host key still sits in `~/.ssh/known_hosts`, so `Net::SSH` would
abort with `fingerprint … does not match`. All SSH/SCP connections go through the `ssh_opts` helper,
which sets `verify_host_key: :never` — appropriate for these single-use, private-subnet instances.

To connect manually when you hit the same mismatch:

```bash
ssh-keygen -R <private-ip>                       # drop the stale key, or…
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i ~/.ssh/$KEYNAME.pem ubuntu@<private-ip>   # bypass for one connection
```

> These are **private** IPs — SSH only routes from inside the VPC (a bastion or another VPC host).

---

## 🛠 Notes

- Uses both public and private IP detection for flexibility (e.g., private VPC vs public subnet).
- Makes all AWS API calls resilient by setting:
  ```ruby
  http_open_timeout: 10,
  http_read_timeout: 60
  ```
- SSH/SCP timeouts vary by step: `10s` for short commands/uploads, `30s` for verification,
  `1800s` for the long-running restore script.
- All SSH/SCP connections share the `ssh_opts(timeout:)` helper (keys + timeout + `verify_host_key: :never`).
- Designed to be run as part of a scheduled job (`DbRestoreJob`) or triggered manually.

---

## 📚 Related Tasks

- `xtrabackup:generate_backup_script`: Rake task to generate the restore script file.
- `DbRestoreJob`: wraps `run!` with the terminate-and-retry recovery described above.
- `ReplicationHealthJob#get_timestamp`: used only by the legacy `verify_timestamp` (no longer in the run path).

---

## ✅ Example Output

Successful run:

```
✓ Backup script already exists at tmp/db_backup_xtra_production.sh
✓ Instance DbCheckInstance found: i-048abcd1234
→ Starting instance...
✓ Instance is running
→ Cleaning up remote services...
✓ Remote services cleanup completed
→ Uploading script to 10.0.3.170:/home/ubuntu/db_backup.sh
→ Running script on 10.0.3.170 (this may take a few minutes...)
✓ Restored DB validated: 152340 users found on 10.0.3.170
✓ Cleanup successful
```

Disk-full recovery (attempt 1 fails → terminate → fresh instance → attempt 2):

```
✗ DbRestoreJob failed (attempt 1): SCP did not finish successfully (1):
→ DbRestoreJob retrying with a fresh instance after: SCP did not finish successfully (1):
→ Terminating instance i-048abcd1234 (DbCheckInstance)...
✓ Instance i-048abcd1234 terminated
→ Launching new instance with name DbCheckInstance...
✓ Restored DB validated: 152340 users found on 10.0.3.171
```

---

## 📞 Support

- Ensure that the SSH key (`~/.ssh/#{ENV['KEYNAME']}.pem`) exists and has proper permissions.
- Confirm that IAM credentials (`AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`) are correctly stored in Rails credentials.
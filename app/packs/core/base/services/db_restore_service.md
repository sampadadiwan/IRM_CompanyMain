# DbRestoreService

`DbRestoreService` is a Ruby service class responsible for restoring MySQL databases using a dynamic EC2 instance on AWS. It orchestrates launching an instance, uploading backup scripts, verifying the restore, and tearing down unnecessary services.

---

## 📦 Responsibilities

- Ensure the backup script is present locally (generate if needed).
- Create or reuse an EC2 instance for restoration.
- Upload and execute a backup restore script remotely.
- Clean up unnecessary services on the remote host (Redis, Elasticsearch, Docker, etc.).
- Verify MySQL data consistency using timestamp checks.
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

---

## 🔧 Required Environment Variables

| Variable | Description |
|----------|-------------|
| `AWS_REGION` | AWS region to operate in |
| `KEYNAME` | Name of the `.pem` SSH key without `.pem` extension |
| `SUBNET_ID` | Subnet ID in which to launch the instance |
| `DB_CHECK_STORAGE` | Volume size (in GB) for the EBS root volume |
| `DB_RESTORE_AMI_NAME` | Name of the AMI used for launching the instance (default: `DB-Redis-ES`) |

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

5. **Verify Timestamp**:
   - Fetches a timestamp from the MySQL DB via `ReplicationHealthJob`.
   - Compares it to the current time to verify data freshness.
   - Send Email Notification

6. **Cleanup**:
   - Deletes `/tmp/xb*` files.
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
- On timestamp validation failure, sends emails via `EntityMailer` and logs via `ExceptionNotifier`.

---

## 🛠 Notes

- Uses both public and private IP detection for flexibility (e.g., private VPC vs public subnet).
- Makes all AWS API calls resilient by setting:
  ```ruby
  http_open_timeout: 10,
  http_read_timeout: 60
  ```
- SSH timeout is set to `10s`.
- SSH/SCP are intentionally **not** abstracted for visibility and control.
- Designed to be run as part of a scheduled job or triggered manually.

---

## 📚 Related Tasks

- `xtrabackup:generate_backup_script`: Rake task to generate the restore script file.
- `ReplicationHealthJob#get_timestamp`: Responsible for inserting and checking the test timestamp in MySQL.

---

## ✅ Example Output

```
✓ Backup script already exists at tmp/db_backup_xtra_production.sh
✓ Instance DbCheckInstance found: i-048abcd1234
→ Starting instance...
✓ Instance is running
→ Cleaning up remote services...
✓ Remote services cleanup completed
→ Uploading script to 13.233.55.8:/home/ubuntu/db_backup.sh
→ Running script on 13.233.55.8 (this may take a few minutes...)
✓ Timestamp '2025-07-16 14:05:00 +0530' is recent (Δ 15s)
✓ Cleanup successful
```

---

## 📞 Support

- Ensure that the SSH key (`~/.ssh/#{ENV['KEYNAME']}.pem`) exists and has proper permissions.
- Confirm that IAM credentials (`AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`) are correctly stored in Rails credentials.
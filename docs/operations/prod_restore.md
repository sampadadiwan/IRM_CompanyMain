# Production Database Restore Process

ENSURE **Sidekiq** is NOT running before proceeding.

### 1. Restore the Primary Database
Run the restore script:
```bash
tmp/db_restore_docker.sh restore_primary
```

### 2. Rename the Database
Rename the restored production database to development:
```bash
tmp/rename_db.sh IRM_production IRM_development root 127.0.0.1 33066
```

### 3. Update Database Configuration
Change `config/database.yml` to point to `db_restore_docker`:

```yaml
development:
  primary:
    <<: *default
    database: IRM_development
    password: Root1234$
    port: 33066
  primary_replica:
    <<: *default_replica
    database: IRM_development
    database_tasks: false
    password: Root1234$
    port: 33066
```

### 4. Sanitize Data (Sandbox Mode)
Open the Rails console and run the following command:
```ruby
EntitySetting.disable_all
```
This will:
- Put everything in **sandbox** mode.
- Disable **WA** (WhatsApp/WebAuthn) for all users.
- Reset the admin password to `password`.

### 5. Apply Pending Migrations
Run the following command to apply any pending migrations to the new database:
```bash
bundle exec rake db:migrate
```


### 6. Verification
Login and troubleshoot production data as needed.

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
- **Scrub investors' personal data** (`DevPiiScrubber`, P1 of the OWASP review 2026-11): PANs, bank account
  numbers, dates of birth, CKYC/KRA/AML/e-sign provider responses, PAN-card and address-proof data, identity
  custom fields (PAN, Aadhaar, passport) and the same values in history (`audits`) are replaced with fakes. The
  same real PAN becomes the same fake everywhere, so duplicates and import matching still behave as in
  production. IFSC codes and names are kept. It refuses any database that isn't a local `*_development` one.
  It prints one line per table with the number of rows changed; expect a few minutes on a full copy (history is
  the largest part).

**Never skip this step** — without it the copy on your machine holds every LP's real PAN and bank account.
See `docs/security/owasp_2026_11_changes.md` › "P1".

### 5. Apply Pending Migrations
Run the following command to apply any pending migrations to the new database:
```bash
bundle exec rake db:migrate
```


### 6. Verification
Login and troubleshoot production data as needed.

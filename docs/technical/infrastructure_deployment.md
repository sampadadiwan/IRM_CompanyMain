# Infrastructure Deployment & Upgrade Guide

## Overview

IRM uses a multi-layered infrastructure deployment architecture:

- **Infrastructure as Code**: Pulumi (Python) for AWS resource provisioning
- **AMI Building**: Packer for creating custom EC2 AMIs with pre-installed dependencies
- **Application Deployment**: Capistrano 3 for Rails app deployment
- **Process Management**: Systemd + Monit, Puma, Sidekiq
- **Reverse Proxy**: Nginx
- **Load Balancing**: AWS Application Load Balancer (ALB)
- **CI/CD**: GitHub Actions for testing and linting

---

## 1. Infrastructure Components

### 1.1 Network (Pulumi — `IRM-Infra/network.py`)

| Resource | CIDR / Config |
|----------|--------------|
| VPC | `10.0.0.0/16` |
| Public Subnet 1 | `10.0.1.0/24` (AZ: region-a) |
| Public Subnet 2 | `10.0.2.0/24` (AZ: region-b) |
| Private Subnet 1 | `10.0.3.0/24` (AZ: region-a) |
| Private Subnet 2 | `10.0.4.0/24` (AZ: region-b) |
| Internet Gateway | Public subnet egress |
| NAT Gateway | Private subnet outbound (placed in public subnet) |

### 1.2 Compute (Pulumi — `IRM-Infra/compute.py`)

**Web Servers (2×)**
- Instance: `t3.large`, one per public subnet
- EBS: 20 GB gp3
- IAM Role: `RailsAppRole` (S3 + EC2 full access)
- Security Group `web-sg` inbound: SSH 22 (0.0.0.0/0), HTTP 80 from ALB, HTTPS 443 from ALB, Node Exporter 9100 from observability, Rails Prometheus 9394 from observability

**Database Primary** (private subnet, AZ-a)
- Instance: `t3.large`
- Services: MySQL, Redis, Elasticsearch
- Security Group `db-sg` inbound: MySQL 3306 from web-sg and db-sg, Redis 6379 from web-sg, Elasticsearch 9200 from web-sg, SSH 22 from web-sg, exporters from observability-sg

**Database Replica** (private subnet, AZ-b)
- Same instance type and services as primary
- User data removes `auto.cnf` on start to reset MySQL UUID (required for replication)
- Replication filter ignores `solid_cache_entries` table

**Observability Server** (public subnet)
- Instance: `t3.large`
- Services: Grafana (port 3000), Prometheus
- Port 3000 accessible from ALB

### 1.3 Load Balancer (Pulumi — `IRM-Infra/alb.py`)

- Type: HTTPS ALB across both public subnets
- Idle timeout: 60 s, HTTP/2 enabled
- **App target group**: port 80, health check `/users/sign_in`
- **Observability target group**: port 3000, health check `/api/health`
- Listener 443: forwards to app; path/host rule routes Grafana traffic to observability group

### 1.4 SSL/TLS (`IRM-Infra/certificate.py`)

- Provider: AWS Certificate Manager (ACM)
- Validation: DNS via Route 53
- Domain configured in Pulumi stack config (e.g. `*.caphive.com`)

---

## 2. Deployment Configuration

### 2.1 Tool: Capistrano 3

**Core settings** (`config/deploy.rb`):
```ruby
set :application, "IRM"
set :repo_url, "git@github.com:ausangshukla/IRM.git"
set :branch, ENV["branch"] || 'main'
set :deploy_to, "/home/ubuntu/IRM"
set :rails_env, fetch(:stage)
set :keep_releases, 3   # production
set :keep_releases, 1   # non-production
```

**Puma** (systemd-managed):
```ruby
set :puma_bind, "unix://#{shared_path}/tmp/sockets/#{fetch(:application)}-puma.sock"
set :puma_threads, [0, 16]
set :puma_workers, 4
set :puma_preload_app, true
set :puma_systemctl_user, :system
set :puma_service_unit_name, "puma_IRM_#{fetch(:rails_env)}"
```

### 2.2 Deployment Stages

| Stage | Server(s) | SSH Key |
|-------|-----------|---------|
| `production_in` | `3.110.85.100` (+ `3.110.217.31` if LB) | `~/.ssh/caphive2.pem` |
| `production_us` | `54.147.171.162` | `~/.ssh/caphive2.us.pem` |
| `staging_in` | `52.66.163.132` | `~/.ssh/altxdev.pem` |
| `staging_us` | `13.222.236.84` (+ `34.229.217.208` if LB) | `~/.ssh/altx.us.pem` |

---

## 3. Deployment Flow (Step-by-Step)

### Phase 1 — Pre-deployment notification
```
Hook: before 'deploy:starting' → deploy:notify_before
→ Enqueues DeploymentNotificationWorker("before") via Sidekiq
→ Users notified that system will go down
```

### Phase 2 — Environment setup
```
Hook: before 'deploy:symlink:shared' → env:point_envfile
→ Symlinks .env.{stage}.{variant} → .env.{stage}
→ Symlinks credentials/encrypt files and keys to environment-specific versions
```

### Phase 3 — Rails master key
```
Hook: before 'deploy:updated' → IRM:set_rails_master_key
→ Reads local file: config/credentials/{stage}.{variant}.key
→ Appends RAILS_MASTER_KEY to /etc/environment on remote
→ Writes key file to release_path
```

### Phase 4 — Code deploy
```
Built-in Capistrano/Rails tasks (automatic):
1. deploy:check
2. deploy:symlink:shared / deploy:symlink:release
3. bundle:install
4. rails:assets:precompile
5. rails:db:migrate
```

### Phase 5 — Service restart
```
Hook: after 'deploy:updated'
→ puma:restart    (systemctl restart puma_IRM_{stage})
→ sidekiq:restart (systemctl restart sidekiq_IRM_{stage})
```

### Phase 6 — Permissions & cleanup
```
Hook: after 'deploy:finished' → ensure_permissions
→ sudo chown -R ubuntu /home/ubuntu/IRM/current/log/*
→ sudo chown -R www-data nginx logs
→ sudo chmod 660 puma.sock
→ sudo service nginx restart
→ Removes old xtrabackup script from shared/tmp
```

### Phase 7 — Post-deployment notification
```
Hook: after 'deploy:finished' → deploy:notify_after
→ Enqueues DeploymentNotificationWorker("after") with 1-minute delay
→ Users notified that system is back online
```

### Commands

```bash
# Standard deploy
bundle exec cap production_in deploy

# Deploy specific branch
branch=feature-branch bundle exec cap production_in deploy

# Skip user notifications
SKIP_NOTIFICATION=true bundle exec cap production_in deploy

# Rollback to previous release
bundle exec cap production_in deploy:rollback
```

---

## 4. Environment & Credentials Management

### File structure

```
.env.production.in          # Production India env vars
.env.production.us          # Production US env vars
.env.staging.in
.env.staging.us

config/credentials/
  production.in.yml.enc     # Encrypted credentials
  production.us.yml.enc
  staging.in.yml.enc
  staging.us.yml.enc
  production.in.key         # Encryption keys (not committed)
  production.us.key
  staging.in.key
  staging.us.key
```

### How symlinking works at deploy time

```ruby
# env:point_envfile (runs before deploy:symlink:shared)
ln -nfs .env.production.in  .env.production
ln -nfs config/credentials/production.in.yml.enc  config/credentials/production.yml.enc
ln -nfs config/credentials/production.in.key      config/credentials/production.key
```

The `RAILS_MASTER_KEY` is also appended to `/etc/environment` so systemd services pick it up.

### Updating credentials / IPs

```bash
# Utility helpers in lib/tasks/aws_utils.rb:
update_rails_credentials(rails_env, env_variant, key, value)
update_env_file(file_path, key, new_value)
replace_ip_addresses(file_path, new_ips)
```

---

## 5. Database Management

### 5.1 Migrations

Capistrano/Rails runs `rails:db:migrate` automatically during every deploy.

### 5.2 Replication

- Primary (AZ-a) → Replica (AZ-b)
- Replica ignores `solid_cache_entries` table

```bash
# If replication breaks:
bundle exec cap production_in db:reset_replication

# Or manually on the replica:
mysql> STOP REPLICA;
mysql> CHANGE REPLICATION FILTER REPLICATE_IGNORE_TABLE = (IRM_staging.solid_cache_entries);
mysql> START REPLICA;
mysql> SHOW REPLICA STATUS\G
```

### 5.3 Backup & Restore (Percona XtraBackup)

**Backup** — stored in S3 bucket `{AWS_S3_BUCKET}-backup-xtra`:
```bash
rake xtrabackup:generate_backup_script   # Generate script with credentials
# Script runs automatically on a schedule
```

**Restore** (disaster recovery):
```bash
bundle exec cap production_in recovery:load_db_from_backups
# Restores both primary and replica from latest S3 backup

bundle exec cap production_in recovery:restore_replica_db
# Replica only
```

**Check available backups**:
```bash
aws s3 ls s3://{bucket}-backup-xtra/ --recursive
```

---

## 6. OS & Dependency Upgrades

### 6.1 AMI-based upgrade strategy (Packer)

Packer templates live in `config/deploy/templates/packer/`:
- `appserver.ami.pkr.hcl` — Web server AMI
- `db_redis_es.ami.pkr.hcl` — Database / Redis / Elasticsearch AMI
- `observability.ami.pkr.hcl` — Grafana / Prometheus AMI

**Rake tasks** (`lib/tasks/packer.rake`):

```bash
# Check template syntax
rake packer:check_env[prod,in]

# Initialize (download plugins)
rake packer:init_env[prod,in]

# Build all AMIs
rake packer:build_env[prod,in,all]

# Build individual AMI
rake packer:build_env[prod,in,app]   # web server
rake packer:build_env[prod,in,db]    # db/redis/es
rake packer:build_env[prod,in,obs]   # observability

# Copy AMI to another region
rake aws:copy_ami[ami-xxxxxxxxx,us-east-1]

# Clean up old AMIs
rake aws:delete_old_amis[AppServer,us-east-1]
```

### 6.2 Full infrastructure upgrade workflow

```bash
# 1. Build new AMIs with updated packages
export AWS_ACCESS_KEY_ID=xxx AWS_SECRET_ACCESS_KEY=yyy AWS_REGION=ap-south-1
rake packer:build_env[prod,in,all]

# 2. Update Pulumi stack config with new AMI IDs
#    Edit Pulumi.production-in-ap-south-1.yaml:
#    - ap-south-1_web_server_ami: ami-NEW
#    - ap-south-1_db_server_ami: ami-NEW
#    - ap-south-1_observability_ami: ami-NEW

# 3. Apply infrastructure changes
cd IRM-Infra
pulumi stack select production-in-ap-south-1
pulumi up

# 4. Update Capistrano config with new IPs (if they changed)
#    Edit config/deploy/production_in.rb

# 5. First-time setup on new instances
bundle exec cap production_in IRM:setup

# 6. Restore database if needed
bundle exec cap production_in recovery:load_db_from_backups
bundle exec cap production_in db:reset_replication

# 7. Deploy app
bundle exec cap production_in deploy
```

### 6.3 In-place OS upgrade (without AMI rebuild)

```bash
# Apply apt updates and reboot
bundle exec cap production_in IRM:apt_update
# Runs: apt-get update, apt-get upgrade -y, journalctl --vacuum-time=2d, reboot

# Reboot only
bundle exec cap production_in IRM:reboot

# Grow disk partition when full
rake aws:grow_disk
# Runs: growpart /dev/nvme0n1 1 → resize2fs /dev/nvme0n1p1
```

---

## 7. Maintenance Mode

```bash
# Enter maintenance mode (returns HTTP 503 with maintenance page)
bundle exec cap production_in nginx:switch_maintenance
# → Stops Sidekiq + Puma, switches nginx site

# Deploy code while in maintenance
bundle exec cap production_in deploy

# Exit maintenance mode
bundle exec cap production_in nginx:switch_app
# → Switches nginx site back, restarts Puma + Sidekiq
```

---

## 8. Process Management

### Puma
- Systemd unit: `puma_IRM_{stage}`
- Socket: `/home/ubuntu/IRM/shared/tmp/sockets/IRM-puma.sock`
- Config template: `config/deploy/templates/puma.rb.erb`
- 4 workers × 16 threads, `preload_app!`
- Monit: `config/deploy/monit/puma_IRM_env.conf.erb`

### Sidekiq
- Systemd unit: `sidekiq_IRM_{stage}`
- Monit: `config/deploy/monit/sidekiq_IRM_env.conf.erb`
- Monit paused before deploy, resumed after: `sidekiq:monit:unmonitor` / `sidekiq:monit:monitor`

### Nginx
- Reverse proxies to Puma Unix socket
- Static assets served directly with gzip + max-expires
- Config template: `config/deploy/templates/nginx_conf.erb`

### Monit
- Watches Puma and Sidekiq PIDs
- Config template: `config/deploy/templates/monitrc.erb`
- Reload after setup: `sudo monit reload`

### Log rotation
- Configured by `IRM:setup_logrotate`
- Config: `config/deploy/logrotate.conf`

---

## 9. CI/CD Pipeline (GitHub Actions)

### Lint & security (`.github/workflows/lint.yml`)
Triggers: push to main, PRs to main

| Job | Tool | Purpose |
|-----|------|---------|
| Rubocop | rubocop | Ruby style |
| Bundler Audit | bundler-audit | Vulnerable gems |
| Brakeman | brakeman | Rails security scan |

### Test & deploy (`.github/workflows/rubyonrails.yml`)
Triggers: push to main, PRs to main

Services: MySQL 5.7, Redis, Elasticsearch 8.19.0

Steps:
1. Install Ruby (via `ruby/setup-ruby@v1`)
2. `bundle install`
3. `bin/rails db:create && db:schema:load`
4. Reset Elasticsearch: `bundle exec rails runner ElasticImporterJob.new.reset`
5. `bundle exec cucumber features`
6. **Auto-deploy to staging** via `miloserdow/capistrano-deploy@master` (uses `DEPLOY_ENC_KEY` secret)

Production deployments are manual — no auto-deploy from CI.

---

## 10. Rollback

### Code rollback
```bash
bundle exec cap production_in deploy:rollback
# Moves 'current' symlink to previous release, restarts Puma/Sidekiq
# Production keeps last 3 releases
```

### Data rollback
```bash
# Restore from latest S3 XtraBackup snapshot
bundle exec cap production_in recovery:load_db_from_backups
```

### Infrastructure rollback
No automation — manual steps:
1. Revert AMI IDs in Pulumi stack config
2. `pulumi up` to recreate with previous AMIs
3. Update Capistrano config with new IPs if they changed

---

## 11. Key File Reference

| File | Purpose |
|------|---------|
| `IRM-Infra/__main__.py` | Pulumi orchestration entry point |
| `IRM-Infra/network.py` | VPC, subnets, routing |
| `IRM-Infra/compute.py` | EC2 instances, security groups |
| `IRM-Infra/alb.py` | Load balancer, target groups |
| `IRM-Infra/certificate.py` | ACM SSL certificates |
| `Capfile` | Capistrano plugin loading |
| `config/deploy.rb` | Core deploy config, hooks, custom tasks |
| `config/deploy/production_in.rb` | Production India server list |
| `config/deploy/production_us.rb` | Production US server list |
| `config/deploy/staging_in.rb` | Staging India server list |
| `config/deploy/staging_us.rb` | Staging US server list |
| `config/deploy/templates/puma.rb.erb` | Puma config template |
| `config/deploy/templates/nginx_conf.erb` | Nginx config template |
| `config/deploy/templates/monitrc.erb` | Monit master config template |
| `config/deploy/monit/puma_IRM_env.conf.erb` | Monit Puma check |
| `config/deploy/monit/sidekiq_IRM_env.conf.erb` | Monit Sidekiq check |
| `config/deploy/services/puma_IRM_env.service.erb` | Puma systemd unit template |
| `config/deploy/logrotate.conf` | Log rotation config |
| `lib/tasks/packer.rake` | Rake tasks for building AMIs |
| `lib/tasks/aws.rake` | AWS infrastructure setup tasks |
| `lib/tasks/aws_cleanup.rake` | AWS resource cleanup |
| `lib/tasks/backup_db_xtra.rake` | XtraBackup rake tasks |
| `lib/tasks/db_backup_xtra.sh` | XtraBackup shell script |
| `lib/tasks/aws_utils.rb` | Helper functions for updating IPs/credentials |
| `lib/tasks/deploy_notifications.rake` | Deploy notification tasks |
| `.github/workflows/rubyonrails.yml` | Test + staging deploy pipeline |
| `.github/workflows/lint.yml` | Lint + security pipeline |

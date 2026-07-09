# Specify required plugins for Packer
packer {
  required_plugins {
    amazon = {
      version = ">= 0.0.2"                      # Minimum version of the amazon plugin required
      source  = "github.com/hashicorp/amazon"  # Plugin source for the Amazon EBS builder
    }
  }
}

# Variable to dynamically name the AMI with a specific date
variable "ami_date" {
  type    = string
  default = ""  # Default value; can be overridden via CLI or env var
}

# Declare variable for AWS region
variable "aws_region" {
  type = string
}

# Declare variable for MySQL root password
variable "mysql_root_password" {
  type = string
}

# SSM Parameter Store path baked into /etc/db_backup.env — the backup script
# resolves its secrets (mysql creds, bucket) from here at runtime via the EC2
# instance role. Set per env by packer.rake (e.g. /irm/production/db_backup).
variable "ssm_prefix" {
  type = string
}

variable "source_ami" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "security_group_id" {
  type = string
}

source "amazon-ebs" "ubuntu" { # Renamed to 'ubuntu' for consistency with appserver.ami.pkr.hcl
  ami_name                    = "DB_Redis_ES-${var.ami_date}"
  instance_type               = "t3.small" # t3: available in ALL regions incl. newer ones (ap-south-2 has no t2 family)
  region                      = var.aws_region # Use the variable for region
  # source_ami                  = var.source_ami # Commented out to use source_ami_filter

  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["099720109477"] # Canonical's owner ID for Ubuntu AMIs
  }

  associate_public_ip_address = "true"
  vpc_id                      = var.vpc_id
  subnet_id                   = var.subnet_id
  ssh_interface               = "public_ip"
  security_group_id           = var.security_group_id
  ssh_username                = "ubuntu"

  tags = {
    "Name"      = "DB_Redis_ES"
    "CreatedBy" = "Packer"
  }
}

###############################################
# COMMON PROVISIONING STEPS - REUSABLE INLINE
###############################################
locals {
  setup_commands = [
    # Clean apt cache and update system
    "sudo rm -r /var/lib/apt/lists/*",
    "sudo apt update",
    "sudo apt-get update",
    "sudo apt-get upgrade --yes",

    # Install Zsh
    "sudo apt-get install --yes zsh",


      # --- MySQL 8.4.6 (Oracle MySQL LTS) ---
      # --- Install MySQL 8.4 (Oracle on jammy+, Percona on focal) ---
      # --- Detect Ubuntu codename ---
      # Detect Ubuntu codename
      "CODENAME=$(lsb_release -cs)",

      # Branch by codename: jammy+ → Oracle MySQL 8.4.6; else (focal) → Percona 8.4 LTS
      "case \"$CODENAME\" in",

      "  jammy|mantic|noble|oracular|plucky)",
      "    sudo apt-get update",
      "    sudo apt-get install -y gnupg lsb-release wget curl",
      # Oracle rotates this signing key every ~2 years and the old one EXPIRES
      # (EXPKEYSIG breaks every bake at once — happened 2026-07 with the 2023
      # key). If a bake fails with 'EXPKEYSIG ... MySQL Release Engineering',
      # check https://repo.mysql.com/ for the next RPM-GPG-KEY-mysql-<year>.
      "    curl -fsSL https://repo.mysql.com/RPM-GPG-KEY-mysql-2025 | gpg --dearmor | sudo tee /usr/share/keyrings/mysql.gpg >/dev/null",
      "    echo \"deb [signed-by=/usr/share/keyrings/mysql.gpg] http://repo.mysql.com/apt/ubuntu/ $CODENAME mysql-8.4-lts\" | sudo tee /etc/apt/sources.list.d/mysql.list >/dev/null",
      "    sudo apt-get update",
      "    printf 'Package: mysql-server\\nPin: version 8.4.6*\\nPin-Priority: 1001\\n\\nPackage: mysql-community-server\\nPin: version 8.4.6*\\nPin-Priority: 1001\\n\\nPackage: mysql-client\\nPin: version 8.4.6*\\nPin-Priority: 1001\\n\\nPackage: mysql-community-client\\nPin: version 8.4.6*\\nPin-Priority: 1001\\n' | sudo tee /etc/apt/preferences.d/mysql-8-4-6 >/dev/null",
      "    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server",
      "    ;;",

      "  *)",
      "    sudo apt-get install -y curl lsb-release gnupg2",
      "    curl -fsSLo /tmp/percona-release.deb https://repo.percona.com/apt/percona-release_latest.generic_all.deb",
      "    sudo apt-get install -y /tmp/percona-release.deb",
      "    sudo percona-release enable-only ps-84-lts release",
      "    sudo percona-release enable tools release",
      "    sudo apt-get update",
      "    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y percona-server-server",
      "    ;;",
      "esac",

      # Enable & start (service name is 'mysql' for both Oracle & Percona)
      "sudo systemctl enable mysql",
      "sudo systemctl start mysql || true",

      # OPTIONAL: allow remote connections without sed (drop-in override)
      "echo '[mysqld]' | sudo tee /etc/mysql/mysql.conf.d/zz-network.cnf >/dev/null",
      "echo 'bind-address = 0.0.0.0' | sudo tee -a /etc/mysql/mysql.conf.d/zz-network.cnf >/dev/null",
      "sudo systemctl restart mysql || true",

      # Show what got installed (helps debugging AMI builds)
      "mysql --version || true",


      # (Optional) Allow remote connections; uncomment if you want root@'%' to work right away
      "[ -f /etc/mysql/mysql.conf.d/mysqld.cnf ] && sudo sed -i 's/^[[:space:]]*bind-address[[:space:]]*=.*/bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf || true",
      "[ -f /etc/mysql/percona-server.conf.d/mysqld.cnf ] && sudo sed -i 's/^[[:space:]]*bind-address[[:space:]]*=.*/bind-address = 0.0.0.0/' /etc/mysql/percona-server.conf.d/mysqld.cnf || true",
      "sudo systemctl restart mysql || true",




    # Docker installation
    "echo INSTALLING- Docker",
    "sudo apt install --yes apt-transport-https ca-certificates curl software-properties-common",
    "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg",
    "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",
    "sudo apt update",
    "sudo apt install --yes docker-ce",
    "sudo systemctl start docker",
    "sudo systemctl enable docker",
    # ubuntu must be in the docker group: the @reboot crontab lines below run
    # `docker run` WITHOUT sudo as the ubuntu user — without this membership
    # they fail on the docker socket at boot, and a DR-launched primary comes
    # up with NO Elasticsearch and NO Redis (app half-broken, cause invisible)
    "sudo usermod -aG docker ubuntu",

    # Install logrotate
    "sudo apt install --yes logrotate",

    # Run Docker containers on reboot in ubuntu user's crontab (persistent)
    "logger 'Setting up crontab entries for ubuntu user (persistent).'",
    "sudo -u ubuntu bash -c 'tmpfile=$(mktemp); (crontab -l 2>/dev/null || true) > $tmpfile; echo \"@reboot docker run -d --rm --name elasticsearch -p 9200:9200 -p 9300:9300 -e ES_JAVA_OPTS=\\\"-Xms512m -Xmx512m\\\" -e \\\"discovery.type=single-node\\\" -e \\\"xpack.security.enabled=false\\\" elasticsearch:8.19.0\" >> $tmpfile; echo \"@reboot docker run -d --rm --name redis-stack-server -p 6379:6379 redis/redis-stack-server:latest\" >> $tmpfile; crontab $tmpfile; rm $tmpfile'",
    "logger 'Crontab successfully updated for ubuntu user. Verifying...'",
    "sudo -u ubuntu crontab -l || true",
    "logger 'Ubuntu user crontab setup complete.'",


   # Install Percona repo helper
    "sudo apt-get update",
    "sudo apt-get install -y curl gnupg2 lsb-release",
    "curl -fsSLo /tmp/percona-release.deb https://repo.percona.com/apt/percona-release_latest.generic_all.deb",
    "sudo apt-get install -y /tmp/percona-release.deb",

    # Enable the correct repo for XtraBackup 8.4 LTS and install
    "sudo percona-release enable pxb-84-lts",
    "sudo apt-get update",
    "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y percona-xtrabackup-84",

    # Compression tools you wanted
    "sudo apt-get install -y lz4 zstd",

    # AWS CLI v2 (your existing approach)
    "sudo apt-get install -y unzip",
    "curl https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o awscliv2.zip",
    "unzip -o awscliv2.zip",
    "sudo ./aws/install",

    # Sanity check
    "percona-xtrabackup --version || true",


    // Install OhMyZsh
    "sudo -u ubuntu sh -c 'RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \"$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\"'",
    "sudo cp /home/ubuntu/.oh-my-zsh/templates/zshrc.zsh-template /home/ubuntu/.zshrc",
    "sudo chown ubuntu:ubuntu /home/ubuntu/.zshrc",
    "sudo chsh -s $(which zsh) ubuntu",

    // node_exporter — installed natively (systemd), NOT via Docker, for the same reason as the
    // app server AMI: a Dockerized node-exporter only sees its own container's mount namespace
    // (just /etc/hostname, /etc/hosts, /etc/resolv.conf), so disk/inode metrics silently report
    // nothing for the host. Native install means real host filesystem visibility from boot.
    "echo INSTALLING- node_exporter",
    "sudo useradd --no-create-home --shell /usr/sbin/nologin node_exporter || true",
    "curl -sL https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz -o /tmp/node_exporter.tar.gz",
    "tar xzf /tmp/node_exporter.tar.gz -C /tmp",
    "sudo cp /tmp/node_exporter-1.8.2.linux-amd64/node_exporter /usr/local/bin/node_exporter",
    "sudo chown node_exporter:node_exporter /usr/local/bin/node_exporter",
    "rm -rf /tmp/node_exporter.tar.gz /tmp/node_exporter-1.8.2.linux-amd64",
    "sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOL",
    "[Unit]",
    "Description=Prometheus Node Exporter",
    "Wants=network-online.target",
    "After=network-online.target",
    "",
    "[Service]",
    "User=node_exporter",
    "Group=node_exporter",
    "Type=simple",
    "ExecStart=/usr/local/bin/node_exporter",
    "Restart=on-failure",
    "",
    "[Install]",
    "WantedBy=multi-user.target",
    "EOL",
    "sudo systemctl daemon-reload",
    "sudo systemctl enable node_exporter",
    "sudo systemctl start node_exporter",

  ]

  mysql_password_setup = [
    # Use modern auth in 8.4
    "echo \"ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '${var.mysql_root_password}';\" > /tmp/mysql-init.sql",
    "echo \"CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED WITH caching_sha2_password BY '${var.mysql_root_password}';\" >> /tmp/mysql-init.sql",
    "echo \"GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;\" >> /tmp/mysql-init.sql",
    "echo \"FLUSH PRIVILEGES;\" >> /tmp/mysql-init.sql",
    "sudo mysql < /tmp/mysql-init.sql",
    "rm /tmp/mysql-init.sql"
  ]
}

###############################################
# BUILD BLOCK - STAGING
##############################################
build {
  name    = "DB_Redis_ES"
  sources = ["source.amazon-ebs.ubuntu"]

  provisioner "shell" {
    inline = local.setup_commands
  }

  provisioner "shell" {
    inline = local.mysql_password_setup
  }

  # Bake the DB backup tooling. The script contains NO secrets (resolved at
  # runtime from SSM via the instance role) and the cron schedule is live from
  # first boot but dormant: full/incr exit immediately unless
  # /etc/db_backup_enabled exists, which restore_primary creates on success.
  # This keeps replicas and DbCheckInstance boots from writing to the chain.
  provisioner "file" {
    source      = "lib/tasks/db_backup_xtra.sh"
    destination = "/tmp/db_backup_xtra.sh"
  }

  provisioner "shell" {
    inline = [
      # Root-only: the script can read DB credentials from SSM at runtime
      "sudo install -m 0700 -o root -g root /tmp/db_backup_xtra.sh /usr/local/bin/db_backup_xtra.sh",
      "rm /tmp/db_backup_xtra.sh",
      # Non-secret runtime config: where the script finds its SSM parameters
      "echo 'SSM_PREFIX=\"${var.ssm_prefix}\"' | sudo tee /etc/db_backup.env",
      "sudo chmod 0600 /etc/db_backup.env",
      # Schedule: nightly full at 23:00, incrementals every 30 min (RPO ~30 min).
      # PATH is explicit: cron defaults to /usr/bin:/bin, but the aws CLI the
      # script needs for SSM lookups lives in /usr/local/bin — without this,
      # every armed cron tick would fail at config resolution.
      "printf '%s\\n' 'SHELL=/bin/bash' 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' '0 23 * * *      root /usr/local/bin/db_backup_xtra.sh full >> /var/log/db_backup.log 2>&1' '0,30 0-22 * * * root /usr/local/bin/db_backup_xtra.sh incr >> /var/log/db_backup.log 2>&1' | sudo tee /etc/cron.d/irm-db-backup",
      "sudo chmod 0644 /etc/cron.d/irm-db-backup",
      # Keep the backup log bounded
      "printf '%s\\n' '/var/log/db_backup.log {' '  weekly' '  rotate 8' '  compress' '  missingok' '  notifempty' '}' | sudo tee /etc/logrotate.d/irm-db-backup"
    ]
  }
}

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

# Declare variable for MySQL root password
variable "mysql_root_password" {
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
  instance_type               = "t2.micro"
  region                      = "ap-south-1"
  source_ami                  = var.source_ami
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
      "    curl -fsSL https://repo.mysql.com/RPM-GPG-KEY-mysql-2023 | gpg --dearmor | sudo tee /usr/share/keyrings/mysql.gpg >/dev/null",
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

    # Install logrotate
    "sudo apt install --yes logrotate",

    # Run Docker containers on reboot
    "logger 'Attempting to add crontab entries for Docker containers.'",
    "(crontab -l 2>/dev/null; echo '@reboot sudo docker run -d --rm --name elasticsearch -p 9200:9200 -p 9300:9300 -e ES_JAVA_OPTS=\"-Xms512m -Xmx512m\" -e \"discovery.type=single-node\" elasticsearch:7.11.1\n@reboot sudo docker run -d --rm --name redis-stack-server -p 6379:6379 redis/redis-stack-server:latest') | crontab -",
    "logger 'Crontab entries added. Verifying crontab for ubuntu user...'",
    "crontab -l || true",
    "logger 'Crontab verification complete.'",


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
    "yes | sh -c \"$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\" \"\" --unattended",

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
}

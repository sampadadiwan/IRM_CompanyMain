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

    # Docker installation
    "echo INSTALLING- Docker",
    "sudo apt install --yes apt-transport-https ca-certificates curl software-properties-common",
    "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg",
    "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",
    "sudo apt update",
    "sudo apt install --yes docker-ce",

    # Install logrotate
    "sudo apt install --yes logrotate",

    # Run Docker containers on reboot
    "(crontab -l 2>/dev/null; echo '@reboot sudo docker run -d --rm --name elasticsearch -p 9200:9200 -p 9300:9300 -e \"discovery.type=single-node\" elasticsearch:7.11.1') | crontab -u ubuntu -",
    "(crontab -l 2>/dev/null; echo '@reboot sudo docker run -d --rm --name redis-stack-server -p 6379:6379 redis/redis-stack-server:latest') | crontab -u ubuntu -",

    # Install MySQL 8 server
    "sudo apt-get install -y mysql-server",
    "sudo systemctl start mysql",
    "sudo systemctl enable mysql",
    "sudo service mysql restart",

    # Install percona
    "curl -O https://repo.percona.com/apt/percona-release_latest.$(lsb_release -sc)_all.deb",
    "sudo apt install ./percona-release_latest.$(lsb_release -sc)_all.deb",
    "sudo percona-release setup pxb-80",
    "sudo apt update",
    "sudo apt install -y percona-xtrabackup-80",
    "sudo apt install -y lz4 zstd",
    "# sudo apt-get install awscli",
    "sudo apt install -y unzip",
    "curl https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o awscliv2.zip",
    "unzip awscliv2.zip",
    "sudo ./aws/install",



  ]

  mysql_password_setup = [
    "echo \"ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${var.mysql_root_password}';\" > /tmp/mysql-init.sql",
    "echo \"FLUSH PRIVILEGES;\" >> /tmp/mysql-init.sql",
    "sudo mysql < /tmp/mysql-init.sql",
    "rm /tmp/mysql-init.sql"
  ]
}

###############################################
# BUILD BLOCK - STAGING
###############################################
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

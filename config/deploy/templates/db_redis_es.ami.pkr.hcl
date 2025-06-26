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

###############################################
# AMAZON EBS SOURCE CONFIG - STAGING
###############################################
source "amazon-ebs" "staging" {
  ami_name                    = "DB_Redis_ES_Staging-${var.ami_date}"
  instance_type               = "t2.micro"
  region                      = "ap-south-1"
  source_ami                  = "ami-0522ab6e1ddcc7055"
  associate_public_ip_address = "true"
  vpc_id                      = "vpc-staging-id"         # Replace with your staging VPC ID
  subnet_id                   = "subnet-staging-id"      # Replace with your staging Subnet ID
  ssh_interface               = "public_ip"
  security_group_id           = "sg-staging-id"          # Replace with your staging SG ID
  ssh_username                = "ubuntu"

  tags = {
    "Name"      = "DB_Redis_ES_Staging"
    "CreatedBy" = "Packer"
  }
}

###############################################
# AMAZON EBS SOURCE CONFIG - PRODUCTION
###############################################
source "amazon-ebs" "production" {
  ami_name                    = "DB_Redis_ES_Prod-${var.ami_date}"
  instance_type               = "t2.micro"
  region                      = "ap-south-1"
  source_ami                  = "ami-0522ab6e1ddcc7055"
  associate_public_ip_address = "true"
  vpc_id                      = "vpc-0cb0c5cad8c279582"            # Replace with your production VPC ID
  subnet_id                   = "subnet-0cf73758b0fb6a9b5"         # Replace with your production Subnet ID
  ssh_interface               = "public_ip"
  security_group_id           = "sg-001a351ad10185d5b"             # Replace with your production SG ID
  ssh_username                = "ubuntu"

  tags = {
    "Name"      = "DB_Redis_ES_Prod"
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
    curl -O https://repo.percona.com/apt/percona-release_latest.$(lsb_release -sc)_all.deb
    sudo apt install ./percona-release_latest.$(lsb_release -sc)_all.deb
    sudo percona-release setup pxb-80
    sudo apt update
    sudo apt install percona-xtrabackup-80
    sudo apt install lz4 zstd
    sudo apt-get install awscli


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
  name    = "build-staging"
  sources = ["source.amazon-ebs.staging"]

  provisioner "shell" {
    inline = local.setup_commands
  }

  provisioner "shell" {
    inline = local.mysql_password_setup
  }
}

###############################################
# BUILD BLOCK - PRODUCTION
###############################################
build {
  name    = "build-production"
  sources = ["source.amazon-ebs.production"]

  provisioner "shell" {
    inline = local.setup_commands
  }

  provisioner "shell" {
    inline = local.mysql_password_setup
  }
}

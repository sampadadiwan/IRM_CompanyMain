packer {
  required_plugins {
    amazon = {
      version = "~> 1.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

# Declare the ami_date variable
variable "ami_date" {
  type    = string
  default = ""  # Optional default value (if needed)
}



variable "aws_region" {
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

variable "ssh_keys_to_copy" {
  type = string
  default = "[]" # Default to an empty JSON array string
}

variable "user_home_dir" {
  type = string
}

source "amazon-ebs" "ubuntu" {
  ami_name      = "AppServer-${var.ami_date}"
  instance_type = "t2.micro"
  region        = var.aws_region

  # Packer now requires either source_ami or source_ami_filter.
  # Since source_ami is provided as a variable, we don't need source_ami_filter.
  # The owner is implicitly handled by the SSM parameter store lookup.
  associate_public_ip_address = "true"
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

  vpc_id                      = var.vpc_id
  subnet_id                   = var.subnet_id
  ssh_interface               = "public_ip"
  security_group_id           = var.security_group_id
  ssh_username                = "ubuntu"
  ssh_timeout                 = "15m" # Increase SSH timeout to 15 minutes
  ssh_clear_authorized_keys   = true # Clear authorized keys on the instance

   # Add tags for the AMI
  tags = {
    "Name"         = "AppServer"
    "CreatedBy"    = "Packer"
  }
  user_data = <<EOF
#!/bin/bash
# Disable UFW (Uncomplicated Firewall)
ufw disable

# Ensure SSH service is running
systemctl enable ssh
systemctl start ssh
EOF
}

build {
  name = "AppServer"
  sources = [
    "source.amazon-ebs.ubuntu"
  ]

  # Setup .ssh directory and permissions
  provisioner "shell" {
    execute_command = "chmod +x {{.Path}}; {{.Path}}"

    inline = [

      "mkdir -p /home/ubuntu/.ssh",
      "chmod 700 /home/ubuntu/.ssh",
      "chown ubuntu:ubuntu /home/ubuntu/.ssh",

      "export DEBIAN_FRONTEND='noninteractive'",
      "sudo rm -r /var/lib/apt/lists/*",
      "sudo apt update",
      "sudo apt-get update",
      "sudo apt-get upgrade --yes",
      "sudo apt-get install --yes zsh",


      // Install OhMyZsh
      "yes | sh -c \"$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\" \"\" --unattended",

      // microsoft fonts - tbd
      "echo INSTALLING- MS Fonts",
      "echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | sudo debconf-set-selections",
      "sudo apt-get install --yes ttf-mscorefonts-installer",

      // RVM
      "echo INSTALLING- RVM and Ruby 3.3.3",
      "sudo apt-get install -y curl gnupg build-essential",
      "gpg --keyserver keyserver.ubuntu.com --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB",
      // "curl -sSL https://get.rvm.io | bash",
      // "curl -sSL https://get.rvm.io | bash -s stable --rails"
      // intalling ruby along with rvm as rvm is not recognized as a package unless the terminal is reopened
      "curl -sSL https://get.rvm.io | bash -s stable --ruby=3.4.4",


      // docker
      "echo INSTALLING- Docker",
      "sudo apt install --yes apt-transport-https ca-certificates curl software-properties-common",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg",
      "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",
      "sudo apt update",
      "sudo apt install --yes docker-ce",

      // database
      "echo INSTALLING- MySql",
      "sudo apt install --yes mysql-client",
      "sudo apt-get install --yes libmysqlclient-dev",
      // "sudo systemctl start mysql.service",
      // libreoffice
      "echo INSTALLING- LibreOffice",
      "sudo add-apt-repository ppa:libreoffice/ppa",
      "sudo apt install --yes libreoffice",
      //  monit
      "echo INSTALLING- Monit",
      "sudo apt install --yes monit ",
      "echo 'set httpd port 2812 and', 'use address localhost', 'allow localhost' | sudo tee /etc/monit/conf.d/httpd",
      "sudo systemctl enable monit",
      "sudo systemctl restart monit",
      "sudo systemctl status monit",
      // log rotate
      "sudo apt install --yes logrotate",
      // nginx
      "echo INSTALLING- Nginx",
      "sudo apt install --yes nginx",
      "sudo ufw app list",
      "sudo ufw allow 'Nginx HTTP'",
      "sudo ufw status",
      "systemctl status nginx",
      // pdftk
      "echo INSTALLING- pdftk",
      "sudo apt install --yes pdftk",
      "sudo apt install --yes pv",
      "sudo apt install --yes unzip",
      "sudo apt install --yes imagemagick",
      "sudo apt install --yes poppler-utils",
      "sudo apt install --yes ffmpeg",


    ]
  }

  # Copy over the ssh keys to the prod/dev server
  dynamic "provisioner" {
    for_each = jsondecode(var.ssh_keys_to_copy)
    labels = ["file"]
    content {
      source      = "${var.user_home_dir}/.ssh/${provisioner.value}"
      destination = "/home/ubuntu/.ssh/${provisioner.value}"
    }
  }

}

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
  region        = "ap-south-1"

  // skip_region_validation = "true"
  associate_public_ip_address = "true"
  source_ami                  = var.source_ami
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
    scripts = ["${path.root}/copy_ssh_keys.sh"]
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

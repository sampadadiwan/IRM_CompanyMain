packer {
  required_plugins {
    amazon = {
      version = ">= 0.0.2"
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

source "amazon-ebs" "ubuntu" {
  ami_name      = "Observability-${var.ami_date}"
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

   # Add tags for the AMI
  tags = {
    "Name"         = "Observability"
    "CreatedBy"    = "Packer"
  }
}

build {
  name = "Observability"
  sources = [
    "source.amazon-ebs.ubuntu"
  ]

  # Use the 'file' provisioner to copy the file
  provisioner "file" {
    source      = "config/initializers/observability/prometheus.yml" # Path to the file on your local machine
    destination = "/home/ubuntu/prometheus.yml" # Path to the destination on the server
  }

  provisioner "shell" {
    inline = [
      "export DEBIAN_FRONTEND='noninteractive'",
      "sudo rm -r /var/lib/apt/lists/*",
      "sudo apt update",
      "sudo apt-get update",
      "sudo apt-get upgrade --yes",
      "sudo apt-get install --yes zsh",


      "wget https://github.com/prometheus/prometheus/releases/download/v2.41.0/prometheus-2.41.0.linux-amd64.tar.gz",
      "tar xvfz prometheus-2.41.0.linux-amd64.tar.gz",
      "sudo mv prometheus-2.41.0.linux-amd64 /opt/prometheus",
      "sudo ln -s /opt/prometheus/prometheus /usr/local/bin/prometheus",
      "sudo ln -s /opt/prometheus/promtool /usr/local/bin/promtool",
      "wget https://dl.grafana.com/oss/release/grafana_9.3.2_amd64.deb",
      "sudo apt-get install -y adduser libfontconfig1",
      "sudo dpkg -i grafana_9.3.2_amd64.deb",

      "sudo useradd --no-create-home --shell /bin/false prometheus",
      "sudo mkdir -p /etc/prometheus",
      "sudo cp /home/ubuntu/prometheus.yml /etc/prometheus/prometheus.yml",
      "sudo chown -R prometheus:prometheus /etc/prometheus",
      "sudo chown -R prometheus:prometheus /opt/prometheus",
      "sudo tee /etc/systemd/system/prometheus.service > /dev/null <<EOL",
      "[Unit]",
      "Description=Prometheus",
      "Wants=network-online.target",
      "After=network-online.target",
      "",
      "[Service]",
      "User=prometheus",
      "Group=prometheus",
      "Type=simple",
      "ExecStart=/usr/local/bin/prometheus \\",
      "  --config.file=/etc/prometheus/prometheus.yml \\",
      "  --storage.tsdb.path=/var/lib/prometheus \\",
      "  --web.console.templates=/opt/prometheus/consoles \\",
      "  --web.console.libraries=/opt/prometheus/console_libraries",
      "",
      "[Install]",
      "WantedBy=multi-user.target",
      "EOL",
      "sudo systemctl daemon-reload",
      "sudo systemctl start prometheus",
      "sudo systemctl enable prometheus",
      "sudo systemctl start grafana-server",
      "sudo systemctl enable grafana-server",
      "sudo mkdir -p /var/lib/prometheus",
      "sudo chown -R prometheus:prometheus /var/lib/prometheus",
      "sudo chmod -R 775 /var/lib/prometheus",




      // log rotate
      "sudo apt install --yes logrotate",


    ]
  }
}

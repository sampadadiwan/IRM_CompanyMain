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

source "amazon-ebs" "ubuntu" {
  ami_name      = "Observability-${var.ami_date}"
  instance_type = "t2.micro"
  region        = "ap-south-1"
  source_ami    = "ami-0522ab6e1ddcc7055"
  // skip_region_validation = "true"
  associate_public_ip_address = "true"
  vpc_id                      = "vpc-0a5573442e8b54a08"
  subnet_id                   = "subnet-02e6d37e5ec01bb5f"
  ssh_interface               = "public_ip"
  security_group_id           = "sg-07fdf064150f9f0b1"
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


      // docker
      "echo INSTALLING- Docker",
      "sudo apt install --yes apt-transport-https ca-certificates curl software-properties-common",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg",
      "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",
      "sudo apt update",
      "sudo apt install --yes docker-ce",

      // log rotate
      "sudo apt install --yes logrotate",

      // Create the docker network
      "sudo docker network create grafana-prometheus",

      // Run the docker instances for prometheus and graphana from crontab
      "(crontab -l 2>/dev/null; echo '@reboot sudo docker run --rm --name my-prometheus --network grafana-prometheus --network-alias prometheus --publish 9090:9090 --volume /home/ubuntu/prometheus.yml:/etc/prometheus/prometheus.yml --detach prom/prometheus') | crontab -u ubuntu -",
      "(crontab -l 2>/dev/null; echo '@reboot sudo docker run --rm --name grafana --network grafana-prometheus --network-alias grafana --publish 8000:3000 --detach grafana/grafana-oss:latest') | crontab -u ubuntu -",
    ]
  }
}

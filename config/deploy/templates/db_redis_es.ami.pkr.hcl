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
  ami_name      = "DB_Redis_ES-${var.ami_date}"
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
    "Name"         = "DB_Redis_ES"
    "CreatedBy"    = "Packer"
  }
}

build {
  name = "DB_Redis_ES"
  sources = [
    "source.amazon-ebs.ubuntu"
  ]


  provisioner "shell" {
    inline = [
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

      // Run the docker instances for ES and Redis from crontab
      "(crontab -l 2>/dev/null; echo '@reboot sudo docker run -d --rm --name elasticsearch -p 9200:9200 -p 9300:9300 -e \"discovery.type=single-node\" elasticsearch:7.11.1') | crontab -u ubuntu -",
      "(crontab -l 2>/dev/null; echo '@reboot sudo docker run -d --rm --name redis-stack-server -p 6379:6379  redis/redis-stack-server:latest') | crontab -u ubuntu -",

      // Now install mysql 8 server
      "sudo apt-get install -y mysql-server",  # Install MySQL 8 from Ubuntu repos
      "sudo systemctl start mysql",            # Start MySQL
      "sudo systemctl enable mysql",           # Enable MySQL to start on boot

      "sudo service mysql restart",
      
    ]
  }

  provisioner "shell" {
    inline = [
      "echo \"ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'MyStrongPassword';\" > /tmp/mysql-init.sql",
      "echo \"FLUSH PRIVILEGES;\" >> /tmp/mysql-init.sql",
      "sudo mysql < /tmp/mysql-init.sql",  # Run the SQL script to reset root password
      "rm /tmp/mysql-init.sql"             # Clean up the SQL script
    ]
  }

}

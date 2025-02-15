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
  ami_name      = "AppServer-${var.ami_date}"
  instance_type = "t2.micro"
  region        = "ap-south-1"
  
  // skip_region_validation = "true"
  associate_public_ip_address = "true"
  // Dev
  // source_ami                  = "ami-0522ab6e1ddcc7055"
  // vpc_id                      = "vpc-0a5573442e8b54a08"
  // subnet_id                   = "subnet-02e6d37e5ec01bb5f"
  // ssh_interface               = "public_ip"
  // security_group_id           = "sg-07fdf064150f9f0b1"
  // ssh_username                = "ubuntu"

  // Prod
  source_ami                  = "ami-0522ab6e1ddcc7055"
  vpc_id                      = "vpc-0cb0c5cad8c279582"
  subnet_id                   = "subnet-0cf73758b0fb6a9b5"
  ssh_interface               = "public_ip"
  security_group_id           = "sg-02fe5b268dcb2b2a3"
  ssh_username                = "ubuntu"
  

   # Add tags for the AMI
  tags = {
    "Name"         = "AppServer"
    "CreatedBy"    = "Packer"
  }
}

build {
  name = "AppServer"
  sources = [
    "source.amazon-ebs.ubuntu"
  ]

  provisioner "shell" {
    inline = [
      "export DEBIAN_FRONTEND='noninteractive'",
      "sudo rm -r /var/lib/apt/lists/*",
      "sudo apt update",
      "sudo apt-get update",
      "sudo apt-get upgrade --yes",
      "sudo apt-get install --yes zsh",

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
      "curl -sSL https://get.rvm.io | bash -s stable --ruby=3.3.3",


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
      "sudo systemctl enable monit",
      "sudo systemctl start monit",
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
      "sudo apt install --yes imagemagick"
      "sudo apt install --yes poppler-utils"
      "sudo apt install --yes ffmpeg"
      
    ]
  }
}

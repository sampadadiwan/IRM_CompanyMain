packer {
  required_plugins {
    amazon = {
      version = ">= 0.0.2"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

source "amazon-ebs" "ubuntu" {
  ami_name      = "pkr ub22 051023"
  instance_type = "t2.micro"
  region        = "ap-south-1"
  source_ami    = "ami-0f5ee92e2d63afc18"
  // skip_region_validation = "true"
  associate_public_ip_address = "true"
  vpc_id                      = "vpc-00364cf49c3f42a03"
  subnet_id                   = "subnet-0203665947eb41df9"
  ssh_interface               = "public_ip"
  security_group_id           = "sg-0e15ce838c2a1c70a"
  ssh_username                = "ubuntu"
}

build {
  name = "packer ubuntu 22"
  sources = [
    "source.amazon-ebs.ubuntu"
  ]

  provisioner "shell" {
    inline = [
      "export DEBIAN_FRONTEND='noninteractive'",
      "sudo rm -r /var/lib/apt/lists/*",
      "sudo apt update",
      "sudo apt-get update",

      // microsoft fonts - tbd
      "echo INSTALLING- MS Fonts",
      "echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | sudo debconf-set-selections",
      "sudo apt-get install --yes ttf-mscorefonts-installer",

      // RVM
      "echo INSTALLING- RVM and Ruby 3.1.2",
      "sudo apt-get install -y curl gnupg build-essential",
      "gpg --keyserver keyserver.ubuntu.com --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB",
      // "curl -sSL https://get.rvm.io | bash",
      // "curl -sSL https://get.rvm.io | bash -s stable --rails"
      // intalling ruby along with rvm as rvm is not recognized as a package unless the terminal is reopened
      "curl -sSL https://get.rvm.io | bash -s stable --ruby=3.1.2",

      // "exec $SHELL",
      // "bash -c 'source /home/ubuntu/.rvm/scripts/rvm'",
      // "bash -c 'source ~/.rvm/scripts/rvm'",
      // "sudo usermod -a -G rvm `whoami`",

      // Ruby
      // "rvm install ruby-3.1.2",
      // "rvm use ruby-3.1.2 --default",
      // "gem install bundler --no-rdoc --no-ri",
      // Rails
      // "gem install rails -v 7.0.6",

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
      "systemctl status nginx"
    ]
  }
}

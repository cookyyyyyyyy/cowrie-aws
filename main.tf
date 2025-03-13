terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

resource "aws_vpc" "vpc-tofu" {
    cidr_block = var.vpc_cidr_block
    tags = {
        Name = var.name_vpc
    }

    provisioner "local-exec" {
      command = "echo 'VPC create'"
    }
}

resource "aws_subnet" "vpc-tofu-sub" {
  vpc_id = aws_vpc.vpc-tofu.id
  cidr_block = var.sub_cidr_block
  availability_zone = var.sub_region
  map_public_ip_on_launch = true

  tags = {
    Name = "tofu-sub"
  }

  provisioner "local-exec" {
    command = "echo 'subnet create'"
  }
}

resource "aws_key_pair" "ssh-key" {
    key_name = "tofu"
    public_key = file(var.pub_key)
}

resource "aws_internet_gateway" "tofu-igw" {
  vpc_id = aws_vpc.vpc-tofu.id

  tags = {
    Name = "tofu-igw"
  }
}

resource "aws_route_table" "tofu-route-table" {
  vpc_id = aws_vpc.vpc-tofu.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.tofu-igw.id
  }

  tags = {
    "Name" = "tofu-pub-route-table"
  }
}

resource "aws_route_table_association" "subnet-route-association" {
  subnet_id = aws_subnet.vpc-tofu-sub.id
  route_table_id = aws_route_table.tofu-route-table.id
}

resource "aws_security_group" "tofu-sg" {
  vpc_id = aws_vpc.vpc-tofu.id

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 22222
    to_port = 22222
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "tofu-sg"
  }

  provisioner "local-exec" {
    command = "echo 'security group create'"
  }
}

resource "aws_instance" "tofu-ec2" {
  ami = "ami-06e02ae7bdac6b938"
  instance_type = "t2.micro"
  subnet_id = aws_subnet.vpc-tofu-sub.id
  key_name = aws_key_pair.ssh-key.key_name
  security_groups = [ aws_security_group.tofu-sg.id ]
  user_data = <<EOF
#!/bin/bash
sudo su -
apt update -y && apt update -y
apt install -y git python3-virtualenv libssl-dev build-essential libpython3-dev python3-minimal authbind
useradd -m cowrie
passwd -d cowrie

sudo git clone http://github.com/micheloosterhof/cowrie /home/cowrie/cowrie
virtualenv /home/cowrie/cowrie/cowrie-env
source /home/cowrie/cowrie/cowrie-env/bin/activate

pip install --upgrade pip
pip install --upgrade -r /home/cowrie/cowrie/requirements.txt

cp /home/cowrie/cowrie/etc/cowrie.cfg.dist /home/cowrie/cowrie/etc/cowrie.cfg
chown -R cowrie:cowrie /home/cowrie/cowrie
EOF

  tags = {
    Name = "ec2-tofu"
  }

  provisioner "local-exec" {
    command = "echo 'ec2 instance create'"
  }
}

output "ec2-pub-ip" {
  value = aws_instance.tofu-ec2.public_ip
  description = "IP publique de l'instance EC2"
}

output "ec2_public_dns" {
  value       = aws_instance.tofu-ec2.tags.Name
  description = "Nom DNS public de l'instance EC2"
}

resource "null_resource" "generate_ansible_inventory" {
  depends_on = [aws_instance.tofu-ec2]  # Attendre la création de l'EC2

  provisioner "local-exec" {
    command = <<EOT
    echo "[ec2-instance]" > inventory.ini
    echo "${aws_instance.tofu-ec2.tags.Name} ansible_host=${aws_instance.tofu-ec2.public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_rsa" >> inventory.ini
    sudo echo "${aws_instance.tofu-ec2.tags.Name} ${aws_instance.tofu-ec2.public_ip}" | sudo tee -a /etc/hosts
    EOT
  }
}

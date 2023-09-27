#------------------------------------------------------------------
# Provision Highly Availabe Web Cluster in any Region Default VPC
# Create:
#    - Security Group for Web Server and ELB
#    - Launch Configuration with Auto AMI Lookup
#    - Auto Scaling Group using 2 Availability Zones
#    - Classic Load Balancer in 2 Availability Zones
# Update to Web Servers will be via Green/Blue Deployment Strategy
#------------------------------------------------------------------

### PROVIDER ###

provider "aws" {
  region = "eu-west-3"
}

### LATEST AMI ###

data "aws_availability_zones" "working" {}
data "aws_ami" "latest_amazon_linux" {
  owners      = ["137112412989"]
  most_recent = true
  filter {
    name   = "name"
    values = ["amzn2-ami-kernel-5.10-hvm-*-gp2"]
  }
}

### SG ###

resource "aws_security_group" "web" {
  name = "Web Security Group"
  dynamic "ingress" {
    for_each = ["80", "443" , "22"]
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name  = "Web Security Group"
    Owner = "Michele"
  }
}

### INSTANCE ###

resource "aws_launch_configuration" "web" {
  name_prefix     = "WebServer-Highly-Available-LC-"
  image_id        = data.aws_ami.latest_amazon_linux.id
  instance_type   = "t3.micro"
  security_groups = [aws_security_group.web.id]
  user_data       = file("user_data.sh")

### DOWNTIME ###
  lifecycle {
    create_before_destroy = true
  }
}


### AUTOSCALING ###

resource "aws_autoscaling_group" "web" {
  name                 = "ASG-${aws_launch_configuration.web.name}"
  launch_configuration = aws_launch_configuration.web.name
  min_size             = 2  ### instance min
  max_size             = 2  ### instance max
  min_elb_capacity     = 2
  health_check_type    = "ELB"
  vpc_zone_identifier  = [aws_default_subnet.default_az1.id, aws_default_subnet.default_az2.id]
  load_balancers       = [aws_elb.web.name]

  dynamic "tag" {
    for_each = {
      Name   = "WebServer in ASG"
      Owner  = "Michele"
      TAGKEY = "TAGVALUE"
    }
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

### ELB ###

resource "aws_elb" "web" {
  name               = "WebServer-HighlyAvailable-ELB"
  availability_zones = [data.aws_availability_zones.working.names[0], data.aws_availability_zones.working.names[1]]
  security_groups    = [aws_security_group.web.id]
  listener {
    lb_port           = 80
    lb_protocol       = "http"
    instance_port     = 80
    instance_protocol = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/"
    interval            = 10
  }
  tags = {
    Name  = "WebServer-HighlyAvailable-ELB"
    Owner = " Michele "
  }
}

### SUBNET DEFAULT ###
resource "aws_default_subnet" "default_az1" {
  availability_zone = data.aws_availability_zones.working.names[0]  ### [0] indica la prima zona di disponibilità
}

resource "aws_default_subnet" "default_az2" {
  availability_zone = data.aws_availability_zones.working.names[1]  ### [1] indica la seconda zona di disponibilità
}


### OUTPUT ###

output "web_loadbalancer_url" {
  value = aws_elb.web.dns_name
}


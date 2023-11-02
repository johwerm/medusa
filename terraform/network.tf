variable "vpc_cidr_block" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_count" {
  description = "Number of subnets"
  type        = map(number)
  default = {
    public  = 2,
    private = 2
  }
}

variable "public_subnet_cidr_blocks" {
  description = "Available CIDR blocks for public subnets"
  type        = list(string)
  default = [
    "10.0.1.0/24",
    "10.0.2.0/24",
    "10.0.3.0/24",
    "10.0.4.0/24"
  ]
}

// This variable contains the CIDR blocks for
// the public subnet. I have only included 4 
// for this tutorial, but if you need more you
// would add them here
variable "private_subnet_cidr_blocks" {
  description = "Available CIDR blocks for private subnets"
  type        = list(string)
  default = [
    "10.0.101.0/24",
    "10.0.102.0/24",
    "10.0.103.0/24",
    "10.0.104.0/24",
  ]
}

data "aws_availability_zones" "medusa" {
  state = "available"
}

resource "aws_vpc" "medusa" {

  cidr_block           = var.vpc_cidr_block
  enable_dns_hostnames = true
  tags = {
    Name = "medusa"
  }
}

resource "aws_internet_gateway" "medusa" {
  vpc_id = aws_vpc.medusa.id
  tags = {
    Name = "medusa"
  }
}

// Create a group of public subnets based on the variable subnet_count.public
resource "aws_subnet" "medusa_public_subnet" {
  count             = var.subnet_count.public
  vpc_id            = aws_vpc.medusa.id
  cidr_block        = cidrsubnet(aws_vpc.medusa.cidr_block, 8, count.index)
  map_public_ip_on_launch = true
  availability_zone = data.aws_availability_zones.medusa.names[count.index]
  tags = {
    Name = "medusa_public_subnet_${count.index}"
  }
}

// Create a group of private subnets based on the variable subnet_count.private
resource "aws_subnet" "medusa_private_subnet" {
  count             = var.subnet_count.private
  vpc_id            = aws_vpc.medusa.id
  cidr_block        = cidrsubnet(aws_vpc.medusa.cidr_block, 8, count.index + 100)
  availability_zone = data.aws_availability_zones.medusa.names[count.index]
  tags = {
    Name = "medusa_private_subnet_${count.index}"
  }
}

resource "aws_route_table" "medusa_public_rt" {
  vpc_id = aws_vpc.medusa.id

  // Since this is the public route table, it will need
  // access to the internet. So we are adding a route with
  // a destination of 0.0.0.0/0 and targeting the Internet 	 
  // Gateway "tutorial_igw"
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.medusa.id
  }
}

resource "aws_route_table_association" "public" {
  count          = var.subnet_count.public
  route_table_id = aws_route_table.medusa_public_rt.id
  subnet_id      = aws_subnet.medusa_public_subnet[count.index].id
}

resource "aws_route_table" "medusa_private_rt" {
  vpc_id = aws_vpc.medusa.id
}

resource "aws_route_table_association" "private" {
  count          = var.subnet_count.private
  route_table_id = aws_route_table.medusa_private_rt.id
  subnet_id      = aws_subnet.medusa_private_subnet[count.index].id
}

resource "aws_security_group" "medusa_web_sg" {
  name        = "medusa-web-sg"
  description = "Security group for medusa web servers"
  vpc_id      = aws_vpc.medusa.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    self        = "false"
    cidr_blocks = ["0.0.0.0/0"]
    description = "any"
  }

  # ingress {
  #   description = "Allow all traffic through HTTP"
  #   from_port   = "80"
  #   to_port     = "80"
  #   protocol    = "tcp"
  #   cidr_blocks = ["0.0.0.0/0"]
  # }

  # ingress {
  #   description = "Allow all traffic through HTTP"
  #   from_port   = "8080"
  #   to_port     = "8080"
  #   protocol    = "tcp"
  #   cidr_blocks = ["0.0.0.0/0"]
  # }

  # ingress {
  #   description = "Allow SSH from my computer"
  #   from_port   = "22"
  #   to_port     = "22"
  #   protocol    = "tcp"
  #   cidr_blocks = ["0.0.0.0/0"]
  #   #cidr_blocks = ["${var.my_ip}/32"]
  # }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "medusa-web-sg"
  }
}

resource "aws_security_group" "medusa_db_sg" {
  name        = "medusa-db-sg"
  description = "Security group for medusa databases"
  vpc_id      = aws_vpc.medusa.id

  // The third requirement was "RDS should be on a private subnet and 	
  // inaccessible via the internet." To accomplish that, we will 
  // not add any inbound or outbound rules for outside traffic.
  
  // The fourth and finally requirement was "Only the EC2 instances 
  // should be able to communicate with RDS." So we will create an
  // inbound rule that allows traffic from the EC2 security group
  // through TCP port 3306, which is the port that MySQL 
  // communicates through
  ingress {
    description     = "Allow PostgreSQL traffic from only the web sg"
    from_port       = "5432"
    to_port         = "5432"
    protocol        = "tcp"
    security_groups = [aws_security_group.medusa_web_sg.id]
  }

  tags = {
    Name = "medusa-db-sg"
  }
}

resource "aws_db_subnet_group" "medusa_db_subnet_group" {
  name        = "medusa_db_subnet_group"
  description = "DB subnet group for medusa"
  subnet_ids  = [for subnet in aws_subnet.medusa_private_subnet : subnet.id]
}
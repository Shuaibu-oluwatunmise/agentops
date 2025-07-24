data "aws_vpc" "default" {
  default = true
}

resource "aws_subnet" "eks" {
  count             = length(data.aws_vpc.default.cidr_block) > 0 ? 2 : 2
  vpc_id            = data.aws_vpc.default.id
  cidr_block        = cidrsubnet(data.aws_vpc.default.cidr_block, 8, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
}

data "aws_availability_zones" "available" {}
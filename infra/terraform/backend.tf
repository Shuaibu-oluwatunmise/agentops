terraform {
  backend "s3" {
    bucket         = "agentops-terraform-state-us-west-1"
    key            = "terraform.tfstate"
    region         = "us-west-1"
    dynamodb_table = "agentops-terraform-locks"
    encrypt        = true
  }
}

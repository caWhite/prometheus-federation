# Prometheus Federation

Terraform demo for running Prometheus with hierarchical federation on AWS.

This example creates an AWS VPC, public subnets spanning 2 availability zones, and a Prometheus instance in each one. During initialization, [cloud-init](https://cloudinit.readthedocs.io/en/latest/) directives passed in via EC2 user-data are executed to retrieve the `node_exporter` and `prometheus` binaries, as well as configure them as services on each server. Both instances share a base Prometheus configuration in which static scrape targets are specified for the local `node_exporter` and `prometheus` ports. Additionally, the federation instance uses EC2 service discovery to identify dynamic targets and scrape the `/federate` endpoint on each one.

## Prerequisites
- [Terraform](https://developer.hashicorp.com/terraform/downloads)
- [AWS account](https://aws.amazon.com/free/)

## Getting Started

```bash
# Clone the repository from source control
❯ git clone https://github.com/cawhite/prometheus-federation.git && cd prometheus-federation

# Initialize the Terraform configuration 
❯ terraform init

# Optionally, inspect the proposed resources before continuing
❯ terraform plan 

# Apply the Terraform configuration 
❯ terraform apply 

# Prometheus web URLs can be found in Terraform outputs. A private key is also exported to troubleshoot an installation via SSH.
❯ terraform output
prometheus_downstream_webui = "http://<ec2-public-dns-name>:9090"
prometheus_federator_webui = "http://<ec2-public-dns-name>:9090"
ssh_private_key = <sensitive>

# Destroy resources when done to stop incurring costs
terraform destroy 

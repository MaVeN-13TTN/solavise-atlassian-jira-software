# AWS Resource Cleanup Instructions

This repository includes a cleanup script (`cleanup.sh`) that helps ensure all provisioned AWS resources are properly deleted to prevent unnecessary costs.

## Prerequisites

1. AWS CLI installed and configured with appropriate credentials
2. Terraform installed (if using Terraform-managed resources)

## Usage

1. Make the script executable:
   ```bash
   chmod +x cleanup.sh
   ```

2. Run the script:
   ```bash
   ./cleanup.sh
   ```

## What the script does

1. First attempts to use Terraform destroy if Terraform is being used
2. Then performs manual cleanup of various AWS resources including:
   - EC2 instances
   - Elastic Load Balancers
   - ECS services and clusters
   - S3 buckets
   - RDS instances
   - Security Groups
   - VPCs and associated resources

## Important Notes

- The script requires AWS CLI access with sufficient permissions to delete resources
- It will attempt to delete ALL resources in the configured AWS region
- Make sure you are running this in the correct AWS account
- Always review the resources that will be deleted before running the script
- Consider backing up any important data before running the cleanup
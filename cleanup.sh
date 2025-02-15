#!/bin/bash

# Cleanup script to delete all provisioned AWS resources

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo "AWS credentials are not configured. Please configure them first."
    exit 1
fi

echo "Starting cleanup of AWS resources..."

# If using Terraform
if [ -d "jira-bitbucket-aws/terraform" ]; then
    echo "Terraform directory found. Attempting to destroy resources..."
    cd jira-bitbucket-aws/terraform
    terraform init
    terraform destroy -auto-approve
    cd ../..
fi

# Additional manual cleanup in case Terraform state is lost or resources were created outside Terraform
echo "Performing additional cleanup..."

# Get the AWS region
AWS_REGION=$(aws configure get region)
if [ -z "$AWS_REGION" ]; then
    AWS_REGION="us-east-1"  # Default to us-east-1 if no region is set
fi

# Delete EC2 instances
echo "Cleaning up EC2 resources..."
INSTANCE_IDS=$(aws ec2 describe-instances --region $AWS_REGION --query 'Reservations[].Instances[?State.Name!=`terminated`].InstanceId' --output text)
if [ ! -z "$INSTANCE_IDS" ]; then
    aws ec2 terminate-instances --region $AWS_REGION --instance-ids $INSTANCE_IDS
    echo "Waiting for instances to terminate..."
    aws ec2 wait instance-terminated --region $AWS_REGION --instance-ids $INSTANCE_IDS
fi

# Delete ELB if any
echo "Cleaning up Elastic Load Balancers..."
ELBS=$(aws elb describe-load-balancers --region $AWS_REGION --query 'LoadBalancerDescriptions[].LoadBalancerName' --output text)
for ELB in $ELBS; do
    aws elb delete-load-balancer --region $AWS_REGION --load-balancer-name $ELB
done

# Delete ECS services and clusters if any
echo "Cleaning up ECS resources..."
CLUSTERS=$(aws ecs list-clusters --region $AWS_REGION --query 'clusterArns[]' --output text)
for CLUSTER in $CLUSTERS; do
    SERVICES=$(aws ecs list-services --region $AWS_REGION --cluster $CLUSTER --query 'serviceArns[]' --output text)
    for SERVICE in $SERVICES; do
        aws ecs update-service --region $AWS_REGION --cluster $CLUSTER --service $SERVICE --desired-count 0
        aws ecs delete-service --region $AWS_REGION --cluster $CLUSTER --service $SERVICE
    done
    aws ecs delete-cluster --region $AWS_REGION --cluster $CLUSTER
done

# Delete S3 buckets
echo "Cleaning up S3 buckets..."
BUCKETS=$(aws s3api list-buckets --query 'Buckets[].Name' --output text)
for BUCKET in $BUCKETS; do
    aws s3 rb s3://$BUCKET --force
done

# Delete RDS instances
echo "Cleaning up RDS instances..."
RDS_INSTANCES=$(aws rds describe-db-instances --region $AWS_REGION --query 'DBInstances[].DBInstanceIdentifier' --output text)
for RDS in $RDS_INSTANCES; do
    aws rds delete-db-instance --region $AWS_REGION --db-instance-identifier $RDS --skip-final-snapshot
done

# Clean up security groups
echo "Cleaning up security groups..."
SECURITY_GROUPS=$(aws ec2 describe-security-groups --region $AWS_REGION --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text)
for SG in $SECURITY_GROUPS; do
    aws ec2 delete-security-group --region $AWS_REGION --group-id $SG
done

# Clean up VPCs
echo "Cleaning up VPCs..."
VPCS=$(aws ec2 describe-vpcs --region $AWS_REGION --query 'Vpcs[?IsDefault==`false`].VpcId' --output text)
for VPC in $VPCS; do
    # Delete associated subnets
    SUBNETS=$(aws ec2 describe-subnets --region $AWS_REGION --filters "Name=vpc-id,Values=$VPC" --query 'Subnets[].SubnetId' --output text)
    for SUBNET in $SUBNETS; do
        aws ec2 delete-subnet --region $AWS_REGION --subnet-id $SUBNET
    done
    
    # Delete route tables
    ROUTE_TABLES=$(aws ec2 describe-route-tables --region $AWS_REGION --filters "Name=vpc-id,Values=$VPC" --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text)
    for RT in $ROUTE_TABLES; do
        aws ec2 delete-route-table --region $AWS_REGION --route-table-id $RT
    done
    
    # Delete internet gateways
    IGWs=$(aws ec2 describe-internet-gateways --region $AWS_REGION --filters "Name=attachment.vpc-id,Values=$VPC" --query 'InternetGateways[].InternetGatewayId' --output text)
    for IGW in $IGWs; do
        aws ec2 detach-internet-gateway --region $AWS_REGION --internet-gateway-id $IGW --vpc-id $VPC
        aws ec2 delete-internet-gateway --region $AWS_REGION --internet-gateway-id $IGW
    done
    
    # Finally delete the VPC
    aws ec2 delete-vpc --region $AWS_REGION --vpc-id $VPC
done

echo "Cleanup completed!"
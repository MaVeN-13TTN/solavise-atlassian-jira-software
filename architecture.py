from diagrams import Diagram, Cluster, Edge
from diagrams.aws.compute import ECS, EC2
from diagrams.aws.database import RDS
from diagrams.aws.storage import S3, EFS
from diagrams.aws.network import ALB, Route53, CloudFront
from diagrams.aws.security import IAM, WAF, SecretsManager
from diagrams.aws.management import Cloudwatch, SystemsManager  # Updated import
from diagrams.aws.analytics import ElasticsearchService
from diagrams.onprem.ci import GithubActions
from diagrams.onprem.vcs import Github
from diagrams.onprem.workflow import Airflow

# Create the diagram
with Diagram("Jira/Bitbucket Data Center on AWS", show=False, direction="LR"):
    # Define nodes
    dns = Route53("Route53")
    cf = CloudFront("CloudFront")
    alb = ALB("ALB")
    waf = WAF("WAF")
    iam = IAM("IAM")
    secrets = SecretsManager("Secrets Manager")
    cloudwatch = Cloudwatch("CloudWatch")  # Updated node
    ssm = SystemsManager("Systems Manager")

    # VPC and Networking
    with Cluster("VPC"):
        with Cluster("Public Subnet"):
            public_subnet = [cf, alb, waf]

        with Cluster("Private Subnet"):
            with Cluster("ECS Cluster"):
                ecs = ECS("ECS")
                ec2 = EC2("EC2")
                ecs - Edge(color="brown", style="dashed") - ec2

            with Cluster("Database Layer"):
                rds_primary = RDS("RDS (Primary)")
                rds_replica = RDS("RDS (Replica)")
                rds_primary - Edge(color="blue", style="dotted") - rds_replica

            with Cluster("Storage Layer"):
                efs = EFS("EFS")
                s3 = S3("S3")

            with Cluster("Search Layer"):
                opensearch = ElasticsearchService("OpenSearch")

    # CI/CD Pipeline
    with Cluster("CI/CD Pipeline"):
        github = Github("GitHub")
        codebuild = GithubActions("CodeBuild")
        codedeploy = Airflow("CodeDeploy")
        github >> codebuild >> codedeploy

    # Security and Monitoring
    iam >> Edge(color="red") >> [ecs, rds_primary, s3]
    secrets >> Edge(color="red") >> [ecs, rds_primary]
    cloudwatch >> Edge(color="green") >> [ecs, rds_primary, alb]
    ssm >> Edge(color="green") >> [ec2, rds_primary]

    # Connections
    dns >> cf >> alb >> ecs
    ecs >> Edge(color="brown") >> [rds_primary, efs, opensearch]
    rds_primary >> Edge(color="blue") >> s3
    codedeploy >> Edge(color="purple") >> ecs

import boto3
import uuid
import sys

def test_aws_credentials():
    try:
        # Create an S3 client
        s3_client = boto3.client('s3')
        
        # Generate a unique bucket name
        bucket_name = f"test-credentials-{uuid.uuid4()}"
        
        print(f"Attempting to create bucket: {bucket_name}")
        
        # Try to create a bucket
        s3_client.create_bucket(Bucket=bucket_name)
        
        print("Successfully created bucket! AWS credentials are working.")
        
        # Clean up - delete the test bucket
        print(f"Cleaning up - deleting bucket {bucket_name}")
        s3_client.delete_bucket(Bucket=bucket_name)
        
        print("Test completed successfully.")
        return True
        
    except Exception as e:
        print(f"Error: {str(e)}")
        print("Failed to create/delete bucket. Please check your AWS credentials.")
        return False

if __name__ == "__main__":
    test_aws_credentials()
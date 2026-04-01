#!/usr/bin/env python3
"""
Automated deployment script for Google Cloud Run
"""
import subprocess
import sys
import time
import os

from config import PROJECT_ID
SERVICE_NAME = "oi-data-entry-app"
REGION = "us-central1"
IMAGE_NAME = f"gcr.io/{PROJECT_ID}/{SERVICE_NAME}"

def run_command(cmd, description):
    """Run a command and handle errors"""
    print(f"\n{'='*60}")
    print(f"{description}")
    print(f"{'='*60}")
    print(f"Running: {' '.join(cmd)}")
    
    try:
        result = subprocess.run(
            cmd,
            check=True,
            capture_output=False,
            text=True
        )
        return True
    except subprocess.CalledProcessError as e:
        print(f"Error: {e}")
        return False
    except KeyboardInterrupt:
        print("\nDeployment cancelled by user")
        return False

def main():
    print("="*60)
    print("Deploying OI Data Entry App to Google Cloud Run")
    print("="*60)
    print(f"Project: {PROJECT_ID}")
    print(f"Service: {SERVICE_NAME}")
    print(f"Region: {REGION}")
    print()
    
    # Step 1: Build Docker image
    print("Step 1: Building Docker image...")
    build_cmd = [
        "gcloud", "builds", "submit",
        "--tag", IMAGE_NAME,
        "--project", PROJECT_ID,
        "--timeout", "20m"
    ]
    
    if not run_command(build_cmd, "Building Docker image"):
        print("\nBuild failed. Trying alternative method...")
        # Try with cloudbuild.yaml
        build_cmd = [
            "gcloud", "builds", "submit",
            "--config", "cloudbuild.yaml",
            "--project", PROJECT_ID
        ]
        if not run_command(build_cmd, "Building with cloudbuild.yaml"):
            print("\n❌ Build failed. Please check your network connection and try again.")
            sys.exit(1)
    
    print("\n✅ Build successful!")
    
    # Step 2: Deploy to Cloud Run
    print("\nStep 2: Deploying to Cloud Run...")
    deploy_cmd = [
        "gcloud", "run", "deploy", SERVICE_NAME,
        "--image", IMAGE_NAME,
        "--platform", "managed",
        "--region", REGION,
        "--allow-unauthenticated",
        "--set-env-vars", f"GCP_PROJECT_ID={PROJECT_ID},BIGQUERY_DATASET=OI",
        "--memory", "512Mi",
        "--cpu", "1",
        "--timeout", "300",
        "--max-instances", "10",
        "--project", PROJECT_ID
    ]
    
    if not run_command(deploy_cmd, "Deploying to Cloud Run"):
        print("\n❌ Deployment failed.")
        sys.exit(1)
    
    # Step 3: Get service URL
    print("\nStep 3: Getting service URL...")
    url_cmd = [
        "gcloud", "run", "services", "describe", SERVICE_NAME,
        "--region", REGION,
        "--project", PROJECT_ID,
        "--format", "value(status.url)"
    ]
    
    try:
        result = subprocess.run(url_cmd, capture_output=True, text=True, check=True)
        service_url = result.stdout.strip()
        
        print("\n" + "="*60)
        print("✅ Deployment Successful!")
        print("="*60)
        print(f"\nYour app is now live at:")
        print(f"  {service_url}")
        print(f"\nThis URL works 24/7, even when your computer is off!")
        print("\nYou can access it from anywhere in the world.")
    except subprocess.CalledProcessError:
        print("\n⚠️  Deployment completed but couldn't retrieve URL.")
        print(f"Check your service at: https://console.cloud.google.com/run/detail/{REGION}/{SERVICE_NAME}")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\nDeployment cancelled.")
        sys.exit(1)

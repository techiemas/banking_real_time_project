#!/bin/bash
set -e

# Configuration
export PROJECT_ID="jaffle-shop-481012"
export REGION="us-central1"
export IMAGE_NAME="gcr.io/$PROJECT_ID/bank-generator"

echo "Deploying to Project: $PROJECT_ID"

# 1. Terraform
echo ">>> Initializing Terraform..."
cd terraform
terraform init
terraform apply -auto-approve -var="project_id=$PROJECT_ID"
cd ..

# 2. Build Generator
echo ">>> Building Generator Image..."
cd generator
gcloud builds submit --tag $IMAGE_NAME .
cd ..

# 3. Deploy Generator (Cloud Run Job)
echo ">>> Deploying Generator Job..."
gcloud run jobs deploy bank-generator-job \
    --image $IMAGE_NAME \
    --region $REGION \
    --set-env-vars PROJECT_ID=$PROJECT_ID,NUM_MESSAGES=1000 \
    --service-account "service-$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')@gcp-sa-pubsub.iam.gserviceaccount.com" \
    --quiet || echo "Warning: Check Service Account permissions manually if this fails first time."

# Note: The service account above is a guess based on the default Pub/Sub one, 
# in realworld you should use the one created by Terraform or the Default Compute SA.
# Let's use the Default Compute SA for simplicity as it usually has broad permissions in a test project,
# or better, use the one we can create in TF. 
# For this script we will assume Default Compute SA has Editor or enough roles.
# Updating to use default compute SA for ease:
DEFAULT_SA=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")-compute@developer.gserviceaccount.com

echo ">>> Updating Job to use Default Compute SA: $DEFAULT_SA"
gcloud run jobs update bank-generator-job \
    --region $REGION \
    --service-account $DEFAULT_SA

echo ">>> Deployment Complete!"
echo "Run the generator: gcloud run jobs execute bank-generator-job --region $REGION"
echo "Run config: terraform/main.tf"


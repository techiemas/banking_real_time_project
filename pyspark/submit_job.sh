#!/bin/bash
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"
BUCKET="dataproc-temp2-$PROJECT_ID"

# Create temp bucket if not exists
gsutil mb -l $REGION gs://$BUCKET || true

echo "Submitting PySpark job to Dataproc Serverless..."

gcloud dataproc batches submit pyspark main.py \
    --project=$PROJECT_ID \
    --region=$REGION \
    --batch="bank-transformation-$(date +%s)" \
    --deps-bucket="gs://$BUCKET" \
    --args="$PROJECT_ID" \
    --version="2.0"

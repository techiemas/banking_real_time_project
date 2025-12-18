# GCloud Commands for Banking Pipeline

Run these commands in your terminal to setup and deploy the project.

## 1. Environment Setup
**Crucial:** Run this block first to set the variables used in subsequent commands.

```bash
export PROJECT_ID="jaffle-shop-481012"
export REGION="us-central1"

gcloud config set project $PROJECT_ID
```

## 2. Enable APIs
```bash
gcloud services enable run.googleapis.com \
    pubsub.googleapis.com \
    bigquery.googleapis.com \
    artifactregistry.googleapis.com \
    dataproc.googleapis.com \
    cloudbuild.googleapis.com \
    workflows.googleapis.com
```

## 3. BigQuery Setup
```bash
# Create Dataset
bq --location=$REGION mk -d --description "Banking Production Dataset" banking_prod

# Create Tables
bq mk --table banking_prod.banking_raw ./schema.json
bq mk --table banking_prod.banking_silver ./schema_silver.json
bq mk --table banking_prod.banking_gold ./schema_gold.json
bq mk --table banking_prod.transactions_fact ./schema_fact.json
```

## 4. Pub/Sub Setup
```bash
# Create Topic
gcloud pubsub topics create bank-transactions

# Grant permissions to Pub/Sub Service Account
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
PUBSUB_SA="service-$PROJECT_NUMBER@gcp-sa-pubsub.iam.gserviceaccount.com"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$PUBSUB_SA" \
    --role="roles/bigquery.dataEditor"

# Create Subscription
gcloud pubsub subscriptions create bank-transactions-bq-sub \
    --topic=bank-transactions \
    --bigquery-table="$PROJECT_ID.banking_prod.banking_raw" \
    --use-topic-schema
```

## 5. Build and Deploy Generator (Cloud Run)
```bash
# Build
cd generator
gcloud builds submit --tag gcr.io/$PROJECT_ID/bank-generator .
cd ..

# Deploy
# Note: Using default compute service account for simplicity.
gcloud run jobs deploy bank-generator-job \
    --image gcr.io/$PROJECT_ID/bank-generator \
    --region $REGION \
    --set-env-vars "PROJECT_ID=$PROJECT_ID,NUM_MESSAGES=1000" \
    --service-account="$PROJECT_NUMBER-compute@developer.gserviceaccount.com"
```

## 6. Execution

### Option A: Run Generator Only
Triggers the Cloud Run job to generate synthetic data.
```bash
gcloud run jobs execute bank-generator-job --region $REGION
```

### Option B: Run End-to-End Workflow
Deploys and runs the Cloud Workflow which triggers the Generator then the Data Pipeline.
```bash
gcloud workflows deploy bank-pipeline --source=workflow.yaml --location=$REGION
gcloud workflows run bank-pipeline --location=$REGION
```

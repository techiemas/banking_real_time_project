$PROJECT_ID = "jaffle-shop-481012"
$REGION = "us-central1"

Write-Host "Setting project to $PROJECT_ID..."
gcloud config set project $PROJECT_ID

Write-Host "Enabling APIs..."
gcloud services enable run.googleapis.com pubsub.googleapis.com sqladmin.googleapis.com bigquery.googleapis.com artifactregistry.googleapis.com dataproc.googleapis.com cloudbuild.googleapis.com

# BigQuery
Write-Host "Creating BigQuery Dataset..."
bq --location=$REGION mk -d --description "Banking Production Dataset" banking_prod
if ($LASTEXITCODE -ne 0) { Write-Host "Dataset might already exist, continuing..." }

Write-Host "Creating BigQuery Table..."
# Schema for raw table
@"
[
  { "name": "transaction_id", "type": "STRING", "mode": "REQUIRED" },
  { "name": "account_id", "type": "STRING", "mode": "REQUIRED" },
  { "name": "amount", "type": "FLOAT", "mode": "REQUIRED" },
  { "name": "transaction_type", "type": "STRING", "mode": "REQUIRED" },
  { "name": "timestamp", "type": "TIMESTAMP", "mode": "REQUIRED" },
  { "name": "data", "type": "STRING", "mode": "NULLABLE" }
]
"@ | Out-File schema.json -Encoding ASCII

bq mk --table banking_prod.banking_raw schema.json
if ($LASTEXITCODE -ne 0) { Write-Host "Table raw might already exist, continuing..." }

# Schema for Silver table (Cleaned)
@"
[
  { "name": "transaction_id", "type": "STRING", "mode": "REQUIRED" },
  { "name": "account_id", "type": "STRING", "mode": "REQUIRED" },
  { "name": "amount", "type": "FLOAT", "mode": "REQUIRED" },
  { "name": "transaction_type", "type": "STRING", "mode": "REQUIRED" },
  { "name": "timestamp", "type": "TIMESTAMP", "mode": "REQUIRED" }
]
"@ | Out-File schema_silver.json -Encoding ASCII

Write-Host "Creating Silver Table..."
bq mk --table banking_prod.banking_silver schema_silver.json
if ($LASTEXITCODE -ne 0) { Write-Host "Table silver might already exist, continuing..." }

# Schema for Gold Fact Table (Aggregated by Type)
@"
[
  { "name": "transaction_type", "type": "STRING", "mode": "REQUIRED" },
  { "name": "total_transactions", "type": "INTEGER", "mode": "REQUIRED" },
  { "name": "total_amount", "type": "FLOAT", "mode": "REQUIRED" }
]
"@ | Out-File schema_fact.json -Encoding ASCII

Write-Host "Recreating Gold Table (transactions_fact)..."
bq rm -f -t banking_prod.transactions_fact
bq mk --table banking_prod.transactions_fact schema_fact.json
if ($LASTEXITCODE -ne 0) { Write-Host "Error creating transactions_fact" }

# Schema for Gold table (Aggregated by Type + Hour)
@"
[
  { "name": "transaction_type", "type": "STRING", "mode": "REQUIRED" },
  { "name": "total_transactions", "type": "INTEGER", "mode": "REQUIRED" },
  { "name": "total_amount", "type": "FLOAT", "mode": "REQUIRED" },
  { "name": "hour_window", "type": "TIMESTAMP", "mode": "NULLABLE" }
]
"@ | Out-File schema_gold.json -Encoding ASCII

Write-Host "Creating Gold Table (banking_gold)..."
bq mk --table banking_prod.banking_gold schema_gold.json
if ($LASTEXITCODE -ne 0) { Write-Host "Table gold might already exist, continuing..." }

# Pub/Sub
Write-Host "Creating Pub/Sub Topic..."
gcloud pubsub topics create bank-transactions
if ($LASTEXITCODE -ne 0) { Write-Host "Topic might already exist..." }

Write-Host "Creating BigQuery Subscription..."
# Needs service account permission
$PROJECT_NUMBER = gcloud projects describe $PROJECT_ID --format="value(projectNumber)"
$PUBSUB_SA = "service-$PROJECT_NUMBER@gcp-sa-pubsub.iam.gserviceaccount.com"

gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$PUBSUB_SA" --role="roles/bigquery.dataEditor"

gcloud pubsub subscriptions create bank-transactions-bq-sub --topic=bank-transactions --bigquery-table="$PROJECT_ID.banking_prod.banking_raw" --use-topic-schema
if ($LASTEXITCODE -ne 0) { Write-Host "Subscription might already exist..." }

# Cloud Run Generator
Write-Host "Building Generator..."
cd generator
gcloud builds submit --tag gcr.io/$PROJECT_ID/bank-generator .
cd ..

Write-Host "Deploying Generator..."
gcloud run jobs deploy bank-generator-job --image gcr.io/$PROJECT_ID/bank-generator --region $REGION --set-env-vars "PROJECT_ID=$PROJECT_ID,NUM_MESSAGES=1000" --service-account "$PROJECT_NUMBER-compute@developer.gserviceaccount.com"

Write-Host "Setup Complete!"

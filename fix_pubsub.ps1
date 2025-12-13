$PROJECT_ID = "jaffle-shop-481012" # replace with your gcp project id

Write-Host "Correcting Pub/Sub Configuration..."

# Cleanup
gcloud pubsub subscriptions delete bank-transactions-bq-sub --quiet
gcloud pubsub topics delete bank-transactions --quiet

# Define Schema (AVRO) - Required for BigQuery mapping
$SchemaFile = "pubsub_schema.json"
@"
{
  "type": "record",
  "name": "Transaction",
  "fields": [
    {"name": "transaction_id", "type": "string"},
    {"name": "account_id", "type": "string"},
    {"name": "amount", "type": "float"},
    {"name": "transaction_type", "type": "string"},
    {"name": "timestamp", "type": "string"}
  ]
}
"@ | Out-File $SchemaFile -Encoding ASCII

# Create Schema
gcloud pubsub schemas create bank-transaction-schema --type=AVRO --definition-file=$SchemaFile
# If fails (exists), continue
if ($LASTEXITCODE -ne 0) { Write-Host "Schema might exist..." }

# Create Topic WITH Schema
gcloud pubsub topics create bank-transactions --schema=bank-transaction-schema --message-encoding=JSON

# Create Subscription (Push to BQ)
gcloud pubsub subscriptions create bank-transactions-bq-sub --topic=bank-transactions --bigquery-table="$PROJECT_ID.banking_prod.banking_raw" --use-topic-schema

Write-Host "Infrastructure Repaired. Re-run verify.ps1 to generate data."

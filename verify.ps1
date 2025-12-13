$PROJECT_ID = "jaffle-shop-481012"
$REGION = "us-central1"

Write-Host "Triggering Generator Job..."
gcloud run jobs execute bank-generator-job --region $REGION --wait

Write-Host "Submitting PySpark Job..."
cd pyspark
$BUCKET = "dataproc-temp234-$PROJECT_ID"
gsutil mb -l $REGION gs://$BUCKET
# Ignore if exists
if ($LASTEXITCODE -ne 0) { Write-Host "Bucket might exist..." }

# Upload script to GCS to avoid Windows path backslash issues
Write-Host "Uploading main.py to GCS..."
gsutil cp main.py gs://$BUCKET/main.py

Write-Host "Submitting Job..."
gcloud dataproc batches submit pyspark gs://$BUCKET/main.py --project=$PROJECT_ID --region=$REGION --batch="bank-tf-$(Get-Date -Format 'yyyyMMddHHmmss')" --deps-bucket="gs://$BUCKET" --version="1.1" --properties="spark.jars.packages=com.google.cloud.spark:spark-bigquery-with-dependencies_2.12:0.34.0"

Write-Host "Verification flow triggered. Check BigQuery Console for 'transactions_fact' and 'banking_gold' tables."

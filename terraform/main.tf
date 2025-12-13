# Enable APIs
resource "google_project_service" "apis" {
  for_each = toset([
    "run.googleapis.com",
    "pubsub.googleapis.com",
    "sqladmin.googleapis.com",
    "bigquery.googleapis.com",
    "iam.googleapis.com",
    "cloudbuild.googleapis.com", # For building containers
    "artifactregistry.googleapis.com",
    "dataproc.googleapis.com" # For PySpark
  ])
  service            = each.key
  disable_on_destroy = false
}

# --- Cloud SQL (Postgres) ---
resource "google_sql_database_instance" "bank_db_instance" {
  name             = "bank-db-instance-demo"
  database_version = "POSTGRES_14"
  region           = var.region
  deletion_protection = false # For demo ease

  settings {
    tier = "db-f1-micro"
    ip_configuration {
      ipv4_enabled = true # Use public IP for simplicity in demo
      authorized_networks {
        name  = "allow-all" # For demo only!
        value = "0.0.0.0/0"
      }
    }
  }
  depends_on = [google_project_service.apis]
}

resource "google_sql_database" "bank_db" {
  name     = "bank_db"
  instance = google_sql_database_instance.bank_db_instance.name
}

resource "google_sql_user" "users" {
  name     = "bank_user"
  instance = google_sql_database_instance.bank_db_instance.name
  password = "bank_password_123" # Hardcoded for demo simplicity
}

# --- BigQuery ---
resource "google_bigquery_dataset" "banking_prod" {
  dataset_id  = "banking_prod"
  description = "Banking Production Dataset"
  location    = var.region
  depends_on = [google_project_service.apis]
}

# Define the table for Pub/Sub BigQuery Subscription
resource "google_bigquery_table" "banking_raw" {
  dataset_id = google_bigquery_dataset.banking_prod.dataset_id
  table_id   = "banking_raw"
  
  # Schema must match the JSON payload and Pub/Sub schema
  schema = <<EOF
[
  {
    "name": "transaction_id",
    "type": "STRING",
    "mode": "REQUIRED"
  },
  {
    "name": "account_id",
    "type": "STRING",
    "mode": "REQUIRED"
  },
  {
    "name": "amount",
    "type": "FLOAT",
    "mode": "REQUIRED"
  },
  {
    "name": "transaction_type",
    "type": "STRING",
    "mode": "REQUIRED"
  },
  {
    "name": "timestamp",
    "type": "TIMESTAMP",
    "mode": "REQUIRED"
  },
  {
    "name": "data",
    "type": "STRING",
    "mode": "NULLABLE" 
  }
]
EOF
}

# --- Pub/Sub ---
resource "google_pubsub_schema" "bank_schema" {
  name = "bank-transaction-schema"
  type = "AVRO"
  definition = <<EOF
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
EOF
  depends_on = [google_project_service.apis]
}

resource "google_pubsub_topic" "bank_events" {
  name = "bank-transactions"
  
  schema_settings {
    schema = "projects/${var.project_id}/schemas/${google_pubsub_schema.bank_schema.name}"
    encoding = "JSON"
  }
  depends_on = [google_pubsub_schema.bank_schema]
}

# BigQuery Subscription (Push to Table)
resource "google_pubsub_subscription" "bq_sub" {
  name  = "bank-transactions-bq-sub"
  topic = google_pubsub_topic.bank_events.name

  bigquery_config {
    table = "${var.project_id}.${google_bigquery_dataset.banking_prod.dataset_id}.${google_bigquery_table.banking_raw.table_id}"
    use_topic_schema = true
  }

  depends_on = [google_bigquery_table.banking_raw, google_project_service.apis]
}

# --- IAM for Pub/Sub -> BigQuery ---
# The Pub/Sub service account needs permission to write to BigQuery
resource "google_project_iam_member" "pubsub_bq_writer" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
  depends_on = [google_project_service.apis]
}

data "google_project" "project" {}

# --- Artifact Registry for Containers ---
resource "google_artifact_registry_repository" "repo" {
  location      = var.region
  repository_id = "bank-repo"
  format        = "DOCKER"
  depends_on    = [google_project_service.apis]
}

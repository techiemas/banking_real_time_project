# GCP Serverless Banking Pipeline (Medallion Architecture)

This project deploys a real-time banking data pipeline on Google Cloud Platform using a **Medallion Architecture** (Bronze -> Silver -> Gold).

## Architecture
1.  **Source**: Python Generator (Cloud Run Job) -> Pub/Sub (`bank-transactions`).
2.  **Bronze (Ingestion)**: Pub/Sub BigQuery Subscription -> BigQuery (`banking_prod.banking_raw`).
3.  **Silver (Cleaning)**: PySpark (Dataproc Serverless) -> BigQuery (`banking_prod.banking_silver`).
    *   Deduplicates transactions.
    *   Filters invalid amounts.
    *   Converts timestamps.
4.  **Gold (Aggregation)**: PySpark (Dataproc Serverless) -> BigQuery.
    *   **transactions_fact**: Aggregated by Transaction Type.
    *   **banking_gold**: Aggregated by Transaction Type and Hour.

## GCP Services Used

| Service | Component | Why it was chosen | Where it is used |
| :--- | :--- | :--- | :--- |
| **Cloud SQL** | Operational Database (Source) | Represents the transactional ledger (OLTP) where banking operations effectively occur. | *Defined in Terraform*. Acts as the upstream source system (Note: The current demo generator mocks this by writing directly to Pub/Sub to save costs). |
| **Cloud Run (Jobs)** | Data Generator | Serverless, cost-effective for finite batch jobs (pay-per-use). | `bank-generator-job`: Runs the Python script to generate synthetic transactions. |
| **Pub/Sub** | Ingestion Layer | Decouples generation from storage; handles spikes in real-time data. | Topic: `bank-transactions`. Subscription pushes data directly to BigQuery. |
| **BigQuery** | Data Warehouse | Serverless, highly scalable, SQL-based analysis. | Dataset: `banking_prod`. Stores Raw, Silver, and Gold tables. |
| **Dataproc Serverless** | Transformation | Managed PySpark environment without cluster management overhead. Autoscaling. | Runs `pyspark/main.py` for Medallion transformations (Bronze -> Silver -> Gold). |
| **Cloud Workflows** | Orchestration | Lightweight, fully serverless orchestration for chaining GCP services. | `bank-pipeline`: Triggers Generator and then submits Dataproc job. |
| **Cloud Storage (GCS)** | Artifact Storage | Durable, low-cost object storage. | Bucket: Stores `main.py` script and temporary staging files for Spark-BigQuery connector. |
| **Cloud Build** | CI/CD | Fully managed build service. | Builds the Docker container for the Cloud Run Generator. |

## Other Tools

| Tool | Purpose | Why it is used |
| :--- | :--- | :--- |
| **Terraform** | Infrastructure as Code (IaC) | Automates the creation and management of GCP resources (Datasets, Topics, Permissions) in a reproducible, version-controlled way. (Note: `setup_infra.ps1` is provided for a lightweight alternative). |
| **PowerShell** | Scripting | Automation of setup and verification tasks for Windows users. | `setup_infra.ps1`, `verify.ps1`. |

## Prerequisites
*   Google Cloud SDK (`gcloud`) installed and authenticated.
*   Project ID set in `gcloud config set project <your-project-id>`.

## Deployment Steps

1.  **Run the deployment script (PowerShell):**
    ```powershell
    .\setup_infra.ps1
    ```
    This script will:
    *   Set the project ID and enable APIs.
    *   Create BigQuery Dataset and Tables (**Raw, Silver, Gold**).
    *   Create Pub/Sub resources.
    *   Build and Deploy the Generator Cloud Run Job.

2.  **Generate Data:**

    **Option A: Cloud Run (Serverless)**
    ```powershell
    .\verify.ps1
    ```

    **Option B: Local Python Script (No Cloud Run required)**
    If you prefer to run the generator from your laptop:
    ```powershell
    $env:PROJECT_ID="jaffle-shop-481012"
    python generator/main.py
    ```

## CI/CD (Continuous Deployment)

Yes, you can use **Google Cloud Build** to automate the deployment of this pipeline whenever you push code to GitHub.

A `cloudbuild.yaml` file is included in the project. It performs the following steps automatically:

1.  **Infrastructure**: runs `terraform apply` to ensure BigQuery tables and Pub/Sub topics are configured correctly.
2.  **Build**: Builds the Python Generator Docker image.
3.  **Push**: Pushes the image to Google Container Registry (GCR).
4.  **Deploy Generator**: Updates the Cloud Run Job.
5.  **Deploy Transformation**: Copies the latest `pyspark/main.py` code to the Cloud Storage bucket.
6.  **Deploy Workflow**: Deploys the updated `workflow.yaml` to Cloud Workflows.

### How to set it up:
1.  Connect your GitHub repository to **Google Cloud Build**.
2.  Create a **Trigger** processing the `cloudbuild.yaml` file on push to the `main` branch.
3.  Now, every `git push` will automatically update your entire pipeline in the cloud!

3.  **Run Verification (End-to-End):**
    This script triggers the PySpark Job (Medallion Transformation).
    ```powershell
    .\verify.ps1
    ```
    *(Note: verify.ps1 will also try to trigger the Cloud Run job, but that's fine even if you used Option B)*

4.  **Orchestration (Cloud Workflows):**
    To run the entire end-to-end pipeline (Generator -> Medallion Transformation) with a single command:
    ```powershell
    gcloud workflows run bank-pipeline --location=us-central1
    ```
    This triggers the Cloud Run generator and then submits the Dataproc Serverless job automatically.

5.  **Verify Dataproc Job Success:**
    Check that your Serverless Spark job completed successfully:
    ```powershell
    gcloud dataproc batches list --region us-central1 --limit 5
    ```
    *Look for STATE: SUCCEEDED*

6.  **Verify Results (BigQuery):**
    Use the `bq` command-line tool (do NOT run SQL directly in PowerShell):

    **Check Gold Layer (Aggregated Results - Hourly):**
    ```powershell
    bq query --use_legacy_sql=false "SELECT * FROM banking_prod.banking_gold ORDER BY hour_window DESC LIMIT 10"
    ```

    **Check Gold Layer (Aggregated Results - By Type):**
    ```powershell
    bq query --use_legacy_sql=false "SELECT * FROM banking_prod.transactions_fact"
    ```

    **Check Silver Layer (Cleaned Data):**
    ```powershell
    bq query --use_legacy_sql=false "SELECT count(*) as count FROM banking_prod.banking_silver"
    ```

## Advanced Patterns (CDC & Event-Driven)

**User Question**: *Can we trigger the Dataproc job automatically as soon as data arrives in the Raw table?*

**Answer**: Yes, there are two main ways to achieve this:

### 1. Event-Driven Batch (Near Real-Time)
You can use **Eventarc** to listen for specific events in BigQuery and trigger the workflow immediately.
*   **Mechanism**: Configure Eventarc to listen for `google.cloud.bigquery.v2.JobService.InsertJob` (data load event) on `banking_raw`.
*   **Target**: Eventarc triggers the **Cloud Workflow**.
*   **Pros**: Automated, runs only when data arrives.
*   **Cons**: Dataproc has a ~90s startup time. If data arrives continuously (streaming), you will trigger too many small jobs, which is inefficient and expensive. This is best for *file uploads* or *periodic dumps*.

### 2. Stream Processing (True Real-Time)
For continuous data like this Banking Pipeline, the best "CDC" approach is **Spark Structured Streaming**.
*   **Mechanism**: Dataproc runs a **continuous, 24/7 job**.
*   **Source**: It reads directly from **Pub/Sub** (not BigQuery Raw).
*   **Action**: It processes (cleans/aggregates) in real-time.
*   **Sink**: Writes directly to `banking_silver` and `banking_gold`.
*   **Pros**: extremely low latency (<1s).
*   **Cons**: Higher cost (cluster runs 24/7).

*Current Setup (Micro-Batch)*: We use Cloud Workflows to run efficiently on demand. To automate this, you would typically add a **Cloud Scheduler** trigger to verify data availability every X minutes.

## Recommendations for Enterprise Production

To take this project from a "Concept Demo" to a "Real-World Enterprise Pipeline", consider adding:

### 1. Switch Gold Layer to dbt (ELT vs ETL)
In modern data engineering, we prefer **ELT** (Extract, Load, Transform).
*   **Current Service**: PySpark writes Gold tables.
*   **Real-World**: PySpark handles heavy cleaning (Silver), but **dbt** (Data Build Tool) handles the Gold aggregations using SQL. It creates documentation, lineage, and testing out-of-the-box.

### 2. Data Quality & Observability
*   **Great Expectations**: Add a step before the Silver write to validate schema (e.g., "amount must be > 0", "id must not be null").
*   **Data Observability**: Tools like Monte Carlo or basic **Cloud Monitoring** alerts to ping you if data volume drops or "null" counts spike.

### 3. Data Governance (PII)
*   **Policy Tags**: Tag `account_id` as "Sensitive" in BigQuery.
*   **Column-Level Security**: Ensure only authorized groups can unmask PII.

### 4. Backfilling Strategy
*   Real pipelines often need to re-process historical data. Your workflow should accept a `date_range` parameter to process specific past days without duplicating data.

## 🚀 How to Clone & Run (For New Users)

If you are cloning this repository to your own GCP environment, follow these steps:

### 1. GCP Setup
1.  **Create a GCP Project** (e.g., `my-bank-project`).
2.  **Enable Billing** for that project.
3.  **Install Google Cloud SDK** locally and run:
    ```bash
    gcloud auth login
    gcloud config set project my-bank-project
    ```

### 2. Code Changes (Update Project ID)
The project ID `jaffle-shop-481012` and bucket names are currently hardcoded. You must **Find & Replace** them with your own:

| File | Change Required |
| :--- | :--- |
| `setup_infra.ps1` | Update `$PROJECT_ID` variable at the top. |
| `pyspark/main.py` | Update default `project_id` and bucket names (or pass as args). |
| `workflow.yaml` | Update `project_id` and `bucket` variables in the `init` step. |
| `verify.ps1` | Update `$PROJECT_ID` and `$BUCKET` variables. |
| `cloudbuild.yaml` | (Optional) Update `_PROJECT_NUMBER` substitution if using CI/CD. |

### 3. Run Setup
Once updated, simply run:
```powershell
.\setup_infra.ps1
```
This will automatically enable all APIs, create your BigQuery tables, Pub/Sub topics, and deploy the generator.

## 📂 Project Structure

```text
bank-pipeline/
├── generator/                 # Cloud Run Job (Python) for synthetic data
│   ├── main.py                # Transaction generation logic
│   ├── Dockerfile             # Container definition
│   └── requirements.txt       # Python dependencies
├── pyspark/                   # Dataproc Serverless (PySpark) transformations
│   └── main.py                # Medallion Architecture logic (Bronze->Silver->Gold)
├── terraform/                 # Infrastructure as Code (Production)
│   ├── main.tf                # Resource definitions (BigQuery, Pub/Sub, etc.)
│   ├── variables.tf           # Terraform variables
│   └── provider.tf            # GCP Provider config
├── cloudbuild.yaml            # CI/CD Pipeline configuration
├── workflow.yaml              # Cloud Workflows orchestration definition
├── setup_infra.ps1            # Quick setup script for Windows
├── verify.ps1                 # Verification and testing script
├── CHANGELOG.md               # Project history and versioning
└── README.md                  # Project documentation
```
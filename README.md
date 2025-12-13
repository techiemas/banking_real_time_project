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
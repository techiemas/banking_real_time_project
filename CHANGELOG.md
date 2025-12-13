# Changelog

All notable changes to the GCP Serverless Banking Pipeline project will be documented in this file.

## [Unreleased]

## [1.0.0] - 2025-12-13

### Added
- **Medallion Architecture**: Implemented full Bronze -> Silver -> Gold data flow.
    - **Bronze**: Raw ingestion from Pub/Sub to `banking_prod.banking_raw`.
    - **Silver**: Deduplication and cleaning logic in PySpark, writing to `banking_prod.banking_silver`.
    - **Gold**: Dual-table aggregation strategy:
        - `transactions_fact`: Aggregated metrics by Transaction Type.
        - `banking_gold`: Aggregated metrics by Transaction Type and Hour.
- **Orchestration**:
    - **Cloud Workflows**: Added `workflow.yaml` to orchestrate end-to-end execution.
    - Automated trigger of Cloud Run Generator followed by Dataproc Serverless Batch.
- **CI/CD**:
    - **Cloud Build**: Added `cloudbuild.yaml` for automated deployment.
    - Pipeline includes: Terraform infrastructure update, Docker build/push, Cloud Run deploy, PySpark code upload, and Workflow deployment.
- **Documentation**:
    - Updated `README.md` with Architecture diagrams, GCP Service descriptions, and Terraform/CI/CD details.
    - Added `walkthrough.md` with step-by-step verification instructions.

### Changed
- **PySpark Logic**: Refactored `pyspark/main.py` to support the new `transactions_fact` aggregation and generic BigQuery writing efficiency.
- **Infrastructure**: Updated `setup_infra.ps1` to support all three layers of the Medallion architecture.
- **Generator**: Switched to Cloud Run Jobs for cost-effective batch data generation.

### Fixed
- **Schema Mismatch**: Resolved issue where `transactions_fact` was inconsistent with Silver schema by enforcing explicit Schema definitions.
- **Orchestration**: Replaced Vertex AI Pipelines with Cloud Workflows for a purely serverless and simpler experience.

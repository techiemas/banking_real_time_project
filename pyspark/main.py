from pyspark.sql import SparkSession
from pyspark.sql.functions import col, sum as _sum, count, to_timestamp

def run_transformation(spark, project_id):
    # Read from BigQuery (Raw Data)
    raw_table = f"{project_id}.banking_prod.banking_raw"
    print(f"Reading from {raw_table}...✅")
    
    df = spark.read \
        .format("bigquery") \
        .option("table", raw_table) \
        .load()

    # --- Bronze to Silver (Cleaning & Deduplication) ---
    print("Step 1: Processing Bronze (Raw) -> Silver (Cleaned)...")
    
    # Cast timestamp and clean data
    silver_df = df \
        .withColumn("timestamp", to_timestamp(col("timestamp"))) \
        .filter(col("amount") > 0) \
        .dropDuplicates(["transaction_id"])
    
    silver_table = f"{project_id}.banking_prod.banking_silver"
    print(f"Writing to {silver_table}...✅")
    
    silver_df.write \
        .format("bigquery") \
        .option("table", silver_table) \
        .option("temporaryGcsBucket", f"dataproc-temp-{project_id}") \
        .mode("overwrite") \
        .save()

    # --- Gold Layer: Fact Table (Aggregated by Type) ---
    print("Step 2a: Aggregating by Transaction Type (transactions_fact)...")
    
    summary_df = silver_df.groupBy("transaction_type") \
        .agg(
            count("*").alias("total_transactions"),
            _sum("amount").alias("total_amount")
        )
    
    summary_df.show()

    target_table = f"{project_id}.banking_prod.transactions_fact"
    print(f"Writing to {target_table}...")
    
    summary_df.write \
        .format("bigquery") \
        .option("table", target_table) \
        .option("temporaryGcsBucket", f"dataproc-temp-{project_id}") \
        .mode("overwrite") \
        .save()

    # --- Silver to Gold (Aggregation) ---
    print("Step 2: Processing Silver (Cleaned) -> Gold (Aggregated)...✅")
    
    # Aggregate by Transaction Type and Hourly Window
    from pyspark.sql.functions import window
    
    gold_df = silver_df.groupBy("transaction_type", window("timestamp", "1 hour").alias("hour_window")) \
        .agg(
            count("*").alias("total_transactions"),
            _sum("amount").alias("total_amount")
        )
    
    # Gold table needs flat structure or struct handling. Window returns a struct {start, end}.
    # Let's keep it simple and take window.start as the time reference
    gold_final_df = gold_df.select(
        col("transaction_type"),
        col("total_transactions"),
        col("total_amount"),
        col("hour_window.start").alias("hour_window")
    )

    gold_final_df.show()

    gold_table = f"{project_id}.banking_prod.banking_gold"
    print(f"Writing to {gold_table}...✅")
    
    gold_final_df.write \
        .format("bigquery") \
        .option("table", gold_table) \
        .option("temporaryGcsBucket", f"dataproc-temp-{project_id}") \
        .mode("overwrite") \
        .save()
    
    print("Medallion Pipeline transformation complete!✅✅")

if __name__ == "__main__":
    import sys
    
    if len(sys.argv) >= 2:
        project_id = sys.argv[1]
    else:
        print("No project ID argument provided, using default: jaffle-shop-481012")
        project_id = "jaffle-shop-481012"
    
    spark = SparkSession.builder \
        .appName("BankingTransformation") \
        .getOrCreate()
        
    run_transformation(spark, project_id)

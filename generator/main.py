import os
import time
import json
import random
import uuid
from datetime import datetime
from google.cloud import pubsub_v1
from faker import Faker

# Configuration
PROJECT_ID = os.environ.get("PROJECT_ID")
TOPIC_ID = "bank-transactions"

if not PROJECT_ID:
    raise ValueError("PROJECT_ID environment variable is required")

publisher = pubsub_v1.PublisherClient()
topic_path = publisher.topic_path(PROJECT_ID, TOPIC_ID)
fake = Faker()

def generate_transaction():
    """Generates a synthetic banking transaction."""
    transaction = {
        "transaction_id": str(uuid.uuid4()),
        "account_id": f"ACC-{random.randint(1000, 9999)}",
        "amount": round(random.uniform(10.0, 5000.0), 2),
        "transaction_type": random.choice(["DEPOSIT", "WITHDRAWAL", "PAYMENT", "TRANSFER"]),
        "timestamp": datetime.utcnow().isoformat()
    }
    return transaction

def publish_messages(num_messages=100, delay=1.0):
    """Publishes messages to Pub/Sub."""
    print(f"Starting to generate {num_messages} transactions to {topic_path}...")
    
    for i in range(num_messages):
        data = generate_transaction()
        # Message must be a bytestring
        data_str = json.dumps(data)
        data_bytes = data_str.encode("utf-8")

        try:
            publish_future = publisher.publish(topic_path, data=data_bytes)
            # Wait for publish to succeed
            publish_future.result()
            print(f"Published: {data}")
        except Exception as e:
            print(f"Error publishing: {e}")
        
        time.sleep(delay)

if __name__ == "__main__":
    # Get configuration from env
    NUM_MESSAGES = int(os.environ.get("NUM_MESSAGES", "50"))
    DELAY = float(os.environ.get("DELAY", "0.5")) # Seconds
    
    publish_messages(NUM_MESSAGES, DELAY)
    print("Done generating transactions.")

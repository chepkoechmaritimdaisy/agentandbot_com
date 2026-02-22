import urllib.request
import json
import time
import random

# Configuration
API_URL = "http://localhost:4000/api/comments"
SOURCES = ["Twitter", "YouTube", "Telegram", "Internal"]
AUTHORS = ["Alice", "Bob", "Charlie", "Agent-007", "ClawBot"]
MESSAGES = [
    "Great update on the governance module!",
    "I found a bug in the UMP parser.",
    "When is the next release?",
    "The agent connection is unstable.",
    "Monitoring system looks good.",
    "Hello world!",
    "Can we integrate with WhatsApp?",
    "Deployed successfully.",
    "Error 500 on /api/status",
    "Checking heartbeat..."
]

def send_comment(comment):
    try:
        data = json.dumps({"comment": comment}).encode('utf-8')
        req = urllib.request.Request(API_URL, data=data, headers={'Content-Type': 'application/json'})
        with urllib.request.urlopen(req) as response:
            print(f"[SENT] {comment['content']} (Status: {response.getcode()})")
    except Exception as e:
        print(f"[ERROR] Failed to send comment: {e}")

def main():
    print("Starting Comment Monitor Simulation...")
    print(f"Target: {API_URL}")

    while True:
        comment = {
            "author": random.choice(AUTHORS),
            "content": random.choice(MESSAGES),
            "source": random.choice(SOURCES),
            "timestamp": time.time()
        }

        send_comment(comment)

        # Wait for a random interval between 2 and 5 seconds
        time.sleep(random.uniform(2, 5))

if __name__ == "__main__":
    main()

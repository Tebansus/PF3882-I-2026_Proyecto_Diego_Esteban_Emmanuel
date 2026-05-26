import urllib.request
import time
import random
import threading
import sys
import argparse

def worker(thread_id, url, delay_min, delay_max):
    print(f"Thread {thread_id} starting...")
    while True:
        try:
            # Simulate a user browsing
            time.sleep(random.uniform(delay_min, delay_max))
            
            # Hit productpage
            req = urllib.request.Request(url)
            req.add_header('User-Agent', f'Bookinfo-LoadGenerator/1.0 Thread-{thread_id}')
            
            with urllib.request.urlopen(req, timeout=5) as response:
                status = response.getcode()
                if status != 200:
                    print(f"Thread {thread_id}: Unexpected status {status}")
        except Exception as e:
            pass # Keep it quiet to not flood logs, or print(f"Thread {thread_id}: Error - {e}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Bookinfo Load Generator")
    parser.add_argument("--url", default="http://localhost:30080/productpage", help="URL to hit")
    parser.add_argument("--threads", type=int, default=5, help="Number of concurrent threads")
    parser.add_argument("--delay-min", type=float, default=0.1, help="Minimum delay between requests")
    parser.add_argument("--delay-max", type=float, default=1.0, help="Maximum delay between requests")
    args = parser.parse_args()

    print(f"Starting load generator against {args.url} with {args.threads} threads.")
    print("Press Ctrl+C to stop.")
    
    threads = []
    for i in range(args.threads):
        t = threading.Thread(target=worker, args=(i, args.url, args.delay_min, args.delay_max), daemon=True)
        t.start()
        threads.append(t)
        
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nStopping load generator.")
        sys.exit(0)

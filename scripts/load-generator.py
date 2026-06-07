import urllib.request
import time
import random
import threading
import sys
import argparse
import os
import platform

def worker(thread_id, url, delay_min, delay_max, header_rate):
    print(f"Thread {thread_id} starting...")
    import urllib.parse
    import http.cookiejar
    parsed_url = urllib.parse.urlparse(url)
    login_url = f"{parsed_url.scheme}://{parsed_url.netloc}/login"
    cookie = None
    
    if header_rate > 0:
        data = urllib.parse.urlencode({'username': 'jason'}).encode('utf-8')
        while cookie is None:
            try:
                cj = http.cookiejar.CookieJar()
                opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
                req = urllib.request.Request(login_url, data=data)
                req.add_header('Referer', url)
                opener.open(req)
                for c in cj:
                    if c.name == 'session':
                        cookie = f"session={c.value}"
                        break
            except Exception as e:
                print(f"Thread {thread_id} Login error: {e}. Retrying in 2 seconds...", flush=True)
                time.sleep(2)

    while True:
        try:
            # Simulate a user browsing
            time.sleep(random.uniform(delay_min, delay_max))
            
            # Hit productpage
            req = urllib.request.Request(url)
            req.add_header('User-Agent', f'Bookinfo-LoadGenerator/1.0 Thread-{thread_id}')
            
            if random.random() < header_rate and cookie:
                req.add_header('Cookie', cookie)
            
            with urllib.request.urlopen(req, timeout=5) as response:
                status = response.getcode()
                if status != 200:
                    print(f"Thread {thread_id}: Unexpected status {status}")
        except Exception as e:
            pass # Keep it quiet to not flood logs, or print(f"Thread {thread_id}: Error - {e}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Bookinfo Load Generator")
    parser.add_argument("--url", default="http://localhost:31080/productpage", help="URL to hit")
    parser.add_argument("--threads", type=int, default=None, help="Number of concurrent threads")
    parser.add_argument("--delay-min", type=float, default=0.1, help="Minimum delay between requests")
    parser.add_argument("--delay-max", type=float, default=1.0, help="Maximum delay between requests")
    parser.add_argument("--header-rate", type=float, default=0.2, help="Probability of adding 'end-user: jason' header (0.0 to 1.0)")
    args = parser.parse_args()
    args.url = args.url.strip()

    if args.threads is None:
        cpu_count = os.cpu_count() or 1
        if platform.system() == "Windows":
            args.threads = cpu_count
        else:
            args.threads = max(1, cpu_count // 3)

    print(f"Starting load generator against {args.url} with {args.threads} threads.")
    print("Press Ctrl+C to stop.")
    
    threads = []
    for i in range(args.threads):
        t = threading.Thread(target=worker, args=(i, args.url, args.delay_min, args.delay_max, args.header_rate), daemon=True)
        t.start()
        threads.append(t)
        
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nStopping load generator.")
        sys.exit(0)

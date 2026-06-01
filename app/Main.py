import time
import random
from flask import Flask, jsonify
from prometheus_client import make_wsgi_app, Counter, Histogram
from werkzeug.middleware.dispatcher import DispatcherMiddleware

app = Flask(__name__)

# Define custom Prometheus metrics
REQUEST_COUNT = Counter(
    'app_requests_total', 
    'Total number of application requests', 
    ['method', 'endpoint', 'http_status']
)
REQUEST_LATENCY = Histogram(
    'app_request_latency_seconds', 
    'Application request latency in seconds', 
    ['endpoint']
)

@app.route('/')
def home():
    start_time = time.time()
    
    # Simulate varying latency
    sleep_time = random.uniform(0.1, 0.5)
    time.sleep(sleep_time)
    
    # Track metrics
    REQUEST_COUNT.labels(method='GET', endpoint='/', http_status='200').inc()
    REQUEST_LATENCY.labels(endpoint='/').observe(time.time() - start_time)
    
    return jsonify(status="success", message="Welcome to the secure app!")

@app.route('/error')
def error():
    # Simulate a 500 error
    REQUEST_COUNT.labels(method='GET', endpoint='/error', http_status='500').inc()
    return jsonify(status="error", message="Something went wrong!"), 500

# Add prometheus wsgi middleware to route /metrics requests
app.wsgi_app = DispatcherMiddleware(app.wsgi_app, {
    '/metrics': make_wsgi_app()
})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
"""
OIB Demo Application with PostgreSQL and Redis
Demonstrates distributed tracing across multiple services
"""

import os
import time
import json
import random
import logging
from functools import wraps

from flask import Flask, jsonify, request
import redis
import psycopg2
from psycopg2.extras import RealDictCursor

# OpenTelemetry imports
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.redis import RedisInstrumentor
from opentelemetry.instrumentation.psycopg2 import Psycopg2Instrumentor

# Prometheus metrics
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Environment configuration
SERVICE_NAME = os.getenv("OTEL_SERVICE_NAME", "oib-demo-app")
OTLP_ENDPOINT = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "oib-alloy-telemetry:4317")

POSTGRES_HOST = os.getenv("POSTGRES_HOST", "oib-postgres")
POSTGRES_PORT = os.getenv("POSTGRES_PORT", "5432")
POSTGRES_USER = os.getenv("POSTGRES_USER", "oib")
POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD", "oib_secret")
POSTGRES_DB = os.getenv("POSTGRES_DB", "oib_demo")

REDIS_HOST = os.getenv("REDIS_HOST", "oib-redis")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))

# Setup OpenTelemetry tracing
resource = Resource.create({"service.name": SERVICE_NAME, "service.version": "1.0.0"})
provider = TracerProvider(resource=resource)
otlp_exporter = OTLPSpanExporter(endpoint=OTLP_ENDPOINT, insecure=True)
provider.add_span_processor(BatchSpanProcessor(otlp_exporter))
trace.set_tracer_provider(provider)
tracer = trace.get_tracer(__name__)

# Instrument libraries
Psycopg2Instrumentor().instrument()
RedisInstrumentor().instrument()

# Prometheus metrics
REQUEST_COUNT = Counter('app_requests_total', 'Total requests', ['method', 'endpoint', 'status'])
REQUEST_LATENCY = Histogram('app_request_latency_seconds', 'Request latency', ['method', 'endpoint'])
DB_QUERY_COUNT = Counter('app_db_queries_total', 'Database queries', ['operation'])
CACHE_OPS = Counter('app_cache_operations_total', 'Cache operations', ['operation', 'result'])

# Initialize Flask
app = Flask(__name__)
FlaskInstrumentor().instrument_app(app)

# Database connection pool
def get_db_connection():
    """Get a database connection with retry logic."""
    for attempt in range(3):
        try:
            conn = psycopg2.connect(
                host=POSTGRES_HOST,
                port=POSTGRES_PORT,
                user=POSTGRES_USER,
                password=POSTGRES_PASSWORD,
                dbname=POSTGRES_DB,
                cursor_factory=RealDictCursor
            )
            return conn
        except psycopg2.OperationalError as e:
            logger.warning(f"Database connection attempt {attempt + 1} failed: {e}")
            time.sleep(1)
    raise Exception("Could not connect to database after 3 attempts")

# Redis connection
def get_redis_client():
    """Get a Redis client."""
    return redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)

# Cache decorator
def cached(ttl=60, prefix="cache"):
    """Cache decorator using Redis."""
    def decorator(f):
        @wraps(f)
        def wrapper(*args, **kwargs):
            cache_key = f"{prefix}:{f.__name__}:{hash(str(args) + str(kwargs))}"
            
            with tracer.start_as_current_span("cache_lookup") as span:
                span.set_attribute("cache.key", cache_key)
                
                try:
                    r = get_redis_client()
                    cached_value = r.get(cache_key)
                    
                    if cached_value:
                        span.set_attribute("cache.hit", True)
                        CACHE_OPS.labels(operation="get", result="hit").inc()
                        logger.info(f"Cache hit for {cache_key}")
                        return json.loads(cached_value)
                    
                    span.set_attribute("cache.hit", False)
                    CACHE_OPS.labels(operation="get", result="miss").inc()
                    logger.info(f"Cache miss for {cache_key}")
                    
                except redis.RedisError as e:
                    logger.warning(f"Redis error: {e}")
                    span.set_attribute("cache.error", str(e))
            
            # Execute function
            result = f(*args, **kwargs)
            
            # Store in cache
            with tracer.start_as_current_span("cache_store") as span:
                span.set_attribute("cache.key", cache_key)
                span.set_attribute("cache.ttl", ttl)
                try:
                    r = get_redis_client()
                    r.setex(cache_key, ttl, json.dumps(result))
                    CACHE_OPS.labels(operation="set", result="success").inc()
                except redis.RedisError as e:
                    logger.warning(f"Redis store error: {e}")
                    CACHE_OPS.labels(operation="set", result="error").inc()
            
            return result
        return wrapper
    return decorator


# ============ API Endpoints ============

@app.route("/")
def index():
    """Homepage with API documentation."""
    return jsonify({
        "service": SERVICE_NAME,
        "version": "1.0.0",
        "endpoints": {
            "/health": "Health check",
            "/users": "List all users",
            "/users/<id>": "Get user by ID",
            "/items": "List all items (cached)",
            "/items/<id>": "Get item by ID",
            "/orders": "Create order (POST) or list orders (GET)",
            "/slow": "Simulated slow endpoint",
            "/error": "Simulated error endpoint",
            "/metrics": "Prometheus metrics"
        }
    })


@app.route("/health")
def health():
    """Health check with dependency status."""
    with tracer.start_as_current_span("health_check") as span:
        status = {"status": "healthy", "checks": {}}
        
        # Check PostgreSQL
        with tracer.start_as_current_span("check_postgres"):
            try:
                conn = get_db_connection()
                cur = conn.cursor()
                cur.execute("SELECT 1")
                cur.close()
                conn.close()
                status["checks"]["postgres"] = "healthy"
            except Exception as e:
                status["checks"]["postgres"] = f"unhealthy: {e}"
                status["status"] = "degraded"
        
        # Check Redis
        with tracer.start_as_current_span("check_redis"):
            try:
                r = get_redis_client()
                r.ping()
                status["checks"]["redis"] = "healthy"
            except Exception as e:
                status["checks"]["redis"] = f"unhealthy: {e}"
                status["status"] = "degraded"
        
        span.set_attribute("health.status", status["status"])
        return jsonify(status), 200 if status["status"] == "healthy" else 503


@app.route("/users")
def list_users():
    """List all users from database."""
    with tracer.start_as_current_span("list_users") as span:
        DB_QUERY_COUNT.labels(operation="select").inc()
        
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("SELECT id, username, email, created_at FROM users ORDER BY id")
        users = cur.fetchall()
        cur.close()
        conn.close()
        
        span.set_attribute("users.count", len(users))
        
        # Convert datetime to string
        result = []
        for user in users:
            result.append({
                "id": user["id"],
                "username": user["username"],
                "email": user["email"],
                "created_at": str(user["created_at"])
            })
        
        return jsonify({"users": result, "count": len(result)})


@app.route("/users/<int:user_id>")
def get_user(user_id):
    """Get user by ID with their items."""
    with tracer.start_as_current_span("get_user") as span:
        span.set_attribute("user.id", user_id)
        
        conn = get_db_connection()
        cur = conn.cursor()
        
        # Get user
        DB_QUERY_COUNT.labels(operation="select").inc()
        cur.execute("SELECT id, username, email, created_at FROM users WHERE id = %s", (user_id,))
        user = cur.fetchone()
        
        if not user:
            cur.close()
            conn.close()
            return jsonify({"error": "User not found"}), 404
        
        # Get user's items
        DB_QUERY_COUNT.labels(operation="select").inc()
        cur.execute("SELECT id, name, description, price FROM items WHERE user_id = %s", (user_id,))
        items = cur.fetchall()
        
        cur.close()
        conn.close()
        
        span.set_attribute("user.items_count", len(items))
        
        return jsonify({
            "user": {
                "id": user["id"],
                "username": user["username"],
                "email": user["email"],
                "created_at": str(user["created_at"])
            },
            "items": [dict(item) for item in items]
        })


@app.route("/items")
@cached(ttl=30, prefix="items")
def list_items():
    """List all items (cached for 30 seconds)."""
    with tracer.start_as_current_span("list_items_db") as span:
        DB_QUERY_COUNT.labels(operation="select").inc()
        
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("""
            SELECT i.id, i.name, i.description, i.price, u.username as seller
            FROM items i
            JOIN users u ON i.user_id = u.id
            ORDER BY i.id
        """)
        items = cur.fetchall()
        cur.close()
        conn.close()
        
        span.set_attribute("items.count", len(items))
        
        result = []
        for item in items:
            result.append({
                "id": item["id"],
                "name": item["name"],
                "description": item["description"],
                "price": float(item["price"]) if item["price"] else 0,
                "seller": item["seller"]
            })
        
        return {"items": result, "count": len(result)}


@app.route("/items/<int:item_id>")
def get_item(item_id):
    """Get item by ID with view counter."""
    cache_key = f"item_views:{item_id}"
    
    with tracer.start_as_current_span("get_item") as span:
        span.set_attribute("item.id", item_id)
        
        # Increment view counter in Redis
        with tracer.start_as_current_span("increment_view_counter"):
            try:
                r = get_redis_client()
                views = r.incr(cache_key)
                CACHE_OPS.labels(operation="incr", result="success").inc()
            except redis.RedisError:
                views = 0
                CACHE_OPS.labels(operation="incr", result="error").inc()
        
        # Get item from database
        DB_QUERY_COUNT.labels(operation="select").inc()
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("""
            SELECT i.id, i.name, i.description, i.price, u.username as seller
            FROM items i
            JOIN users u ON i.user_id = u.id
            WHERE i.id = %s
        """, (item_id,))
        item = cur.fetchone()
        cur.close()
        conn.close()
        
        if not item:
            return jsonify({"error": "Item not found"}), 404
        
        span.set_attribute("item.views", views)
        
        return jsonify({
            "item": {
                "id": item["id"],
                "name": item["name"],
                "description": item["description"],
                "price": float(item["price"]) if item["price"] else 0,
                "seller": item["seller"],
                "views": views
            }
        })


@app.route("/orders", methods=["GET", "POST"])
def orders():
    """List orders or create a new order."""
    if request.method == "GET":
        return list_orders()
    else:
        return create_order()


def list_orders():
    """List all orders."""
    with tracer.start_as_current_span("list_orders") as span:
        DB_QUERY_COUNT.labels(operation="select").inc()
        
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("""
            SELECT o.id, o.total, o.status, o.created_at, u.username
            FROM orders o
            JOIN users u ON o.user_id = u.id
            ORDER BY o.created_at DESC
            LIMIT 50
        """)
        orders = cur.fetchall()
        cur.close()
        conn.close()
        
        span.set_attribute("orders.count", len(orders))
        
        result = []
        for order in orders:
            result.append({
                "id": order["id"],
                "total": float(order["total"]) if order["total"] else 0,
                "status": order["status"],
                "username": order["username"],
                "created_at": str(order["created_at"])
            })
        
        return jsonify({"orders": result, "count": len(result)})


def create_order():
    """Create a new order with items."""
    with tracer.start_as_current_span("create_order") as span:
        data = request.get_json() or {}
        user_id = data.get("user_id", random.randint(1, 3))
        item_ids = data.get("item_ids", [random.randint(1, 5) for _ in range(random.randint(1, 3))])
        
        span.set_attribute("order.user_id", user_id)
        span.set_attribute("order.items_count", len(item_ids))
        
        conn = get_db_connection()
        cur = conn.cursor()
        
        try:
            # Calculate total
            with tracer.start_as_current_span("calculate_total"):
                DB_QUERY_COUNT.labels(operation="select").inc()
                cur.execute("SELECT SUM(price) as total FROM items WHERE id = ANY(%s)", (item_ids,))
                result = cur.fetchone()
                total = float(result["total"]) if result["total"] else 0
            
            # Create order
            with tracer.start_as_current_span("insert_order"):
                DB_QUERY_COUNT.labels(operation="insert").inc()
                cur.execute(
                    "INSERT INTO orders (user_id, total, status) VALUES (%s, %s, 'pending') RETURNING id",
                    (user_id, total)
                )
                order_id = cur.fetchone()["id"]
            
            # Add order items
            with tracer.start_as_current_span("insert_order_items"):
                for item_id in item_ids:
                    DB_QUERY_COUNT.labels(operation="insert").inc()
                    cur.execute(
                        "INSERT INTO order_items (order_id, item_id) VALUES (%s, %s)",
                        (order_id, item_id)
                    )
            
            conn.commit()
            span.set_attribute("order.id", order_id)
            span.set_attribute("order.total", total)
            
            # Invalidate items cache
            with tracer.start_as_current_span("invalidate_cache"):
                try:
                    r = get_redis_client()
                    keys = r.keys("items:*")
                    if keys:
                        r.delete(*keys)
                    CACHE_OPS.labels(operation="delete", result="success").inc()
                except redis.RedisError:
                    CACHE_OPS.labels(operation="delete", result="error").inc()
            
            logger.info(f"Created order {order_id} with total {total}")
            
            return jsonify({
                "order": {
                    "id": order_id,
                    "user_id": user_id,
                    "total": total,
                    "status": "pending",
                    "items": item_ids
                }
            }), 201
            
        except Exception as e:
            conn.rollback()
            logger.error(f"Order creation failed: {e}")
            span.set_attribute("error", str(e))
            return jsonify({"error": str(e)}), 500
        finally:
            cur.close()
            conn.close()


@app.route("/slow")
def slow_endpoint():
    """Simulated slow endpoint with database and cache operations."""
    with tracer.start_as_current_span("slow_operation") as span:
        delay = random.uniform(0.3, 0.8)
        span.set_attribute("delay.seconds", delay)
        
        # Simulate some cache checks
        with tracer.start_as_current_span("slow_cache_check"):
            try:
                r = get_redis_client()
                r.get("slow:check")
                time.sleep(delay * 0.3)
            except redis.RedisError:
                pass
        
        # Simulate database query
        with tracer.start_as_current_span("slow_db_query"):
            DB_QUERY_COUNT.labels(operation="select").inc()
            conn = get_db_connection()
            cur = conn.cursor()
            cur.execute("SELECT pg_sleep(%s), COUNT(*) FROM items", (delay * 0.3,))
            cur.fetchone()
            cur.close()
            conn.close()
        
        # Additional processing time
        time.sleep(delay * 0.4)
        
        return jsonify({
            "message": "Slow operation completed",
            "delay_ms": int(delay * 1000)
        })


@app.route("/error")
def error_endpoint():
    """Simulated error endpoint."""
    with tracer.start_as_current_span("error_operation") as span:
        error_type = random.choice(["database", "cache", "validation", "internal"])
        span.set_attribute("error.type", error_type)
        
        if error_type == "database":
            try:
                conn = get_db_connection()
                cur = conn.cursor()
                cur.execute("SELECT * FROM nonexistent_table")
            except Exception as e:
                span.record_exception(e)
                return jsonify({"error": "Database error", "details": str(e)}), 500
        
        elif error_type == "cache":
            return jsonify({"error": "Cache connection failed"}), 503
        
        elif error_type == "validation":
            return jsonify({"error": "Validation failed", "field": "user_id"}), 400
        
        else:
            return jsonify({"error": "Internal server error"}), 500


@app.route("/metrics")
def metrics():
    """Prometheus metrics endpoint."""
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}


# Error handlers
@app.errorhandler(404)
def not_found(e):
    return jsonify({"error": "Not found"}), 404


@app.errorhandler(500)
def internal_error(e):
    return jsonify({"error": "Internal server error"}), 500


if __name__ == "__main__":
    logger.info(f"Starting {SERVICE_NAME}")
    logger.info(f"OTLP endpoint: {OTLP_ENDPOINT}")
    logger.info(f"PostgreSQL: {POSTGRES_HOST}:{POSTGRES_PORT}")
    logger.info(f"Redis: {REDIS_HOST}:{REDIS_PORT}")
    app.run(host="0.0.0.0", port=5000, debug=False)

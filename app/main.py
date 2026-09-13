"""Demo service for the observability lab.

A small FastAPI app that is deliberately easy to observe. It exposes
Prometheus metrics and endpoints that simulate work and failure.
Structured logging and tracing come later in the build.
"""

import logging
import os
import random
import time

from fastapi import FastAPI, Response
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    Counter,
    Histogram,
    generate_latest,
)
from starlette.requests import Request

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("demo-app")

app = FastAPI(title="demo-app", docs_url=None, redoc_url=None)

# Metric labels use the route template, not the raw path. Raw paths
# would create a new label value per unique URL and blow up cardinality.
REQUESTS = Counter(
    "app_requests_total",
    "HTTP requests handled, by route, method and status code.",
    ["route", "method", "status"],
)
LATENCY = Histogram(
    "app_request_duration_seconds",
    "Request duration in seconds, by route and method.",
    ["route", "method"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5),
)


@app.middleware("http")
async def measure(request: Request, call_next):
    start = time.perf_counter()
    response = await call_next(request)
    route = request.scope.get("route")
    template = route.path if route else "unmatched"
    if template not in ("/metrics", "/health", "/ready"):
        elapsed = time.perf_counter() - start
        REQUESTS.labels(template, request.method, response.status_code).inc()
        LATENCY.labels(template, request.method).observe(elapsed)
    return response


@app.get("/")
def index():
    return {"service": "demo-app", "endpoints": ["/work", "/flaky", "/health", "/ready", "/metrics"]}


@app.get("/work")
def work():
    """Simulated work with variable latency."""
    time.sleep(random.uniform(0.01, 0.05))
    time.sleep(random.uniform(0.02, 0.2))
    log.info("work done")
    return {"status": "done"}


@app.get("/flaky")
def flaky():
    """Fails around 30% of the time. Exists so the error-rate alert
    and the error panels have something real to show during testing."""
    if random.random() < 0.3:
        log.error("flaky endpoint failed")
        return Response(content='{"status": "error"}', status_code=500, media_type="application/json")
    log.info("flaky endpoint succeeded")
    return {"status": "ok"}


@app.get("/health")
def health():
    """Liveness. Process is up and the event loop is serving requests."""
    return {"status": "alive"}


@app.get("/ready")
def ready():
    """Readiness. This app has no downstream dependencies, so readiness
    equals liveness here. Kept as a separate endpoint anyway, because the
    two probes answer different questions and merging them is a habit
    that hurts once a real dependency appears."""
    return {"status": "ready"}


@app.get("/metrics")
def metrics():
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", "8000")))

"""Demo service for the observability lab.

A small FastAPI app that is deliberately easy to observe. This first
version exposes Prometheus metrics and endpoints that simulate work
and failure. Structured logging and tracing come later in the build.
"""

import logging
import os
import random
import time

from fastapi import FastAPI, Response
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("demo-app")

app = FastAPI(title="demo-app", docs_url=None, redoc_url=None)


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

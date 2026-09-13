"""OpenTelemetry setup.

Tracing is opt-in. If OTEL_EXPORTER_OTLP_ENDPOINT is unset the app runs
exactly as before, with no exporter and no background threads. That
keeps plain local runs (docker run, pytest) free of a Tempo dependency.

Spans are exported over OTLP HTTP to whatever the endpoint points at,
in this lab that is the Tempo service inside the cluster.
"""

import logging
import os
from contextlib import contextmanager

log = logging.getLogger("demo-app.tracing")

_TRACER = None


def configure_tracing(app) -> None:
    global _TRACER
    endpoint = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT")
    if not endpoint:
        log.info("tracing disabled, OTEL_EXPORTER_OTLP_ENDPOINT not set")
        return
    from opentelemetry import trace
    from opentelemetry.exporter.otlp.proto.http.trace_exporter import (
        OTLPSpanExporter,
    )
    from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
    from opentelemetry.sdk.resources import Resource
    from opentelemetry.sdk.trace import TracerProvider
    from opentelemetry.sdk.trace.export import BatchSpanProcessor

    resource = Resource.create(
        {"service.name": os.environ.get("OTEL_SERVICE_NAME", "demo-app")}
    )
    provider = TracerProvider(resource=resource)
    provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
    trace.set_tracer_provider(provider)
    FastAPIInstrumentor.instrument_app(
        app, excluded_urls="health,ready,metrics"
    )
    _TRACER = trace.get_tracer("demo-app")
    log.info("tracing enabled, exporting to %s", endpoint)


@contextmanager
def span(name: str):
    """Open a child span, or do nothing when tracing is off. Lets the
    request handlers create inner spans without caring whether the SDK
    is configured."""
    if _TRACER is None:
        yield
        return
    with _TRACER.start_as_current_span(name):
        yield

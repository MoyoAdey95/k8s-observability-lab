"""JSON log formatting.

Hand-rolled formatter rather than a logging library dependency. The
format is small enough that owning it is simpler than configuring
someone else's, and it keeps the trace correlation logic visible.

Each line carries trace_id and span_id when a trace is active. Loki's
derived-fields config in Grafana picks trace_id out of the log line and
links it to the matching trace in Tempo.
"""

import json
import logging
import sys
import time


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        entry = {
            "ts": time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(record.created))
            + f".{int(record.msecs):03d}Z",
            "level": record.levelname.lower(),
            "logger": record.name,
            "message": record.getMessage(),
        }
        trace_id, span_id = _current_trace_ids()
        if trace_id:
            entry["trace_id"] = trace_id
            entry["span_id"] = span_id
        if record.exc_info:
            entry["exception"] = self.formatException(record.exc_info)
        return json.dumps(entry)


def _current_trace_ids():
    """Return (trace_id, span_id) as hex strings, or (None, None) when
    no trace is active or the OpenTelemetry SDK is not installed."""
    try:
        from opentelemetry import trace

        ctx = trace.get_current_span().get_span_context()
        if ctx.is_valid:
            return format(ctx.trace_id, "032x"), format(ctx.span_id, "016x")
    except ImportError:
        pass
    return None, None


def configure_logging() -> None:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(logging.INFO)
    # uvicorn installs its own handlers, replace them so access logs
    # come out as JSON too instead of a second plain-text stream
    for name in ("uvicorn", "uvicorn.access", "uvicorn.error"):
        logger = logging.getLogger(name)
        logger.handlers = []
        logger.propagate = True

# Architecture

One small service, observed three ways. The app is deliberately boring
so the pipelines around it are the interesting part.

```
                        ┌──────────────────────────────────────────┐
                        │            namespace: app                │
                        │  Deployment demo-app (2-5 replicas, HPA) │
                        │   /metrics   stdout JSON   OTLP spans    │
                        └──────┬───────────┬──────────────┬────────┘
                               │           │              │
             scrape (15s)      │           │ tailed by    │ pushed by app
             via ServiceMonitor│           │ promtail     │ (OTLP HTTP 4318)
                               ▼           ▼              ▼
                        ┌────────────┐ ┌────────┐  ┌────────────┐
namespace: monitoring   │ Prometheus │ │  Loki  │  │   Tempo    │
                        └──────┬─────┘ └────┬───┘  └─────┬──────┘
                               │            │            │
                               └──────┬─────┴────────────┘
                                      ▼
                                 ┌─────────┐      ┌──────────────┐
                                 │ Grafana │      │ Alertmanager │
                                 └─────────┘      └──────────────┘
```

## The three paths

**Metrics** are pull-based. The app exposes `/metrics` in Prometheus
format, a ServiceMonitor tells the Prometheus operator to scrape it
every 15 seconds through the Service's endpoints. Custom metrics are a
request counter and a latency histogram, labelled by route template
rather than raw path to keep cardinality bounded. Alert rules live in
a PrometheusRule manifest and are evaluated by Prometheus itself, with
Alertmanager handling grouping and (in production, not here) routing.

**Logs** are push-based. The app writes JSON lines to stdout, the kubelet 
writes those to a file on the node, and promtail (a DaemonSet, one
pod per node) tails the files and pushes to Loki with pod, namespace
and container labels attached. The app has no logging dependency
beyond stdout.

**Traces** are the only path the app actively participates in. The
OpenTelemetry SDK instruments FastAPI, request handlers add child
spans, and the SDK batches and exports spans over OTLP HTTP to Tempo.
Tracing turns on only when `OTEL_EXPORTER_OTLP_ENDPOINT` is set, so
the app runs unchanged where no Tempo exists.

## Correlation

The JSON log formatter includes `trace_id` when a trace is active.
Grafana's Loki datasource has a derived-field rule that extracts it
and renders a link to the matching Tempo trace, and the Tempo
datasource is configured for the reverse jump from span to log lines.
This is the practical payoff of running all three signals in one
place. A slow request found on the latency panel leads to its trace,
and the trace leads to its logs, no timestamp archaeology.

## Local and cloud

Everything above is identical on kind and on GKE. The kind cluster
(three nodes, so spreading and scale-out are visible) is where all
iteration happens, for free. The GKE cluster is Terraform-provisioned,
zonal with a spot node pool, exists for an evidence session and is
destroyed the same day. The kustomize overlays carry the only
differences, image source and one topology spread constraint for spot
reclaims.

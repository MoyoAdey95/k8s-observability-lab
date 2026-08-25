# k8s-observability-lab

A Kubernetes workload with the full observability stack built around
it as code. One FastAPI service, observed three ways. Metrics and
alerts (kube-prometheus-stack), logs (Loki), and traces (Tempo +
OpenTelemetry), with dashboards, alert rules and Helm values all
committed to this repo.

Personal lab, not client or production work. Metrics and log pipelines
are the part I run professionally. Distributed tracing is the layer I
added to expand my learning. Deployed, tested and maintained by me.

## Design

Development happens on a local kind cluster. Free and rebuildable in
minutes. The same manifests and values then get proven on a real GKE
cluster (zonal, spot nodes, Terraform-provisioned) which is destroyed
the same day. Evidence from that run lives in
[docs/evidence](docs/evidence/). The full picture is in
[docs/architecture.md](docs/architecture.md), and
[docs/production-deltas.md](docs/production-deltas.md) covers what
would change in production.

```
app (FastAPI)  ──/metrics──▶  Prometheus ──▶ Alertmanager
     │ stdout JSON ──promtail──▶  Loki           │
     │ OTLP ─────────────────▶  Tempo            ▼
     └──────────────── Grafana ◀── dashboards as code
```

## Run it locally

Prerequisites. Docker, kind, kubectl, helm, kustomize.

```bash
# cluster + metrics-server + namespaces
./clusters/kind/bootstrap.sh

# build the app image and load it into kind
docker build -t demo-app:dev app/
kind load docker-image demo-app:dev --name obs-lab

# deploy the app
kubectl apply -k k8s/overlays/local

# install the observability stack
./observability/install.sh

# look at it
kubectl -n monitoring port-forward svc/kps-grafana 3000:80
# http://localhost:3000, admin/admin, dashboard "demo-app"
```

Generate some traffic worth looking at:

```bash
kubectl -n app port-forward svc/demo-app 8080:80
while true; do curl -s localhost:8080/work >/dev/null; curl -s localhost:8080/flaky >/dev/null; done
```

`/work` produces traces with child spans and normal latency spread,
`/flaky` fails around 30% of the time so the error panels and the
error-rate alert have something real to show.

## What's in here

The app ([app/](app/)) exposes a request counter and latency histogram
labelled by route template, writes structured JSON logs to stdout with
`trace_id` included when a trace is active, and exports OTLP spans
when `OTEL_EXPORTER_OTLP_ENDPOINT` is set. The base manifests
([k8s/base](k8s/base/)) carry liveness and readiness probes, resource
requests and limits, a restrictive security context and an HPA.
Overlays differ only in image source and one spot-related scheduling
constraint. Dashboards and alert rules are files
([observability/dashboards](observability/dashboards/),
[observability/alerts](observability/alerts/)), so a fresh cluster
comes up with the same panels and the same three alerts every time.

## Cost

All iteration is local and free. The GKE phase uses a zonal cluster
(management fee inside the GKE free-tier credit) with two e2-small
spot nodes, which prices in cents per hour. `terraform destroy`
runs the same day. The project carries a budget alert regardless.

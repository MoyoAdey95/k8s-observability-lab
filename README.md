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

Bring up the cluster, metrics-server and namespaces.

```bash
./clusters/kind/bootstrap.sh
```

Build the app image and load it into kind. No registry involved, kind
reads the image straight from the local Docker daemon.

```bash
docker build -t demo-app:dev app/
kind load docker-image demo-app:dev --name obs-lab
```

Deploy the app, then the observability stack.

```bash
kubectl apply -k k8s/overlays/local
./observability/install.sh
```

Open Grafana on http://localhost:3000, admin/admin, dashboard
"demo-app".

```bash
kubectl -n monitoring port-forward svc/kps-grafana 3000:80
```

Generate some traffic worth looking at.

```bash
kubectl -n app port-forward svc/demo-app 8080:80
```

```bash
while true; do curl -s localhost:8080/work >/dev/null; curl -s localhost:8080/flaky >/dev/null; done
```

`/work` produces traces with child spans and normal latency spread,
`/flaky` fails around 30% of the time so the error panels and the
error-rate alert have something real to show. Half the traffic hitting
`/flaky` is what puts the dashboard error ratio near 15%.

## Following one request through all three signals

The point of running all three is that they answer different
questions, and the repo is wired so you can walk between them.

The dashboard shows p95 latency climbing. That tells you something is
slow. In Grafana, open Explore, pick the Tempo datasource
and run a TraceQL query for the slow ones.

```
{ duration > 200ms }
```

Open a trace and the child spans show where the time went. On the
captured run a 163ms `/work` request split into 25ms of `lookup` and
134ms of `compute`, which is the answer the histogram cannot give you.

Going the other way, the app writes JSON logs with `trace_id` and
`span_id` when a trace is active. Grafana's Loki datasource is
configured with a derived field that turns that `trace_id` into a link
straight to the trace, so a log line you found by searching becomes a
trace with one click.

## Run it on GKE

Prerequisites. Terraform, gcloud, and the `gke-gcloud-auth-plugin`
component, which kubectl needs to authenticate against GKE and which
gcloud does not install by default.

```bash
gcloud components install gke-gcloud-auth-plugin
```

Provision the cluster. It is zonal with a spot node pool, sized to be
cheap rather than resilient.

```bash
cd clusters/gke
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
```

Point kubectl at it using the command Terraform prints as the
`get_credentials` output.

Build and push the image. The `--platform` flag is not optional on an
arm64 machine. GKE's e2 nodes are amd64, and an image built without it
starts and dies immediately with `exec format error`.

```bash
docker build --platform linux/amd64 -t <region>-docker.pkg.dev/<project>/<repo>/demo-app:v1 app/
docker push <region>-docker.pkg.dev/<project>/<repo>/demo-app:v1
```

Set that image in `k8s/overlays/gke/kustomization.yaml`, then deploy
exactly as locally.

```bash
kubectl apply -k k8s/overlays/gke
./observability/install.sh
```

### Teardown

Order matters here. Deleting a GKE cluster does not delete the
persistent disks its PVCs created, so Loki's disk survives
`terraform destroy` and keeps billing quietly. Delete the PVCs while
the cluster is still alive and the CSI driver releases the disks with
them.

```bash
kubectl delete pvc --all -n monitoring
```

```bash
cd clusters/gke
terraform destroy
```

Then confirm nothing was left behind.

```bash
gcloud compute disks list
```

That should return nothing. Run all of this the same day you created
the cluster.

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

All iteration is local and free. The GKE phase billed $0.05 in total,
all of it was Compute Engine for two e2-medium spot nodes running a
few hours. The cluster management fee came to $0.08 and was covered
in full by the GKE free-tier credit, while networking was covered the
same way, so both show as zero. `terraform destroy` runs the same day
and the project carries a budget alert regardless.

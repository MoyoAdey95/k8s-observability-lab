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

## Run it with GitOps instead

The section above is the original flow, where someone runs
`kubectl apply -k` and `observability/install.sh`. The `gitops/`
directory is the same lab with Argo CD in front of it, so the cluster
follows this repository rather than following whoever last ran a
command.

Build the cluster and the image as above, then install Argo CD and
apply one manifest.

```bash
./gitops/install-argocd.sh
kubectl apply -f gitops/root-app.yaml
```

That manifest is a root Application pointing at `gitops/apps`, which
holds six more. The demo app, the four observability charts, and the
ServiceMonitor and alert rules. Nothing else is applied by hand. The
chart versions are pinned in those files.

Do not run `observability/install.sh` on a GitOps cluster. Argo CD
installs the stack from nothing, and letting Helm create the releases
first produces ownership conflicts that are tedious to unpick.

### Teardown, GitOps version

Delete the root Application first, and do it while Argo CD is still
running.

```bash
kubectl -n argocd delete app root
```

Every Application carries a deletion finalizer, so that one command
removes the six children and everything they manage. The command
blocks for a minute or two while the cascade runs. Finalizers need
Argo CD alive to be processed, so destroying the cluster with
Applications still present leaves deletes that never complete and
objects that have to be unstuck by hand.

Then confirm the cluster is empty and destroy it.

```bash
kubectl -n argocd get applications
kubectl -n monitoring get pvc
```

```bash
cd clusters/gke
terraform destroy
```

```bash
gcloud compute disks list
```

The PVC check is there to be read rather than acted on. In the
original flow, deleting PVCs by hand was a required step, because a
GKE cluster can be destroyed with persistent disks still attached to
nothing, and they keep billing afterwards. Deleting the root
Application turns out to cover it. The Loki chart sets
`enableStatefulSetAutoDeletePVC` on its single binary StatefulSet, so
removing the StatefulSet removes the PVC and the CSI driver releases
the disk.

The rule was never really about PVCs. Something has to delete the
StatefulSet while the cluster is still alive, because
`terraform destroy` takes the control plane away and no controller
ever processes the deletion. Deleting PVCs by hand was one way to
force that. The root Application is a better one, and it covers every
workload rather than the ones you remembered.

[gitops/README.md](gitops/README.md) covers why Argo CD is installed
with Helm rather than Terraform, how the multi-source Applications
keep a single copy of each values file, and what the sync waves are
for. [docs/gitops.md](docs/gitops.md) is what running it taught,
including a subchart that stayed enabled because Helm accepts keys
that do not exist, and why `helm list` cannot tell you what a GitOps
cluster is running.

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

All iteration is local and free. Two GKE runs have been billed.

| | 14 Sep 2026 | 12 Oct 2026 |
|---|---|---|
| Nodes | 2 x e2-medium spot | 2 x e2-standard-2 spot |
| Cluster lifetime | about 1h30 | 2h42 |
| Spot vCPU | $0.0663 | $0.2225 |
| Spot RAM | $0.0356 | $0.1195 |
| Balanced PD capacity | $0.0366 | $0.0633 |
| External IP on spot VM | $0.0115 | $0.0215 |
| Everything else | $0.0020 | $0.0028 |
| **Billed** | **$0.1520** | **$0.4296** |
| Zonal cluster management fee | $0.2528, fully credited | $0.4523, fully credited |

Both management fees were covered in full by the GKE free tier, which
allows one zonal cluster. Networking charges, mostly Network
Intelligence Center and Private Service Connect, were credited the
same way and show as zero.

The figures above come from the resource-level billing export in
BigQuery, net of credits. `docs/evidence/gitops/cost.txt` has the
queries. **An earlier version of this section said $0.05 and a $0.08
management fee for the September run.** Both were inaccurate, read off the
billing console on the day before usage had finished posting. The
export is the source now and the number does not move once a day has
settled.

The October run cost 2.8 times the September one. Disk and external IP charges
are per hour and both runs had the same two VMs and the same 110GB of disk, so
their 1.8x ratio is the difference in cluster lifetime. vCPU and RAM
rose 3.4x, which leaves about 1.9x per node-hour for e2-standard-2
over e2-medium. Moving up a node size to make room for Argo CD
therefore roughly doubled the hourly rate, and running an hour longer
did the rest.

`terraform destroy` runs the same day either way, and the project
carries a budget alert regardless.

# Production deltas

What separates this lab from a production deployment of the same
stack. The architecture would survive contact with production, most of
the sizing and storage decisions would not.

## Storage and durability

Loki and Tempo run single-binary with filesystem storage here. In
production both move to object storage (GCS in this ecosystem) and
Loki runs in its scalable read/write split so ingest and query scale
independently. Prometheus keeps 24 hours of data on an emptyDir-backed
volume in this lab. Production wants persistent volumes sized for the
retention policy, and long retention usually means Thanos or Mimir
rather than a bigger Prometheus disk.

Reclaim behaviour is worth knowing wherever this runs. Deleting the
GKE cluster left Loki's 10GB persistent disk behind, still billing,
because the disk belongs to the project rather than the cluster and
nothing cascaded the delete. The teardown in the README deletes the
PVCs first for that reason. In production the same property is a
feature. A cluster rebuild does not take the data with it, but it
means disk lifecycle is something you own deliberately rather than
something the cluster handles for you.

## Log shipping

Promtail does the shipping. Grafana has frozen Promtail feature
development in favour of Alloy, so a fresh production rollout today
starts with Alloy, which can also collect metrics and traces and would
replace both promtail and the app's direct OTLP export with a single
collection layer. Promtail is used in this lab because it does exactly
one job and its config fits on one screen.

## Access and auth

Grafana sits behind a port-forward with a static admin password.
Production puts it behind SSO, wires role-based access, and never
port-forwards. Alertmanager here has no receivers. Firing alerts are
visible in the UI and go nowhere. Production routes by severity to
paging and chat, with inhibition rules so a node alert does not page
for every pod on that node.

## Cluster

The GKE cluster is zonal with spot nodes and public node IPs,
optimised to cost nearly nothing for an afternoon. Production wants a
regional control plane, non-spot (or mixed) pools for stateful
workloads, private nodes behind Cloud NAT, workload identity for any
pod that touches GCP APIs, and network policies. None of that changes
the manifests in `k8s/base`, which is the argument for keeping base
and overlay separate.

Spot is not free of consequences even in a lab. A node was reclaimed
and replaced during the evidence run, which is captured in
`docs/evidence/gke/`. The workload survived it because the deployment
uses `whenUnsatisfiable: ScheduleAnyway` on its topology spread
constraint, so the scheduler placed both pods on the surviving node
rather than leaving one pending. On a production pool that constraint
would be worth tightening, but only alongside a pool that can actually
satisfy it.

## Sizing

Nodes were sized from the monitoring stack's memory requests, and CPU
turned out to be the binding constraint. Both e2-medium nodes settled
near 90% of allocatable CPU requests with nothing left unscheduled, so
the stack fits, but there is no room for the HPA to scale out. The
observability stack is the heavy tenant here, not the demo app.
Production sizes for the stack plus headroom, which puts this at
e2-standard-2 or larger, and usually splits monitoring onto its own
node pool so a busy workload cannot starve the thing watching it.

Added later: the GitOps extension puts Argo CD on the same cluster, and
its controller, repo-server, Redis and API server do not fit beside the
stack on e2-medium. The node pool moved to e2-standard-2 for that
reason, so this delta is no longer hypothetical.

## Sampling and cost

Every trace is kept here. At production traffic that gets expensive
fast, so head or tail sampling gets configured in the SDK or a
collector, and the sampling decision becomes a real engineering
choice. The metrics/logs sides have the same conversation, longer
scrape intervals for expensive targets, and retention tiers for logs.

## GitOps

The Applications in `gitops/` track the `main` branch, so every push is
a deployment. That is the point in a lab where the whole exercise is
watching a commit turn into a running change, and it is the first thing
you would change for production.

A real environment pins to a tag or an image digest and makes promotion
a conscious act, usually a separate directory or branch per
environment with a pull request between them. Tracking `main`
everywhere means a change lands in production the moment it merges,
with no gate and nowhere to stop it.

Argo CD polls Git every three minutes here. Production points a
repository webhook at the Argo CD server so a merge syncs in seconds.
Nothing webhooks a laptop, and the wait makes the mechanism visible
in `docs/evidence/gitops/sync-from-commit.txt`.

The cluster's Kubernetes version is not pinned. `clusters/gke`
takes the release channel default, which is how the rebuild came up on
1.36.4 where the original run was 1.35.7. Pinning means choosing
between a static version that reaches end of life and a channel that
moves on Google's schedule rather than on a commit, and it is the
same problem as an unpinned Helm chart one layer down.

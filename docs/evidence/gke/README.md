# GKE evidence

Captured from the zonal GKE cluster provisioned by
`clusters/gke`, two e2-medium spot nodes in europe-west1-b. Same
manifests, same Helm values, same dashboard JSON as the local kind
cluster. The cluster was created, evidenced and destroyed on the same
day.

**cluster-state.txt**

Nodes, workload and monitoring stack in one capture. Two things in it
are worth reading rather than skimming.

The node ages differ, 19 minutes against 10, and the internal IPs are
`10.132.0.6` and `10.132.0.7` where they were `.4` and `.5` twenty
minutes earlier. A spot node was reclaimed and replaced during the
session. Nothing was lost, the workload carried on, and the promtail
DaemonSet pod on the new node is 10 minutes old while its sibling is
13. That is the spot bargain working as intended rather than a fault.

Both demo-app pods sit on the same node. The deployment carries a
topology spread constraint, but with `whenUnsatisfiable: ScheduleAnyway`
it is a preference and not a requirement. The reclaim above is why it
was not met, the other node was being replaced at the moment the pods
were scheduled. A hard `DoNotSchedule` would have made the pods
unschedulable instead, which on spot nodes is the worse failure.

**dashboard-on-gke.png**

The dashboard from `observability/dashboards/`, unmodified, on the
managed cluster. Request rate by route, error ratio sitting around 15%
because the load generator hits `/flaky` half the time, p50 and p95
latency, replicas against HPA desired, container restarts, and the
Loki logs panel.

**log-line-trace-id-link.png**

A single JSON log line expanded, showing the `trace_id` and `span_id`
fields the formatter adds when a trace is active, and the Links
section Grafana builds from the derived field.

**trace-work-child-spans.png**

A `/work` request in Tempo. 163.23ms total, of which `lookup` took
25.25ms and `compute` took 134.5ms. The histogram says p95 is around
230ms, the trace says which span owns the time.

## Notes from the run

The image had to be rebuilt with `--platform linux/amd64`. My personal
laptop is arm64 and the nodes are amd64, so the first image started
and died immediately with `exec format error`. It had run fine on kind
because kind's nodes are containers on the same machine.

Nodes were sized from the stack's memory requests, and CPU turned out
to be the binding constraint. Both nodes sit near 90% of allocatable
CPU requests with nothing unscheduled, so it works, but there is no
headroom for the autoscaler to scale out here. On a longer-lived
cluster this would be e2-standard-2.

Loki's PVC bound to GKE's default storage class with no intervention,
which was the change most likely to be needed when moving off the
local-path provisioner kind uses.

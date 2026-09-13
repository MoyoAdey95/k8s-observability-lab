# Local evidence (kind)

Screenshots from the local kind cluster. Every alert in
`observability/alerts/demo-app-rules.yaml` was made to fire
deliberately before being committed. The GKE evidence in the parent
directory comes later and covers whether the same configuration works
on a managed cluster.

**alert-high-error-rate-firing.png**

A load generator running inside the cluster called `/work` and
`/flaky` once a second each. `/flaky` fails about 30% of the time by
design, so roughly 15% of all requests returned 5xx. The alert fired
at a measured ratio of 0.1268 against a 0.05 threshold, after holding
for its full 5 minute duration.

**alert-pod-restarting-firing.png**

Killing PID 1 inside a pod five times in a row, with 30 seconds
between each, produced four container restarts. The alert has no `for`
duration and fired as soon as the count crossed three. The measured
value is 3.15 rather than 4. Graphing the raw counter shows why. The
series for this pod starts at 1 rather than 0, because the first
scrape that recorded it had already caught one restart, so
`increase()` measured a delta of three across the window, and the
fraction above that is extrapolation to the window edges.
`increase()` reports what the window contains, not what actually
happened.

**alert-app-down-firing.png**

Scaling the deployment to zero. This is the case the `absent()` clause
exists for. With no pods, Prometheus has no `up{job="demo-app"}`
series at all, so a plain `sum(up{job="demo-app"}) == 0` would match
nothing and stay silent, and a total disappearance would go
unreported.

Worth noting in that last screenshot, the group header reads FIRING
(3). All three alerts are red at the same time because the error rate
and restart alerts were still firing off the tail of their own
evaluation windows while the app was already gone. Alerts persist for
as long as their window still contains the bad data.

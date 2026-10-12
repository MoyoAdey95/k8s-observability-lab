# GitOps evidence

Captured from the rebuilt GKE cluster, two e2-standard-2 spot nodes in
europe-west1-b, running Argo CD 3.5.5 from chart 10.10.3. The whole
observability stack and the demo app arrived through the Applications in
`gitops/`, and the only `kubectl apply` in the run was `root-app.yaml`.

**sync-from-commit.txt**

A threshold change going from a commit into the cluster on its own.

The alert expression in the cluster reads `> 3` before the commit and
`> 2` after it, and the Application's recorded revision moves from
`672338c` to `fd36184`. Nothing ran `kubectl apply` in between. That is
the claim the whole extension exists to demonstrate, so it is worth
being precise about the two halves of it.

The first half is that the cluster changed. The second half is that
Argo CD can say which commit put it in that state. The old flow could
do the first and not the second: `kubectl apply -k` leaves nothing
behind that answers "which version of this repo is running", which is
why `docs/evidence/gke/cluster-state.txt` from the original lab records
pods and services but cannot say what produced them.

Three minutes passed between the push and the sync. That is Argo CD's
default polling interval, not how long it takes to apply a rule. A
production setup points a repository webhook at the Argo CD server and
the same sync happens in seconds. The wait is in the capture because
removing it would have meant forcing a refresh by hand, and a forced
refresh proves something weaker.

What this file does not show is Prometheus loading the new rule. The
PrometheusRule object is where the GitOps boundary sits: Argo CD owns
getting the object into the cluster and the Prometheus operator owns
what happens next. That second step was already evidenced in the
original lab, in `docs/evidence/local/`, where the rule fired.

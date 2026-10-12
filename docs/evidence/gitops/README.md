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
do the first and not the second. `kubectl apply -k` leaves nothing
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
PrometheusRule object is where the GitOps boundary sits. Argo CD owns
getting the object into the cluster and the Prometheus operator owns
what happens next. That second step was already evidenced in the
original lab, in `docs/evidence/local/`, where the rule fired.

**self-heal-and-rollback.txt**

Three sequences, and the one that went wrong is the most useful.

The first was meant to show that Argo CD leaves `/spec/replicas` alone
because the Application ignores it. A manual scale to 4 held while the
Application still read `Synced`, which does show the drift was
suppressed. Then the deployment went back to 2 and for a moment it
looked like Argo CD had reasserted the manifest. The HPA had done it,
55 seconds after the scale, with the app under no load and
`minReplicas: 2`. The capture says so and says what follows from it,
which is that a cluster running both controllers cannot be used to
test either one in isolation. `RespectIgnoreDifferences` stays in the
Application on documented behaviour, not on evidence from this lab,
and the file is explicit about that rather than claiming a result it
did not measure.

The second changed an environment variable with an ordinary `kubectl
set env`. It was reverted in two seconds, and the ReplicaSet the
tamper created never finished rolling out. That gap against the
three-minute commit sync is the detail worth taking away. Argo CD
polls Git on a timer and watches the cluster, so hand edits are caught
far faster than commits are picked up. `initiatedBy` on the sync
operation reads `{"automated":true}` with no username attached.

The third is a rollback done the way this repo argues for, as
`git revert` rather than `argocd app rollback`. The CLI command refuses
to run while automated sync is on, and turning auto-sync off to use it
means the cluster stops following Git, which gives up the property the
whole setup is for. The history ends up with three commits, the change,
the revert and the reapply, and the cluster followed each one without
anybody applying anything.

**cluster-state.txt**

The counterpart to `docs/evidence/gke/cluster-state.txt` from the
original lab, and it answers the question that one could not.

`helm list -A` returns a single release, Argo CD itself. The four
charts behind the observability stack are absent, because Argo CD
renders charts with `helm template` and applies the output rather than
running `helm install`. No release, no Helm history, nothing in the
cluster that names a chart version.

That is worth dwelling on because the fix proposed for the original
lab's gap was to capture `helm list -A` next time. On this cluster that
capture holds none of the information it was meant to preserve. The
versions are in `gitops/apps/*.yaml` on dated commits instead, which
outlives the cluster rather than disappearing with it, but it is not
where the obvious command looks.

The node capture also records GKE moving from 1.35.7 to 1.36.4 between
the two runs, which nothing in the repository pinned. That one is
noted as outstanding rather than solved.

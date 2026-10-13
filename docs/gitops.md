# GitOps

What running the Argo CD extension taught, as distinct from how it is
put together. The design arguments and the bootstrap order live in
[gitops/README.md](../gitops/README.md), next to the files they
describe, and the captures are in
[docs/evidence/gitops/](evidence/gitops/).

## Helm will accept a key that does not exist

`gitops/values.yaml` switched off three Argo CD subcharts: dex,
notifications and the ApplicationSet controller. After the install,
two of the three pods were gone and the ApplicationSet controller was
running.

The values were not at fault. `helm get values argocd -n argocd`
showed `applicationSet.enabled: false` sitting in the release exactly
as written. Chart `argo-cd 10.10.3` simply has no such key. The
`applicationSet` block goes from `name` straight to `replicas`,
because ApplicationSet is a core component there with no on and off
switch, and the only lever is the replica count.

Helm raised nothing, because this chart ships no `values.schema.json`
and without one any key is as valid as any other. So a subchart you
believe you turned off stays on, the release looks exactly as intended
from the values side, and the only thing that reveals it is counting
pods.

The controller is left running. Two nodes of e2-standard-2 have the
headroom, and `replicas: 0` would be a deviation from the chart
defaults bought for nothing. The comment in `values.yaml` now records
what happened rather than what was intended.

## The chart versions are no longer in the cluster

The original lab installed the observability stack with
`observability/install.sh`, which pins nothing and records nothing.
Months later the repository could not say which Loki chart it had run.
The obvious remedy was to capture `helm list -A` on the next cluster.

On a GitOps cluster that capture returns one row, Argo CD itself.
Argo CD renders charts with `helm template` and applies the output, so
Loki, Tempo, promtail and kube-prometheus-stack exist as plain
Kubernetes objects with no release, no Helm secret and no history. The
command that was supposed to close the gap looks in a place where the
information is not.

What closed it instead is `targetRevision` on each chart source, which
Argo CD requires. The versions are in `gitops/apps/*.yaml`, on commits
with dates and authors, and they survive the cluster being deleted in
a way cluster state never does. The lesson is not that `helm list` is
useless, it is that the question "what version is running" belongs to
the repository rather than the cluster, and GitOps is what makes that
true.

The Loki question did get an answer, from the Helm
repository index rather than from anything this repository had kept.
Chart 7.3.0 was published on 10 August 2026 and remains the newest, so
the September run and the pinned version are the same chart.

## Drift in the cluster and drift in Git move at different speeds

Two changes, both reconciled by the same Argo CD, with very different
timings.

A commit changing an alert threshold took three minutes to reach the
cluster. A hand-made `kubectl set env` on the demo-app Deployment was
undone in two seconds, fast enough that the ReplicaSet it created
never finished rolling out.

Argo CD polls Git on an interval and watches cluster resources through
informers. Drift inside the cluster arrives as an event and is acted
on immediately. A new commit waits for the next poll, which is three
minutes by default. Pointing a repository webhook at the Argo CD
server closes most of that gap, and this lab does not.

It is worth knowing which number applies to which situation. "Argo CD
will fix it" is true in seconds for a hand edit and true in minutes
for a commit, and people conflate the two when reasoning about
incident response.

## Two controllers can both own the same field

`k8s/base/deployment.yaml` sets `replicas: 2` and `k8s/base/hpa.yaml`
scales between 2 and 5. Under `kubectl apply -k` this was harmless,
because nothing went back and reasserted the manifest once the HPA had
moved on. Under `selfHeal` it is a standing conflict. The HPA scales
out, Argo CD sees a cluster that does not match Git, and scales back
in.

The fix is `ignoreDifferences` on `/spec/replicas`, plus
`RespectIgnoreDifferences=true` in `syncOptions`. `ignoreDifferences`
alone only stops the Application reporting `OutOfSync`. The next sync
still applies the manifest as written, replicas included.

The usual advice is to delete `replicas` from the Deployment entirely
and let the HPA own the number. That is not done here because the
local overlay runs on kind with no metrics-server, so there is no HPA
on that path and the Deployment would come up with the Kubernetes
default of one pod.

The test showed the Application reporting `Synced` with four replicas
running against a manifest saying two, which is the diff suppression working.
It could not show what a sync would have done to the field, because the HPA
scaled the deployment back to its minimum before the question could be answered,
and no test that leaves both controllers running will separate them.
`RespectIgnoreDifferences` is set on documented behaviour, not on
evidence from this cluster.

## Rolling back means reverting a commit

`argocd app rollback` exists and is not used here. It refuses to run
while automated sync is enabled, which is reasonable. It would set the
cluster to a previous state that Git does not describe, and the next
reconcile would undo it. Turning auto-sync off to use the command
means the cluster has stopped following Git for the duration, which is
the one property the whole arrangement exists to provide.

`git revert` is the rollback. The threshold change was reverted,
the cluster went back to the old value on its own, and then the revert
was itself reverted so the repository ends on the value the evidence
supports. Three commits in the history, each with an author and a
timestamp, describing a change, a rollback, and a decision to go
forward again.

## What is still unpinned

The cluster came up on Kubernetes 1.36.4, where the original lab ran
1.35.7. `clusters/gke` takes the release channel default, so the control plane
and node version arrive from whenever `terraform apply` happens to run.

Pinning a GKE minor version means choosing between a static
version that goes end of life and a channel that moves on its own
schedule, and that trade is a decision rather than an oversight. It is
noted in [production-deltas.md](production-deltas.md) with the rest of
the things a real environment would do differently.

## The teardown rule was about the wrong object

The original lab learned that destroying a GKE cluster
leaves the persistent disks behind its PVCs billing away, and wrote
down a rule to delete the PVCs first. Going into this teardown I assumed
that rule held and would need adapting, because Argo CD owns the
StatefulSet and would recreate a PVC deleted underneath it.

What happened was that `kubectl -n argocd delete app root` took
everything with it. The PVC was already gone before the delete command
was run, the namespace was still Active so nothing had been removed
wholesale, and `gcloud compute disks list` showed only the two node
boot disks.

The Loki chart explains it. `singleBinary.persistence` defaults to
`enableStatefulSetAutoDeletePVC: true` with `whenDeleted: Delete`, so
the StatefulSet carries a retention policy that deletes its own PVC.
Nothing in this repository's values touches that, and the policy had
been there all along.

Which means the original lab's disk was never orphaned by a missing
step. It was orphaned because `terraform destroy` removes the control
plane, and a retention policy only fires when a controller processes a
StatefulSet deletion. There was no controller left to do it. Deleting
PVCs by hand worked as a remedy, but it was treating the symptom. The
actual requirement is that something delete the workloads while the
cluster is alive.

Deleting the root Application does that for everything in one command,
which is a better rule than a list of objects to remember. It is also
the one place where auto-sync has to be reckoned with in the right
order, because deletion finalizers need Argo CD running to be
processed. Argo CD has to outlive everything it manages and die last.

## A cost figure read on the day is an estimate

It was previously recorded that the September GKE run billed $0.05, with a $0.08
cluster management fee. Both numbers were inaccurate. The resource-level
billing export says $0.1520 billed and $0.2528 credited.

The figures were read off the billing console a few hours after
`terraform destroy`, when the day's usage had not finished posting.

The correction is not that $0.15 is expensive, but that a repository
making a cost claim should quote the settled figure, and the way to get
one is to wait a day and query the export rather than read a dashboard
while the usage is still landing. `docs/evidence/gitops/cost.txt` has
the queries and both runs side by side, so the next person can check
the arithmetic instead of trusting a sentence.

The comparison that export makes possible is worth more than either
number on its own. Disk and external IP charges are per hour and both
runs had identical hardware counts, so their ratio isolates cluster
lifetime. vCPU and RAM carry lifetime and node size together, so
dividing one out leaves the other. The node size change that made room
for Argo CD cost about 1.9x per node-hour. That is derived from this
repository's own billing data rather than from a pricing page.

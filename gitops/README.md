# GitOps

Argo CD and the Applications that describe everything this cluster
runs. Git is the source of truth. Nothing here is applied by hand once
the bootstrap is done.

## Why Argo CD is installed with Helm rather than Terraform

The repo already splits the two. Terraform builds the cluster in
`clusters/gke`, and Helm installs what runs inside it. Argo CD could
have gone into that same Terraform root using the helm provider, and
the reasons not to are worth being specific about.

Terraform resolves provider configuration during plan, before any
resource is created. A helm provider configured from the cluster's own
outputs therefore has nothing to point at on a first run against empty
state, so the plan either fails or quietly plans against whatever
credentials are lying around. The usual workarounds are running the
root twice or using targeted applies, both of which are worse than a
script that runs after the cluster exists.

Destroy has the mirror of that problem. The provider is still
configured against a cluster Terraform is in the middle of deleting.

There is also an ownership argument. Argo CD manages its own
resources from the moment it starts. Holding it in Terraform state
means two controllers believe they own the same objects, and the next
`terraform plan` reports drift that is not drift.

So Terraform owns the cluster, Helm installs Argo CD once, and Argo CD
owns everything after that.

## Bootstrap order

```
cd clusters/gke && terraform apply
gcloud container clusters get-credentials obs-lab --zone europe-west1-b --project moyo-cloud-lab
./gitops/install-argocd.sh
kubectl apply -f gitops/root-app.yaml
```

The last line is the only `kubectl apply` of a workload manifest in the
whole flow. Everything else arrives because Argo CD read it out of
Git.

## Do not run observability/install.sh on this cluster

That script is the version of this repo from before Argo CD, kept so
the two approaches can be compared. Running it first and letting Argo
CD adopt the releases afterwards produces ownership conflicts that are
tedious to unpick. On a GitOps cluster, Argo CD installs the stack from
nothing.

## How the Helm Applications are put together

Each of the four charts is an Application with two sources. The chart
comes from its upstream Helm repository and the values come from this
repo, joined by `ref: values` on the git source and `$values/` in the
value file path.

The alternative is copying the values inline into each Application,
which would fork them from the files `install.sh` reads and quietly
end the claim that kind and GKE run identical configuration. Two
sources keeps one copy of every values file.

`targetRevision` on a chart source is the chart version, and Argo CD
requires it. `install.sh` has no equivalent, so it installs whatever
is newest on the day it runs and does not record what that was.
When the GitOps work started I could not say from this repo which
Loki chart the original lab had used. The Helm index answers it after
the fact. 7.3.0 was published on 10 August 2026 and nothing newer has
shipped since, so the September run and this pin are the same chart.

That was luck rather than design. A release landing in between would
have changed the chart under an unchanged values file, with nothing
in the repo to show it had happened. Pinning turns a chart upgrade
into a commit somebody has to make, and the version is now written
down whether or not anyone goes looking for it.

## The root Application

`root-app.yaml` is an Application whose source is the `gitops/apps`
directory, so the thing it syncs is six more Applications. That is the
whole app-of-apps pattern. One manifest goes in by hand and everything
else is reachable from Git without another `kubectl apply`.

Ordering is the part that needs stating. `observability-config.yaml`
carries `argocd.argoproj.io/sync-wave: "1"` and the rest are wave 0 by
default. Argo CD waits for every wave 0 resource to go healthy before
it starts wave 1, and an Application counts as healthy once its own
sync has finished. So the ServiceMonitor and the PrometheusRule are
not applied until the kube-prometheus-stack Application has installed
the CRDs they need, and the demo-app Application has created the `app`
namespace they reference.

Without the wave, that sync fails on the first run and succeeds on the
retry, which works but logs an error nobody should have to learn to
ignore.


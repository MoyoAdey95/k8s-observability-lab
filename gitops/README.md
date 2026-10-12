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

# GitOps

## Critical gotchas

- **ArgoCD OutOfSync**: Manual `kubectl` changes cause drift - use `argocd app diff` to find divergence
- **Flux ImageUpdateAutomation not pushing**: Check Git write credentials in flux-system namespace
- **Helm "another operation in progress"**: Delete stuck secret `kubectl get secrets -n <ns> -l owner=helm,status=pending-upgrade`
- **Kustomize patch not applying**: Strategic merge patches must match exactly on name/kind/apiVersion in base
- **Never use `:latest` tags**: Use SHA or semver for reproducible deploys
- **Secrets never in Git**: Use Sealed Secrets, External Secrets Operator, or Vault

## Quick triage

```bash
argocd app list; argocd app get <app>       # ArgoCD status
flux get all                                 # Flux resources
helm list -A                                 # Helm releases
kubectl kustomize overlays/production        # Preview Kustomize
```

## ArgoCD

```bash
# Basic ops
argocd app sync <app>                        # Deploy
argocd app rollback <app> <revision>         # Rollback
argocd app set <app> --sync-policy none      # Emergency stop auto-sync

# Troubleshooting
argocd app get <app> --refresh; argocd app diff <app>  # OutOfSync diagnosis
argocd app get <app> -o yaml | grep -A20 conditions    # ComparisonError details
kubectl rollout status deployment/<name> -n <ns>       # "Progressing" forever - check rollout
```

## Flux CD

```bash
# Basic ops
flux reconcile kustomization <name> --with-source  # Force sync
flux suspend kustomization <name>                  # Stop auto-sync
flux resume kustomization <name>                   # Resume auto-sync

# Troubleshooting
flux get kustomizations; flux logs --kind=Kustomization --name=<name>  # Not syncing
flux get images all; flux logs --kind=ImageUpdateAutomation           # ImageUpdate not pushing
flux get helmreleases -A; helm list -A; helm history <rel> -n <ns>    # Helm release stuck
```

## Helm

```bash
# Basic ops
helm upgrade <rel> <chart> -n <ns> -f values.yaml --install  # Deploy/upgrade
helm rollback <rel> <revision> -n <ns>                       # Rollback
helm install <rel> <chart> --dry-run --debug                 # Preview

# Troubleshooting
helm list -A | grep failed; helm history <rel> -n <ns>                       # Failed release
helm rollback <rel> 0 -n <ns>                                                 # Delete pending upgrade
kubectl get secrets -n <ns> -l owner=helm,status=pending-upgrade; kubectl delete secret <name>  # Clear stuck operation
```

## Kustomize

```bash
kubectl kustomize <dir>                      # Preview
kubectl apply -k <dir>                       # Apply
kubectl diff -k overlays/production          # Diff before apply

# Troubleshooting
kubectl api-resources | grep <kind>          # API version mismatch
kubectl kustomize overlays/prod | grep -A5 "<name>"  # Verify patch target
```

## Safety checks

```bash
kubectl config current-context               # Verify cluster
kubectl apply --dry-run=server -k overlays/production  # Dry-run
kubectl diff -k overlays/production          # Preview changes
git diff HEAD^ k8s/                          # Review Git changes
```

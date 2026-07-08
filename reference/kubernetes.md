# Kubernetes — diagnostics and operations

## Critical gotchas

- **Always check events first** — `kubectl get events --sort-by='.lastTimestamp' -n <ns> | tail -30` tells the incident story before logs
- **Never use `-f` for streaming logs** — agent can't stream, use `--tail=200` or `--since=30m`
- **CrashLoop needs --previous logs** — current container just started, previous crashed container has the error
- **Empty service endpoints = selector mismatch** — service selector must match pod labels exactly
- **ConfigMap/Secret env vars need pod restart** — volumes update in ~60s, env vars never update without restart
- **Always specify `-n <namespace>`** — never assume default namespace on production clusters
- **OOMKilled = memory limit too low** — not a memory leak, raise limits
- **Evicted = node pressure** — check node conditions with `kubectl describe node`
- **Pending with "Insufficient cpu/memory" = cluster capacity exhausted** — scale nodes or reduce requests
- **PodDisruptionBudget blocks drain** — either wait for more pods ready or temporarily delete PDB

## Quick reference

```bash
# Triage (first 60 seconds)
kubectl get nodes; kubectl get pods -A | grep -v Running
kubectl get events --sort-by='.lastTimestamp' -A | tail -30
kubectl top nodes; kubectl top pods -n <namespace>

# Logs (never use -f)
kubectl logs <pod> -n <namespace> --tail=200
kubectl logs <pod> -n <namespace> --previous  # for CrashLoop
kubectl logs -l app=<label> -n <namespace> --tail=50 --prefix

# Pod failure diagnosis
kubectl describe pod <name> -n <namespace>  # check Events and Last State
# OOMKilled = raise memory limit | CrashLoopBackOff = check --previous logs
# ImagePullBackOff = registry auth or image missing | Pending = node capacity/selector/taints

# Resources
kubectl describe node <node> | grep -A5 "Allocated resources"
kubectl top pods -n <namespace> --containers
kubectl get limitranges,resourcequota -n <namespace>
kubectl set resources deployment/<name> -n <namespace> --limits=cpu=500m,memory=512Mi --requests=cpu=250m,memory=256Mi

# Networking
kubectl exec <pod-a> -n <namespace> -- wget -O- --timeout=5 http://<pod-b-ip>:8080
kubectl get endpoints <svc> -n <namespace>  # empty = selector mismatch
kubectl get networkpolicies -n <namespace>
kubectl get pods -n kube-system -l k8s-app=kube-dns  # CoreDNS health

# Ingress
kubectl get ingress -n <namespace>
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=100
# 404 = path rules wrong | 502/503 = backend not ready | TLS = check secret exists

# Storage
kubectl get pv,pvc -n <namespace>
kubectl describe pvc <name> -n <namespace>  # check events for provisioning issues
kubectl get storageclass

# RBAC
kubectl auth can-i list pods --as=system:serviceaccount:<namespace>:<sa-name> -n <namespace>
kubectl get rolebindings,clusterrolebindings -A -o json | jq -r '.items[] | select(.subjects[]?.name=="<sa-name>") | "\(.metadata.namespace) \(.metadata.name) \(.roleRef.name)"'

# ConfigMaps/Secrets
kubectl get configmaps,secrets -n <namespace>
kubectl rollout restart deployment/<name> -n <namespace>  # reload config (env vars need restart, volumes auto-update in ~60s)

# Deployments
kubectl rollout restart deployment/<name> -n <namespace>  # zero-downtime
kubectl rollout status deployment/<name> -n <namespace> --timeout=5m
kubectl rollout undo deployment/<name> -n <namespace>
kubectl scale deployment/<name> -n <namespace> --replicas=N

# Node operations
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data --timeout=5m
kubectl uncordon <node>
kubectl taint nodes <node> key=value:NoSchedule
kubectl get nodes -o json | jq -r '.items[] | "\(.metadata.name) \(.status.conditions[] | select(.status=="True") | .type)"'

# Jobs/CronJobs
kubectl create job --from=cronjob/<name> <name>-manual-$(date +%s) -n <namespace>
kubectl logs job/<name> -n <namespace>

# HPA
kubectl get hpa -n <namespace>
kubectl describe hpa <name> -n <namespace>  # check metrics-server if not scaling

# CRDs/Operators
kubectl get crd
kubectl logs -n <operator-namespace> -l app=<operator-label> --tail=200

# Non-interactive exec (can't use -it)
kubectl exec <pod> -n <namespace> -- env | grep -v PASSWORD
kubectl exec <pod> -n <namespace> -- ps aux

# Context verification
kubectl config current-context && kubectl get pods -n <namespace>
```

## Troubleshooting patterns

**Pods stuck Pending:**
- Check events: `kubectl describe pod <name> -n <namespace>`
- Node resources exhausted: `kubectl describe nodes | grep -A5 "Allocated resources"`
- PVC not bound: `kubectl get pvc -n <namespace>`
- Node selector/affinity not satisfied

**Pods CrashLooping:**
- Check previous logs: `kubectl logs <pod> -n <namespace> --previous`
- Check probes: `kubectl describe pod <name> -n <namespace> | grep -A10 Liveness`
- Check resource limits: `kubectl top pod <pod> -n <namespace> --containers`
- Check mounted secrets/configmaps exist

**Service not routing:**
- Check endpoints: `kubectl get endpoints <svc> -n <namespace>` (should list pod IPs)
- Check selector matches pods: `kubectl get svc <svc> -n <namespace> -o yaml | grep selector` vs `kubectl get pods -n <namespace> --show-labels`
- Test: `kubectl exec <test-pod> -n <namespace> -- wget -O- http://<svc>:<port>`

**High pod restart counts:**
- OOMKills: `kubectl describe pod <pod> -n <namespace> | grep -i oom` — raise memory limits
- Liveness probe too aggressive: increase `initialDelaySeconds` or `periodSeconds`
- Memory leak: monitor `kubectl top pod <pod> -n <namespace> --containers` over time

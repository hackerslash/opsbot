# Service Mesh Operations

## Critical Gotchas

- **Sidecar not injecting**: namespace must have `istio-injection=enabled` label or `linkerd.io/inject=enabled` annotation
- **mTLS connection failures**: mixing PERMISSIVE and STRICT modes causes auth errors; check `istioctl authn tls-check` or `linkerd viz edges`
- **Traffic not routing to canary**: VirtualService subset names must match DestinationRule subsets exactly; use `istioctl analyze`
- **Sidecar consuming excessive CPU/memory**: reduce trace sampling (`meshConfig.defaultConfig.tracing.sampling`) or disable unused features
- **Authorization policy denying legitimate traffic**: default-deny policies require explicit ALLOW rules; check `kubectl logs -c istio-proxy | grep "RBAC: access denied"`

## Quick Triage

```bash
istioctl version; kubectl get pods -n istio-system
kubectl get namespace -L istio-injection
istioctl proxy-status | grep -v SYNCED
kubectl logs -l app=istiod -n istio-system --tail=100 | grep -i error
```

## Istio

```bash
# Control plane
istioctl analyze -A
kubectl rollout restart deployment/istiod -n istio-system

# Sidecar injection
kubectl label namespace production istio-injection=enabled
kubectl get pod mypod -o jsonpath='{.spec.containers[*].name}'

# Traffic management (canary: 90% v1, 10% v2)
kubectl get virtualservices -A; kubectl get destinationrules -A
# VirtualService: route with weight 90 to subset v1, weight 10 to subset v2
# DestinationRule: subsets v1 (version=v1), v2 (version=v2)

# mTLS
istioctl authn tls-check
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata: {name: default, namespace: production}
spec: {mtls: {mode: STRICT}}
EOF
istioctl proxy-config secret mypod | grep -i expir
kubectl logs mypod -c istio-proxy | grep -i tls

# Authorization (deny-all + explicit allow)
kubectl get authorizationpolicies -A
# AuthorizationPolicy with spec: {} = deny-all
# AuthorizationPolicy with action: ALLOW, rules: principals/methods
kubectl logs mypod -c istio-proxy | grep "RBAC: access denied"

# Circuit breaking
# DestinationRule trafficPolicy: connectionPool (maxConnections, http1MaxPendingRequests), outlierDetection (consecutiveErrors, baseEjectionTime)
istioctl proxy-config cluster mypod --fqdn myapp.production.svc.cluster.local -o json | grep outlier

# Debugging
kubectl port-forward mypod 15000:15000
curl localhost:15000/config_dump; curl localhost:15000/clusters
istioctl proxy-config log mypod --level debug
kubectl top pod mypod --containers
```

## Linkerd

```bash
linkerd check; linkerd check --proxy
linkerd viz stat deploy -n linkerd

# Proxy injection
kubectl annotate namespace production linkerd.io/inject=enabled
linkerd viz stat pod mypod

# Traffic split (canary: 90% v1, 10% v2)
kubectl get trafficsplits -A
# TrafficSplit: service myapp, backends [{service: myapp-v1, weight: 900}, {service: myapp-v2, weight: 100}]

# mTLS
linkerd viz edges
linkerd identity
linkerd viz tap deploy/myapp | grep -i tls

# Debugging
linkerd viz tap deploy/myapp; linkerd viz top deploy/myapp
kubectl logs mypod -c linkerd-proxy
```

## Consul Connect

```bash
consul catalog services; consul catalog nodes -service=myapp
consul services register -name=myapp -port=8080

# Intentions (authorization)
consul intention list
consul intention create -allow frontend backend
consul intention check frontend backend

# Proxy
consul connect proxy -service myapp
journalctl -u consul -f | grep envoy
```

## Envoy Standalone

```bash
envoy --mode validate --config-path envoy.yaml
curl localhost:9901/config_dump; curl localhost:9901/clusters
curl -X POST localhost:9901/logging?level=debug
curl localhost:9901/clusters | grep health_flags
```

## Troubleshooting

```bash
# Sidecar not injecting
kubectl get namespace production -o jsonpath='{.metadata.labels.istio-injection}'
kubectl get pod mypod -o jsonpath='{.metadata.annotations.sidecar\.istio\.io/inject}'
kubectl logs -n istio-system -l app=istiod --tail=100 | grep injection
# kubectl label namespace production istio-injection=enabled; kubectl rollout restart deployment/myapp

# mTLS connection failures (503, TLS handshake errors)
istioctl authn tls-check mypod.production
kubectl get peerauthentication -A
kubectl logs mypod -c istio-proxy | grep -i "tls\|handshake"
# set PERMISSIVE temporarily, verify both services have sidecars, then STRICT

# Traffic not routing to canary
istioctl analyze virtualservice myapp
kubectl get destinationrule myapp -o yaml
kubectl get pods -l version=v2 --show-labels
istioctl proxy-config routes mypod
# ensure DestinationRule subsets match VirtualService subset references

# Sidecar high CPU/memory
kubectl top pod mypod --containers
kubectl exec mypod -c istio-proxy -- curl localhost:15000/stats | grep -i "memory\|cpu"
# set sidecar.istio.io/proxyCPU/proxyMemory annotations, reduce scope with includeOutboundIPRanges

# Authorization denying legitimate traffic (403)
kubectl get authorizationpolicies -A
istioctl proxy-config log mypod --level rbac:debug
kubectl logs mypod -c istio-proxy | grep "RBAC: access denied"
# add explicit ALLOW rule with principals matching service account
```

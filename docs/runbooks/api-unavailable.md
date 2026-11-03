# API unavailable

**Alert:** `MatterHubApiDown`, or the smoke test fails after a deployment.

## Check, outside in

```bash
curl -sv https://matterhub.example.com/version              # DNS, TLS, ingress
kubectl -n app-routing-system get pods                       # ingress controller healthy?
kubectl -n matterhub get ingress,svc,endpoints matterhub     # endpoints empty = no ready pods
kubectl -n matterhub get pods -l app.kubernetes.io/component=api
kubectl -n matterhub describe pod <pod>                      # probe failures, image pull, scheduling
```

| Symptom | Cause | Fix |
|---|---|---|
| TLS error | Certificate in Key Vault expired / not synced | Renew certificate in Key Vault; app routing picks it up |
| Endpoints empty, pods not Ready | `/readyz` failing: database | see [high-error-rate.md](high-error-rate.md) |
| `ImagePullBackOff` | Digest not in registry / AcrPull missing | Check `az acr repository show-manifests`; kubelet identity role assignment |
| `Pending` pods | No capacity or quota | `kubectl describe pod`; node pool max; ResourceQuota |
| `CreateContainerConfigError` mentioning secrets-store | Key Vault / workload identity issue | [security-incident.md](security-incident.md) checks; federated credential subject must be `system:serviceaccount:matterhub:matterhub` |
| Everything healthy in-cluster | NetworkPolicy or NSG change | Check recent Terraform/Helm changes to `networkpolicy.yaml` / NSG rules |

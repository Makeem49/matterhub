# Pod crash-looping

**Alert:** `MatterHubPodCrashLooping`: more than 3 restarts in 15 minutes.

```bash
kubectl -n matterhub get pods
kubectl -n matterhub describe pod <pod> | sed -n '/Last State/,/Ready/p'   # exit code, reason
kubectl -n matterhub logs <pod> --previous | tail -50
```

| Last state | Meaning | Action |
|---|---|---|
| `OOMKilled` (137) | Exceeded memory limit | Check for a leak (memory trend in Container Insights); raise `resources.limits.memory` if usage is legitimate |
| `Error` (1) with a config `ValidationError` | Bad configuration, e.g. auth settings missing | The app refuses insecure config by design. Fix values and redeploy; roll back if urgent |
| Liveness probe failures | Process hung (not the database: liveness never checks it) | Capture logs, roll back; investigate event-loop blocking |
| `secrets-store` mount errors | Key Vault access | Check identity role assignment and the Key Vault private endpoint DNS |

Because of the PDB and `maxUnavailable: 0`, a bad rollout leaves the old pods serving;
`helm upgrade --atomic` in the pipeline rolls back automatically on timeout.

# High latency

**Alert:** `MatterHubHighLatency`: p95 above 500 ms for 10 minutes.

## Check

1. Is it all routes or one? [`slow-requests.kql`](../../observability/kql/slow-requests.kql)
   gives p50/p95/p99 per route and the slowest request IDs.
2. Is the API CPU-bound? `kubectl -n matterhub top pods`; is the HPA at `maxReplicas`?
   `kubectl -n matterhub get hpa`.
3. Is it the database? PostgreSQL CPU, IOPS, connections; slow queries are logged
   (`log_min_duration_statement = 1000`) to `PostgreSQLLogs`.
4. App Insights > Performance > the slow operation > dependency breakdown.

## Mitigate

- HPA at max and CPU high: raise `autoscaling.maxReplicas` (Helm) or the user node pool
  `max_count` (Terraform). Check the namespace ResourceQuota has headroom.
- One slow query: add an index through a migration (expand-only, `CREATE INDEX CONCURRENTLY`).
- Database saturated: scale the SKU (`postgres.sku_name`): planned change, brief failover.
- Latency after a release: [rollback.md](rollback.md).

#!/usr/bin/env python3
"""Report AKS clusters that need Kubernetes or node-image patching.

    az login
    python scripts/python/aks_upgrade_report.py --subscription <id> [--json] [--fail-on-unsupported]

For every AKS cluster in the subscription it shows the control plane version, each node
pool's version and node image, the auto-upgrade channels, and the upgrades AKS offers.
A cluster is flagged when:

* a newer *patch* is available but the cluster is not on an auto-upgrade channel, or
* its minor version is no longer offered by AKS in the region (out of support), or
* node pools run a different version to the control plane (version skew).

Run weekly from a pipeline to evidence patching for the service's security assurance.
Requires: pip install azure-identity azure-mgmt-containerservice
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import asdict, dataclass, field
from typing import Any


@dataclass
class PoolInfo:
    name: str
    version: str
    node_image: str | None


@dataclass
class ClusterInfo:
    name: str
    resource_group: str
    location: str
    version: str
    upgrade_channel: str | None
    node_os_channel: str | None
    pools: list[PoolInfo]
    available_upgrades: list[str]
    supported_minors: list[str]


@dataclass
class Finding:
    cluster: str
    severity: str  # "high" | "medium" | "info"
    message: str


@dataclass
class Report:
    clusters: list[ClusterInfo] = field(default_factory=list)
    findings: list[Finding] = field(default_factory=list)

    @property
    def has_high(self) -> bool:
        return any(f.severity == "high" for f in self.findings)


def minor(version: str) -> str:
    major, minor_, *_ = version.split(".")
    return f"{major}.{minor_}"


def evaluate(cluster: ClusterInfo) -> list[Finding]:
    findings: list[Finding] = []
    current_minor = minor(cluster.version)

    if cluster.supported_minors and current_minor not in cluster.supported_minors:
        findings.append(
            Finding(
                cluster.name,
                "high",
                f"Kubernetes {cluster.version} is out of support in "
                f"{cluster.location}; supported minors: {', '.join(cluster.supported_minors)}",
            )
        )

    patches = [v for v in cluster.available_upgrades if minor(v) == current_minor]
    if patches and cluster.upgrade_channel in (None, "none"):
        findings.append(
            Finding(
                cluster.name,
                "medium",
                f"Patch {max(patches, key=_key)} available and no auto-upgrade channel is set",
            )
        )

    newer_minors = sorted({minor(v) for v in cluster.available_upgrades} - {current_minor}, key=_key)
    if newer_minors:
        findings.append(
            Finding(
                cluster.name,
                "info",
                f"Minor upgrade available: {newer_minors[-1]} (plan it: test in dev first)",
            )
        )

    for pool in cluster.pools:
        if pool.version != cluster.version:
            findings.append(
                Finding(
                    cluster.name,
                    "medium",
                    f"Node pool '{pool.name}' runs {pool.version}, control plane runs {cluster.version}",
                )
            )

    if cluster.node_os_channel in (None, "None", "Unmanaged"):
        findings.append(
            Finding(
                cluster.name,
                "medium",
                "Node OS security patches are not automated "
                "(set node_os_upgrade_channel = NodeImage or SecurityPatch)",
            )
        )
    return findings


def _key(version: str) -> tuple[int, ...]:
    return tuple(int(part) for part in version.split("."))


def build_report(clusters: list[ClusterInfo]) -> Report:
    report = Report(clusters=clusters)
    for cluster in clusters:
        report.findings.extend(evaluate(cluster))
    return report


def render_markdown(report: Report) -> str:
    lines = [
        "# AKS patching report",
        "",
        "| Cluster | Version | Upgrade channel | Node OS channel | Pools |",
        "|---|---|---|---|---|",
    ]
    for c in report.clusters:
        pools = "<br>".join(f"{p.name}: {p.version} / {p.node_image or '?'}" for p in c.pools)
        lines.append(
            f"| {c.name} | {c.version} | {c.upgrade_channel or 'none'} | "
            f"{c.node_os_channel or 'none'} | {pools} |"
        )
    lines += ["", "## Findings", ""]
    if not report.findings:
        lines.append("No action needed.")
    order = {"high": 0, "medium": 1, "info": 2}
    for f in sorted(report.findings, key=lambda f: (order[f.severity], f.cluster)):
        lines.append(f"- **{f.severity.upper()}** `{f.cluster}`: {f.message}")
    return "\n".join(lines) + "\n"


def collect(subscription_id: str) -> list[ClusterInfo]:  # pragma: no cover - needs Azure
    from azure.identity import DefaultAzureCredential
    from azure.mgmt.containerservice import ContainerServiceClient

    client = ContainerServiceClient(DefaultAzureCredential(), subscription_id)
    supported_by_region: dict[str, list[str]] = {}
    clusters: list[ClusterInfo] = []
    for mc in client.managed_clusters.list():
        rg = mc.id.split("/")[4]
        if mc.location not in supported_by_region:
            versions = client.managed_clusters.list_kubernetes_versions(mc.location)
            supported_by_region[mc.location] = sorted({v.version for v in versions.values or []}, key=_key)
        profile: Any = client.managed_clusters.get_upgrade_profile(rg, mc.name)
        upgrades = [u.kubernetes_version for u in (profile.control_plane_profile.upgrades or [])]
        auto = mc.auto_upgrade_profile
        clusters.append(
            ClusterInfo(
                name=mc.name,
                resource_group=rg,
                location=mc.location,
                version=mc.current_kubernetes_version or mc.kubernetes_version,
                upgrade_channel=getattr(auto, "upgrade_channel", None),
                node_os_channel=getattr(auto, "node_os_upgrade_channel", None),
                pools=[
                    PoolInfo(
                        p.name, p.current_orchestrator_version or p.orchestrator_version, p.node_image_version
                    )
                    for p in mc.agent_pool_profiles or []
                ],
                available_upgrades=upgrades,
                supported_minors=supported_by_region[mc.location],
            )
        )
    return clusters


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--subscription", required=True)
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    parser.add_argument(
        "--fail-on-unsupported",
        action="store_true",
        help="exit 1 when any HIGH finding exists (use in pipelines)",
    )
    args = parser.parse_args(argv)

    report = build_report(collect(args.subscription))
    if args.json:
        print(
            json.dumps(
                {
                    "clusters": [asdict(c) for c in report.clusters],
                    "findings": [asdict(f) for f in report.findings],
                },
                indent=2,
            )
        )
    else:
        print(render_markdown(report))
    return 1 if args.fail_on_unsupported and report.has_high else 0


if __name__ == "__main__":
    sys.exit(main())

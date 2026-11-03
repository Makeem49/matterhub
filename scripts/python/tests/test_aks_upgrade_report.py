import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import aks_upgrade_report as r  # noqa: E402


def cluster(**kw):
    base = dict(
        name="aks-matterhub-prod",
        resource_group="rg",
        location="uksouth",
        version="1.32.4",
        upgrade_channel="patch",
        node_os_channel="NodeImage",
        pools=[
            r.PoolInfo("system", "1.32.4", "AKSAzureLinux-V3gen2-202610.20.0"),
            r.PoolInfo("user", "1.32.4", "AKSAzureLinux-V3gen2-202610.20.0"),
        ],
        available_upgrades=["1.32.7", "1.33.3"],
        supported_minors=["1.32", "1.33", "1.34"],
    )
    base.update(kw)
    return r.ClusterInfo(**base)


def severities(c):
    return sorted(f.severity for f in r.evaluate(c))


def test_healthy_cluster_only_gets_minor_upgrade_info():
    assert severities(cluster()) == ["info"]


def test_out_of_support_minor_is_high():
    c = cluster(version="1.29.9", pools=[r.PoolInfo("system", "1.29.9", None)], available_upgrades=["1.30.5"])
    findings = r.evaluate(c)
    assert any(f.severity == "high" and "out of support" in f.message for f in findings)
    assert r.build_report([c]).has_high


def test_patch_available_without_channel_is_medium():
    findings = r.evaluate(cluster(upgrade_channel=None))
    assert any(f.severity == "medium" and "1.32.7" in f.message for f in findings)


def test_version_skew_and_unmanaged_node_os_are_flagged():
    c = cluster(pools=[r.PoolInfo("user", "1.31.8", None)], node_os_channel="None")
    messages = " ".join(f.message for f in r.evaluate(c))
    assert "runs 1.31.8" in messages
    assert "Node OS security patches are not automated" in messages


def test_version_ordering_is_numeric():
    c = cluster(
        version="1.9.1",
        supported_minors=[],
        pools=[r.PoolInfo("p", "1.9.1", None)],
        available_upgrades=["1.10.2", "1.9.5"],
        upgrade_channel="none",
    )
    msgs = [f.message for f in r.evaluate(c)]
    assert any("Minor upgrade available: 1.10" in m for m in msgs)
    assert any("Patch 1.9.5" in m for m in msgs)


def test_markdown_report():
    report = r.build_report([cluster(), cluster(name="aks-dev", upgrade_channel=None)])
    md = r.render_markdown(report)
    assert md.startswith("# AKS patching report")
    assert "| aks-matterhub-prod | 1.32.4 | patch | NodeImage |" in md
    assert md.index("**MEDIUM**") < md.index("**INFO**")
    assert "No action needed." in r.render_markdown(r.build_report([]))

import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import release_notes as rn  # noqa: E402

US = "\x1f"


def rec(subject: str, body: str = "", sha: str = "abcdef1234", author: str = "Akeem") -> str:
    return US.join([sha, author, subject, body])


def test_parses_conventional_commit_with_scope():
    c = rn.parse_commit(rec("feat(api): add audit trail endpoint"))
    assert isinstance(c, rn.Commit)
    assert (c.type, c.scope, c.subject, c.breaking, c.sha) == (
        "feat",
        "api",
        "add audit trail endpoint",
        False,
        "abcdef12",
    )


def test_breaking_change_by_bang_or_footer():
    assert rn.parse_commit(rec("fix!: drop v0 endpoints")).breaking
    assert rn.parse_commit(rec("feat: new auth", body="BREAKING CHANGE: tokens need roles")).breaking


def test_unconventional_commits_are_kept_but_merges_dropped():
    notes = rn.build_notes([rec("tidy things"), rec("Merge pull request #4"), rec("docs: runbook")])
    assert notes.unconventional == ["tidy things"]
    assert len(notes.sections["Documentation"]) == 1


def test_render_groups_and_flags_risky_changes():
    notes = rn.build_notes(
        [
            rec("feat(api): pagination"),
            rec("infra(terraform): enable zone-redundant HA", sha="1111111111"),
            rec("fix(auth): reject tokens from other tenants", sha="2222222222"),
            rec("chore!: python 3.13 base image", sha="3333333333"),
        ]
    )
    md = rn.render(notes, "v1.0.0", "v1.1.0")
    assert md.startswith("# Release notes: `v1.0.0` -> `v1.1.0`")
    assert "## :warning: Breaking changes" in md
    review = md.split("## Needs change review")[1].split("## New features")[0]
    assert "enable zone-redundant HA" in review and "reject tokens" in review
    assert md.index("## New features") < md.index("## Bug fixes") < md.index("## Infrastructure")


def test_main_against_a_real_git_repo(tmp_path, monkeypatch, capsys):
    def git(*args):
        subprocess.run(["git", *args], cwd=tmp_path, check=True, capture_output=True)

    git("init", "-q")
    git("config", "user.email", "t@example.com")
    git("config", "user.name", "Tester")
    git("commit", "--allow-empty", "-q", "-m", "chore: initial")
    git("tag", "v1")
    git("commit", "--allow-empty", "-q", "-m", "feat(helm): add PodDisruptionBudget")
    monkeypatch.chdir(tmp_path)
    assert rn.main(["v1", "HEAD"]) == 0
    out = capsys.readouterr().out
    assert "**helm:** add PodDisruptionBudget" in out
    assert rn.main(["does-not-exist"]) == 2

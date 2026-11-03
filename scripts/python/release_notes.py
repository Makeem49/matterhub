#!/usr/bin/env python3
"""Generate release notes from Conventional Commits between two git refs.

    python scripts/python/release_notes.py v1.4.0 HEAD > RELEASE_NOTES.md

Commit messages follow https://www.conventionalcommits.org (enforced in PR titles; see
CONTRIBUTING.md), e.g. ``feat(api): add audit trail endpoint`` or ``fix!: ...``.
The output groups changes for the CAB/release record and flags breaking changes and
changes that touch infrastructure or security.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from collections import defaultdict
from dataclasses import dataclass, field

SECTIONS: dict[str, str] = {
    "feat": "New features",
    "fix": "Bug fixes",
    "perf": "Performance",
    "security": "Security",
    "infra": "Infrastructure",
    "ci": "Pipelines",
    "docs": "Documentation",
    "refactor": "Refactoring",
    "test": "Tests",
    "chore": "Maintenance",
    "build": "Maintenance",
    "deps": "Dependencies",
}
_PATTERN = re.compile(r"^(?P<type>[a-z]+)(?:\((?P<scope>[\w./-]+)\))?(?P<breaking>!)?: (?P<subject>.+)$")
_SEPARATOR = "\x1f"


@dataclass(frozen=True)
class Commit:
    sha: str
    type: str
    scope: str | None
    subject: str
    breaking: bool
    author: str


@dataclass
class ReleaseNotes:
    sections: dict[str, list[Commit]] = field(default_factory=lambda: defaultdict(list))
    breaking: list[Commit] = field(default_factory=list)
    unconventional: list[str] = field(default_factory=list)


def parse_commit(line: str) -> Commit | str:
    """Parse one ``sha<US>author<US>subject<US>body`` record. Returns the raw subject if
    the commit does not follow the convention."""
    sha, author, subject, body = (line.split(_SEPARATOR) + ["", "", ""])[:4]
    match = _PATTERN.match(subject.strip())
    if not match:
        return subject.strip()
    breaking = bool(match["breaking"]) or "BREAKING CHANGE:" in body
    return Commit(
        sha=sha[:8],
        type=match["type"],
        scope=match["scope"],
        subject=match["subject"].strip(),
        breaking=breaking,
        author=author,
    )


def build_notes(records: list[str]) -> ReleaseNotes:
    notes = ReleaseNotes()
    for record in records:
        if not record.strip():
            continue
        parsed = parse_commit(record)
        if isinstance(parsed, str):
            if not parsed.startswith("Merge "):
                notes.unconventional.append(parsed)
            continue
        notes.sections[SECTIONS.get(parsed.type, "Other")].append(parsed)
        if parsed.breaking:
            notes.breaking.append(parsed)
    return notes


def render(notes: ReleaseNotes, from_ref: str, to_ref: str) -> str:
    def line(c: Commit) -> str:
        scope = f"**{c.scope}:** " if c.scope else ""
        return f"- {scope}{c.subject} (`{c.sha}`, {c.author})"

    out = [f"# Release notes: `{from_ref}` -> `{to_ref}`", ""]
    if notes.breaking:
        out += ["## :warning: Breaking changes", "", *[line(c) for c in notes.breaking], ""]

    risky = [
        c
        for cs in notes.sections.values()
        for c in cs
        if c.type in {"infra", "security"} or (c.scope or "") in {"terraform", "helm", "k8s", "auth"}
    ]
    if risky:
        out += [
            "## Needs change review",
            "",
            "These touch infrastructure, deployment or security controls:",
            "",
            *[line(c) for c in risky],
            "",
        ]

    order = list(dict.fromkeys([*SECTIONS.values(), "Other"]))
    for title in order:
        commits = notes.sections.get(title)
        if commits:
            out += [f"## {title}", "", *[line(c) for c in commits], ""]

    if notes.unconventional:
        out += ["## Other commits", "", *[f"- {s}" for s in notes.unconventional], ""]
    return "\n".join(out).rstrip() + "\n"


def git_log(from_ref: str, to_ref: str) -> list[str]:
    fmt = _SEPARATOR.join(["%H", "%an", "%s", "%b"]) + "\x1e"
    result = subprocess.run(  # noqa: S603 - fixed argv, no shell
        ["git", "log", "--no-merges", f"--format={fmt}", f"{from_ref}..{to_ref}"],  # noqa: S607
        check=True,
        capture_output=True,
        text=True,
    )
    return [r.strip("\n") for r in result.stdout.split("\x1e")]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("from_ref", help="previous release tag or commit")
    parser.add_argument("to_ref", nargs="?", default="HEAD")
    args = parser.parse_args(argv)
    try:
        records = git_log(args.from_ref, args.to_ref)
    except subprocess.CalledProcessError as exc:
        print(f"git log failed: {exc.stderr.strip()}", file=sys.stderr)
        return 2
    sys.stdout.write(render(build_notes(records), args.from_ref, args.to_ref))
    return 0


if __name__ == "__main__":
    sys.exit(main())

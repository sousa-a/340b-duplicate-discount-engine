# test_publication.py
#
# Nothing internal goes public. The decision log, the internal review, the plans, the data source log and the
# reference data profile live in private/ (git-ignored),
# and every published file cites sources by author and year (docs/REFERENCES.md), never by internal numbers.
# This test scans every file that would be pushed and fails on:
#   - decision numbers (D7, D0c...), open items (O3...) and internal reference numbers (R14...)
#   - links to the private docs
#   - notes about how a source reached us ("pasted", "by the user") and chat or session links
# All data in this repository is completely synthetic (SYNTHETIC_DATA_NOTICE.md).

import pathlib
import re

REPO = pathlib.Path(__file__).resolve().parents[1]
NOT_PUBLISHED = {"private", "reference_data", "data", ".git", "__pycache__", ".pytest_cache", "target", "dbt_packages", "logs"}
SUFFIXES = {".py", ".md", ".yml", ".yaml", ".csv", ".sql", ".txt", ".toml", ".cfg", ".json"}

CHECKS = {
    "decision number": re.compile(r"\bD\d{1,2}[a-e]?\b"),
    "open item number": re.compile(r"\bO\d{1,2}\b"),
    "internal reference number": re.compile(r"\bR\d{1,2}\b"),
    "link to a private doc": re.compile(r"DECISIONS\.md|PROJECT_REVIEW\.md|VISUALS_PLAN\.md|PARAMETERS\.md|REFERENCE_KEYS|DATA_SOURCES\.md|REFERENCE_DATA_PROFILE|SYNTHETIC_DATA_DESIGN"),
    "internal note": re.compile(r"\bpasted\b|\bby the user\b|\bfrom the user\b|claude\.ai|Claude-Session|session_0", re.IGNORECASE),
}

# The register script writes private/PARAMETERS.md and its test checks it, so those two name the file on purpose.
ALLOWED = {("src/common/build_parameters_register.py", "link to a private doc"),
           ("tests/test_parameters_register.py", "link to a private doc")}


def published_files():
    for p in sorted(REPO.rglob("*")):
        rel = p.relative_to(REPO)
        if p.is_file() and p.suffix in SUFFIXES and not (set(rel.parts) & NOT_PUBLISHED) and p.name != "test_publication.py":
            yield p, rel


def test_nothing_internal_is_published():
    problems = []
    n = 0
    for p, rel in published_files():
        n += 1
        for i, line in enumerate(p.read_text(encoding="utf-8-sig").splitlines(), start=1):
            for what, rx in CHECKS.items():
                m = rx.search(line)
                if m and (rel.as_posix(), what) not in ALLOWED:
                    problems.append(f"{rel}:{i}: {what} '{m.group(0)}'")
    print(f"[publication] scanned {n} files, {len(problems)} problems")
    for x in problems[:50]:
        print(f"[publication]   {x}")
    assert not problems, f"{len(problems)} internal references in published files, first: {problems[:5]}"


def test_private_folder_is_git_ignored():
    lines = (REPO / ".gitignore").read_text(encoding="utf-8").splitlines()
    assert "private/" in lines

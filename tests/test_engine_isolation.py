# test_engine_isolation.py
#
# Enforces the "two worlds" rule:
# the detection engine must never read ground truth or generator-only data.
#
# Checked locations: every SQL and YAML file under dbt/, every Python file under src/ingestion/ and the Databricks
# notebooks under notebooks/ (the raw parser is engine code too).
# Forbidden: any reference to the truth schema, and any reference to generator-only tables
# (TPA accumulation records), which a manufacturer would never receive.

import pathlib
import re

REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]

ENGINE_PATHS = [
    (REPO_ROOT / "dbt", "*.sql"),
    (REPO_ROOT / "dbt", "*.yml"),
    (REPO_ROOT / "src" / "ingestion", "*.py"),
    (REPO_ROOT / "notebooks", "*.py"),
]

# Patterns that would mean the engine is looking at the answer key or at hidden generator data.
FORBIDDEN_PATTERNS = {
    "truth schema": re.compile(r"\btruth\s*\.", re.IGNORECASE),
    "truth source": re.compile(r"source\(\s*['\"]truth['\"]", re.IGNORECASE),
    "ground truth table": re.compile(r"\bground_truth", re.IGNORECASE),
    "TPA accumulation table": re.compile(r"\btpa_accumulat", re.IGNORECASE),
}

# This file and the dbt_project.yml comment mention the rule itself; they are not engine code.
ALLOWED_FILES = {
    REPO_ROOT / "dbt" / "dbt_project.yml",
}


def _engine_files():
    for base, pattern in ENGINE_PATHS:
        if base.exists():
            for path in sorted(base.rglob(pattern)):
                if path in ALLOWED_FILES or "target" in path.parts or "dbt_packages" in path.parts or "seeds" in path.parts:
                    continue
                yield path


def test_engine_never_reads_truth_or_generator_only_data():
    violations = []
    checked = 0
    for path in _engine_files():
        checked += 1
        text = path.read_text(encoding="utf-8", errors="replace")
        for line_no, line in enumerate(text.splitlines(), start=1):
            for label, regex in FORBIDDEN_PATTERNS.items():
                if regex.search(line):
                    violations.append(f"{path.relative_to(REPO_ROOT)}:{line_no} [{label}] {line.strip()}")
    print(f"[engine-isolation] files checked: {checked}")
    print(f"[engine-isolation] violations found: {len(violations)}")
    for v in violations:
        print(f"[engine-isolation] VIOLATION {v}")
    assert not violations, "Engine code references ground truth or generator-only data:\n" + "\n".join(violations)

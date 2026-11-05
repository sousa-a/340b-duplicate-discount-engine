# conftest.py
# Makes the repository root importable so tests can use "from src... import ...".
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))

# The synthetic data generator (src/generator/, src/common/, config/) is kept in a separate private repo for now.
# In a checkout without it, pytest skips the generator tests instead of failing on their imports, so
# "python3 -m pytest tests -q" works in both places.
ROOT = pathlib.Path(__file__).resolve().parents[1]
GENERATOR_TESTS = [
    "test_entities.py", "test_prices.py", "test_ndc.py", "test_dispensing.py", "test_conversion.py",
    "test_wholesale.py", "test_x12.py", "test_npi.py", "test_extract_nppes_npis.py", "test_identifier_audit.py",
    "test_parameters_register.py", "test_pilot_submissions.py", "test_mtf.py", "test_state_invoices.py", "test_noise.py", "test_truth.py",
]
HAS_GENERATOR = (ROOT / "src" / "generator" / "config.py").exists() and (ROOT / "src" / "common" / "npi.py").exists()
collect_ignore = [] if HAS_GENERATOR else GENERATOR_TESTS
if not HAS_GENERATOR:
    print(f"[conftest] generator not in this checkout, skipping {len(GENERATOR_TESTS)} generator test files")

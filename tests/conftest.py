# conftest.py
# Makes the repository root importable so tests can use "from src... import ...".
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))

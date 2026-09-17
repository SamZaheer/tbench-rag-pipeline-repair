import subprocess
import pytest

def test_retrieval_pipeline():
    """Verify that the retrieval pipeline in /app passes all evaluation tests."""
    result = subprocess.run(
        ["pytest", "/app/tests/test_retrieval.py", "-v"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Retrieval tests failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"

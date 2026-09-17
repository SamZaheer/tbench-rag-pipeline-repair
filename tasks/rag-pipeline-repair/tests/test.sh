#!/bin/bash
pip install -q pytest
pytest /app/tests/test_retrieval.py -v
if [ $? -eq 0 ]; then
    echo "1.0" > /logs/verifier/reward.txt
else
    echo "0.0" > /logs/verifier/reward.txt
fi

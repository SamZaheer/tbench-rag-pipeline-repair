FROM python:3.11-slim

WORKDIR /app

RUN pip install --no-cache-dir pytest numpy

COPY retrieval/ /app/retrieval/
COPY tests/ /app/tests/

ENV PYTHONPATH=/app

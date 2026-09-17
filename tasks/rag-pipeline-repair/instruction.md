You are a senior engineer at a fast-growing startup. A colleague has handed you a broken "hybrid retrieval" service that powers the company's internal knowledge-base assistant.

The service lives in `/app/retrieval/retrieval.py`. It is supposed to implement a **hybrid retrieval pipeline** that:

1. Indexes a corpus of text documents using both BM25 sparse retrieval and dense vector retrieval (cosine similarity over TF-IDF vectors).
2. At query time, retrieves the top-k candidates from both retrievers and **fuses** the ranked lists using Reciprocal Rank Fusion (RRF).
3. Returns the final fused and re-ranked document list.
4. Supports incremental document addition (`add_documents`) after initial index construction without rebuilding the full index from scratch.
5. Filters out documents that do NOT contain at least one token from a caller-supplied `allow_terms` list when `allow_terms` is non-empty.

The code is intentionally broken in multiple independent ways. Some bugs are shallow (wrong variable names, off-by-one), some are algorithmic (wrong fusion formula, missing multiplier), and some are subtle (incorrect filter scope, stale cache after `add_documents`).

You must repair the file so that all evaluation tests pass.

## Interface contract (DO NOT change the public API)

```python
class HybridRetriever:
    def __init__(self, k1: float = 1.5, b: float = 0.75, rrf_k: int = 60)
        """
        k1, b  — BM25 parameters.
        rrf_k  — constant used in Reciprocal Rank Fusion score: 1/(rrf_k + rank).
        """

    def build_index(self, documents: list[str]) -> None
        """Build BM25 + dense index from scratch on the given documents."""

    def add_documents(self, new_docs: list[str]) -> None
        """Append new documents to the existing index."""

    def retrieve(
        self,
        query: str,
        top_k: int = 5,
        allow_terms: list[str] | None = None,
    ) -> list[tuple[str, float]]
        """
        Return up to top_k (document_text, rrf_score) tuples, ranked
        descending by score.
        If allow_terms is non-empty, only documents containing at least one
        of those terms (case-insensitive) are eligible.
        """
```

## What you know about the bugs

You have been told there are **at least 5 distinct bugs** spread across the file. Do not assume the entire architecture is wrong — some parts work correctly.

The bugs include at least:
- A BM25 average document length formula error
- A BM25 scoring numerator error
- A stale document-frequency table after `add_documents`
- An incorrect normalization in the dense retriever
- An off-by-one in the RRF rank formula
- An `allow_terms` filter that checks the wrong token set

## Constraints

- You must **ONLY** modify `/app/retrieval/retrieval.py`.
- Do not add new external dependencies. Available: `math`, `re`, `collections`, `numpy`.
- Do not modify any test files.
- The interface (class name, method signatures, return types) must remain exactly as described above.

When you believe you have fixed all bugs, run the evaluation:

```bash
cd /app && python -m pytest tests/ -v
```

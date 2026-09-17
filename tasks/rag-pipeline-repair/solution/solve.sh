#!/usr/bin/env bash
set -euo pipefail

cat << 'EOF' > /app/retrieval/retrieval.py
"""
Hybrid Retrieval Engine combining BM25 and Dense TF-IDF Cosine Similarity with RRF.
"""

import math
import re
from collections import Counter, defaultdict


class HybridRetriever:

    def __init__(
        self, k1: float = 1.5, b: float = 0.75, rrf_k: int = 60
    ) -> None:
        self.k1 = k1
        self.b = b
        self.rrf_k = rrf_k

        self.documents: list[str] = []
        self.doc_tokens: list[list[str]] = []
        self.doc_lengths: list[int] = []
        self.avgdl: float = 0.0
        self.N: int = 0

        # BM25 index data structures
        self.doc_freqs: dict[str, int] = defaultdict(int)
        self.term_freqs: list[Counter[str]] = []

        # Dense index data structures
        self.vocab: set[str] = set()
        self.doc_vectors: list[dict[str, float]] = []

    def _tokenize(self, text: str) -> list[str]:
        """Simple lowercase word tokenizer."""
        return re.findall(r"\b\w+\b", text.lower())

    def build_index(self, documents: list[str]) -> None:
        """Build BM25 + dense index from scratch on the given documents."""
        self.documents = list(documents)
        self.N = len(documents)
        self.doc_tokens = [self._tokenize(doc) for doc in documents]
        self.doc_lengths = [len(tokens) for tokens in self.doc_tokens]

        total_len = sum(self.doc_lengths)
        self.avgdl = total_len / self.N if self.N > 0 else 0.0

        # Build BM25 term frequencies & document frequencies
        self.doc_freqs = defaultdict(int)
        self.term_freqs = []
        self.vocab = set()
        for tokens in self.doc_tokens:
            tf = Counter(tokens)
            self.term_freqs.append(tf)
            for term in tf.keys():
                self.doc_freqs[term] += 1
                self.vocab.add(term)

        # Build dense TF-IDF vectors
        self._build_dense_vectors()

    def add_documents(self, new_docs: list[str]) -> None:
        """Append new documents to the existing index."""
        if not new_docs:
            return

        self.documents.extend(new_docs)
        self.N = len(self.documents)

        new_tokens_list = [self._tokenize(doc) for doc in new_docs]
        self.doc_tokens.extend(new_tokens_list)
        new_lengths = [len(tokens) for tokens in new_tokens_list]
        self.doc_lengths.extend(new_lengths)

        # Update avgdl
        self.avgdl = sum(self.doc_lengths) / self.N if self.N > 0 else 0.0

        # Update document frequencies and vocabulary
        for tokens in new_tokens_list:
            tf = Counter(tokens)
            self.term_freqs.append(tf)
            for term in tf.keys():
                self.doc_freqs[term] += 1
                self.vocab.add(term)

        # Re-build dense vectors for all docs with updated collection state
        self._build_dense_vectors()

    def _build_dense_vectors(self) -> None:
        """Build L2-normalized TF-IDF vectors for all documents."""
        self.doc_vectors = []
        for tf in self.term_freqs:
            vec = {}
            for term, count in tf.items():
                df = self.doc_freqs.get(term, 0)
                idf = (
                    math.log((self.N - df + 0.5) / (df + 0.5) + 1.0)
                    if df > 0
                    else 0.0
                )
                tf_val = 1.0 + math.log(count) if count > 0 else 0.0
                vec[term] = tf_val * idf

            norm = math.sqrt(sum(v**2 for v in vec.values())) if vec else 0.0
            if norm > 0:
                vec = {term: val / norm for term, val in vec.items()}
            self.doc_vectors.append(vec)

    def _bm25_score(self, query_tokens: list[str], doc_idx: int) -> float:
        """Calculate BM25 score for a query against document at doc_idx."""
        score = 0.0
        doc_len = self.doc_lengths[doc_idx]
        tf_counter = self.term_freqs[doc_idx]

        for term in query_tokens:
            if term not in tf_counter:
                continue
            tf = tf_counter[term]
            df = self.doc_freqs.get(term, 0)

            idf = math.log((self.N - df + 0.5) / (df + 0.5) + 1.0)

            denom = tf + self.k1 * (
                1.0 - self.b + self.b * (doc_len / self.avgdl)
            )
            score += idf * (tf * (self.k1 + 1.0)) / denom

        return score

    def _dense_score(self, query_tokens: list[str], doc_idx: int) -> float:
        """Calculate dense cosine similarity score."""
        q_tf = Counter(query_tokens)
        q_vec = {}
        for term, count in q_tf.items():
            df = self.doc_freqs.get(term, 0)
            idf = (
                math.log((self.N - df + 0.5) / (df + 0.5) + 1.0)
                if df > 0
                else 0.0
            )
            tf_val = 1.0 + math.log(count) if count > 0 else 0.0
            q_vec[term] = tf_val * idf

        norm = math.sqrt(sum(v**2 for v in q_vec.values())) if q_vec else 0.0
        if norm > 0:
            q_vec = {term: val / norm for term, val in q_vec.items()}

        doc_vec = self.doc_vectors[doc_idx]
        return sum(q_vec[t] * doc_vec.get(t, 0.0) for t in q_vec)

    def retrieve(
        self,
        query: str,
        top_k: int = 5,
        allow_terms: list[str] | None = None,
    ) -> list[tuple[str, float]]:
        """Retrieve and rank documents using hybrid RRF."""
        if not self.documents:
            return []

        query_tokens = self._tokenize(query)

        # Filtering logic
        eligible_indices = []
        if allow_terms:
            allow_set = set(t.lower() for t in allow_terms)
            for idx, tokens in enumerate(self.doc_tokens):
                token_set = set(tokens)
                if any(term in token_set for term in allow_set):
                    eligible_indices.append(idx)
        else:
            eligible_indices = list(range(len(self.documents)))

        if not eligible_indices:
            return []

        # Score eligible documents
        bm25_scores = [
            (idx, self._bm25_score(query_tokens, idx))
            for idx in eligible_indices
        ]
        dense_scores = [
            (idx, self._dense_score(query_tokens, idx))
            for idx in eligible_indices
        ]

        # Rank documents (1-indexed ranks for RRF)
        bm25_ranked = [
            idx for idx, _ in sorted(bm25_scores, key=lambda x: x[1], reverse=True)
        ]
        dense_ranked = [
            idx for idx, _ in sorted(dense_scores, key=lambda x: x[1], reverse=True)
        ]

        rrf_scores = defaultdict(float)

        for rank_0, idx in enumerate(bm25_ranked):
            rrf_scores[idx] += 1.0 / (self.rrf_k + rank_0 + 1)

        for rank_0, idx in enumerate(dense_ranked):
            rrf_scores[idx] += 1.0 / (self.rrf_k + rank_0 + 1)

        # Sort by RRF score descending
        final_ranked = sorted(
            rrf_scores.items(), key=lambda x: x[1], reverse=True
        )

        results = [
            (self.documents[idx], score)
            for idx, score in final_ranked[:top_k]
        ]
        return results
EOF

"""
Evaluation unit tests for HybridRetriever.
Tests check the specific contract and bug fixes required.
"""

import math
from retrieval.retrieval import HybridRetriever


def test_avgdl_calculation():
    """Bug 1 check: avgdl must equal sum(doc_lengths) / N."""
    docs = [
        "apple banana cherry",
        "date elderberry fig grape",
    ]
    retriever = HybridRetriever()
    retriever.build_index(docs)

    # doc1 has 3 tokens, doc2 has 4 tokens -> total 7 tokens across 2 docs -> avgdl = 3.5
    assert retriever.avgdl == 3.5, f"Expected avgdl 3.5, got {retriever.avgdl}"


def test_bm25_scoring_formula():
    """Bug 2 check: BM25 score must use (k1 + 1) multiplier in TF numerator."""
    retriever = HybridRetriever(k1=1.5, b=0.75)
    docs = [
        "python machine learning data science",
        "python python python code developer",
    ]
    retriever.build_index(docs)

    # doc1 has 5 tokens, doc2 has 5 tokens -> avgdl = 5.0
    # N=2, df=2 -> idf = ln((2-2+0.5)/(2+0.5) + 1.0) = ln(0.5/2.5 + 1.0) = ln(1.2)
    idf = math.log(1.2)
    tf = 1
    denom = tf + 1.5 * (1.0 - 0.75 + 0.75 * (5.0 / 5.0))
    expected_score = idf * (tf * 2.5) / denom

    actual_score = retriever._bm25_score(["python"], 0)
    assert math.isclose(actual_score, expected_score, rel_tol=1e-5), (
        f"Expected BM25 score {expected_score}, got {actual_score}"
    )


def test_add_documents_updates_df_and_vocab():
    """Bug 3 check: add_documents must update doc_freqs, vocab, N, and dense vectors."""
    retriever = HybridRetriever()
    initial_docs = ["first document about alpha"]
    retriever.build_index(initial_docs)

    assert "beta" not in retriever.vocab
    assert retriever.doc_freqs.get("beta", 0) == 0

    new_docs = ["second document about beta and gamma"]
    retriever.add_documents(new_docs)

    assert retriever.N == 2
    assert "beta" in retriever.vocab
    assert retriever.doc_freqs["beta"] == 1

    # Check retrieval for newly added document term
    results = retriever.retrieve("beta", top_k=1)
    assert len(results) == 1
    assert "second document" in results[0][0]


def test_dense_vector_l2_normalization():
    """Bug 4 check: Dense vector norm must use sum of squares v**2."""
    retriever = HybridRetriever()
    docs = ["quantum computing physics physics"]
    retriever.build_index(docs)

    vec = retriever.doc_vectors[0]
    # Sum of squares of L2-normalized vector must be 1.0
    l2_sum = sum(v**2 for v in vec.values())
    assert math.isclose(l2_sum, 1.0, rel_tol=1e-5), f"L2 norm sum of squares was {l2_sum}, expected 1.0"


def test_rrf_rank_scoring():
    """Bug 5 check: RRF score must use 1-indexed rank formula 1 / (rrf_k + rank)."""
    retriever = HybridRetriever(rrf_k=60)
    docs = [
        "machine learning models",
        "deep neural networks",
    ]
    retriever.build_index(docs)

    results = retriever.retrieve("learning", top_k=2)
    # The top document (rank 1 in both BM25 and dense) should get rrf score 2 * (1 / (60 + 1)) = 2/61
    expected_top_score = 2.0 / 61.0
    top_doc, top_score = results[0]
    assert math.isclose(top_score, expected_top_score, rel_tol=1e-4), (
        f"Expected top RRF score {expected_top_score}, got {top_score}"
    )


def test_allow_terms_filtering():
    """Bug 6 check: allow_terms filter must use OR logic (at least one term)."""
    retriever = HybridRetriever()
    docs = [
        "apple pie recipe",
        "banana bread recipe",
        "cherry tart recipe",
    ]
    retriever.build_index(docs)

    # Searching with allow_terms=["apple", "banana"] should return docs 0 and 1, but filter out doc 2
    results = retriever.retrieve("recipe", top_k=5, allow_terms=["apple", "banana"])
    retrieved_texts = [doc for doc, _ in results]

    assert len(results) == 2, f"Expected 2 eligible documents, got {len(results)}"
    assert "apple pie recipe" in retrieved_texts
    assert "banana bread recipe" in retrieved_texts
    assert "cherry tart recipe" not in retrieved_texts

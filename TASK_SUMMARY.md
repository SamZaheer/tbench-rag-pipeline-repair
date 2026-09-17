# Deep-Dive Technical Summary: `samzaheer/rag-pipeline-repair`

## 1. System Architecture: How Hybrid Retrieval Works

The core module `/app/retrieval/retrieval.py` implements a class called `HybridRetriever`. It combines two distinct information retrieval paradigms using **Reciprocal Rank Fusion (RRF)**:

```
                          ┌──────────────────────────┐
                          │  Input Document Corpus   │
                          └────────────┬─────────────┘
                                       │
                         ┌─────────────┴─────────────┐
                         ▼                           ▼
              ┌─────────────────────┐     ┌─────────────────────┐
              │    BM25 Retriever   │     │    Dense TF-IDF     │
              │  (Sparse / Exact)   │     │ (Cosine Similarity) │
              └──────────┬──────────┘     └──────────┬──────────┘
                         │                           │
                         │ BM25 Scores               │ Cosine Scores
                         ▼                           ▼
                     Rank List 1                 Rank List 2
                         │                           │
                         └─────────────┬─────────────┘
                                       │
                                       ▼
                       ┌───────────────────────────────┐
                       │  Reciprocal Rank Fusion (RRF) │
                       │    Score = 1/(k + Rank_1) +   │
                       │            1/(k + Rank_2)     │
                       └───────────────┬───────────────┘
                                       │
                                       ▼
                           Top-k Reranked Results
```

### Key Methods in `HybridRetriever`:
1. `build_index(documents: list[str])`: Tokenizes documents, calculates document lengths, collection size ($N$), average document length ($\text{avgdl}$), document frequencies ($\text{doc\_freqs}$), and L2-normalized TF-IDF dense vectors.
2. `add_documents(new_docs: list[str])`: Appends new documents to an existing index without rebuilding from scratch.
3. `retrieve(query: str, top_k: int, allow_terms: list[str])`: Filters candidates using `allow_terms` (if specified), computes BM25 and Dense Cosine scores for eligible candidates, ranks them separately, fuses ranks via RRF, and returns the top-$k$ documents with their RRF scores.

---

## 2. Detailed Breakdown of the 6 Planted Bugs

Each bug was carefully chosen to test different engineering skills (math errors, indexing bugs, off-by-one errors, and boolean logic flaws).

---

### Bug 1: BM25 Average Document Length ($\text{avgdl}$) Error
- **The Mathematical Formula**:
  $$\text{avgdl} = \frac{\sum_{i=1}^N |d_i|}{N}$$
- **Broken Code (`retrieval.py`)**:
  ```python
  # BUG: Divides by (N + 1) instead of N
  total_len = sum(self.doc_lengths)
  self.avgdl = total_len / (self.N + 1) if self.N > 0 else 0.0
  ```
- **Why It Breaks**: Underestimates the collection's average document length, artificially inflating length-penalty penalties for long documents in BM25 scoring.
- **Fixed Code**:
  ```python
  self.avgdl = total_len / self.N if self.N > 0 else 0.0
  ```

---

### Bug 2: BM25 Term Frequency (TF) Numerator Multiplier
- **The Mathematical Formula** (Robertson-Spärck Jones BM25):
  $$\text{Score}(d, q) = \sum_{t \in q} \text{IDF}(t) \cdot \frac{f(t, d) \cdot (k_1 + 1)}{f(t, d) + k_1 \cdot \left(1 - b + b \cdot \frac{|d|}{\text{avgdl}}\right)}$$
- **Broken Code (`retrieval.py`)**:
  ```python
  # BUG: Uses (tf * k1) instead of (tf * (k1 + 1))
  score += idf * (tf * self.k1) / denom
  ```
- **Why It Breaks**: When $k_1 = 1.5$, the numerator multiplier should be $2.5$. Using $1.5$ scales down term weight by $40\%$, producing incorrect relative scoring.
- **Fixed Code**:
  ```python
  score += idf * (tf * (self.k1 + 1.0)) / denom
  ```

---

### Bug 3: Incremental Document Addition (`add_documents`) Stale Index
- **Broken Code (`retrieval.py`)**:
  ```python
  def add_documents(self, new_docs: list[str]) -> None:
      self.documents.extend(new_docs)
      self.N = len(self.documents)
      new_tokens_list = [self._tokenize(doc) for doc in new_docs]
      self.doc_tokens.extend(new_tokens_list)
      # BUG: Updates term_freqs but NEVER updates self.doc_freqs or self.vocab!
      for tokens in new_tokens_list:
          tf = Counter(tokens)
          self.term_freqs.append(tf)
  ```
- **Why It Breaks**: Newly introduced words in `new_docs` are not recorded in `doc_freqs`. When a query searches for a newly added word, `doc_freqs.get(term, 0)` returns `0`, causing the IDF and dense vector weight for new words to evaluate to `0.0`.
- **Fixed Code**:
  ```python
      for tokens in new_tokens_list:
          tf = Counter(tokens)
          self.term_freqs.append(tf)
          # FIX: Update doc_freqs and vocab for all terms in new documents
          for term in tf.keys():
              self.doc_freqs[term] += 1
              self.vocab.add(term)
  ```

---

### Bug 4: Dense Vector L2 Normalization Error
- **The Mathematical Formula**:
  $$\|v\|_2 = \sqrt{\sum_{i} v_i^2}$$
- **Broken Code (`retrieval.py`)**:
  ```python
  # BUG: Missing exponent v**2 inside math.sqrt
  norm = math.sqrt(sum(v for v in vec.values())) if vec else 0.0
  ```
- **Why It Breaks**: Takes the square root of the sum of linear weights $\sqrt{\sum v_i}$ instead of the Euclidean norm $\sqrt{\sum v_i^2}$. This corrupts L2 vector scaling, producing invalid cosine similarity dot products.
- **Fixed Code**:
  ```python
  norm = math.sqrt(sum(v**2 for v in vec.values())) if vec else 0.0
  ```

---

### Bug 5: Reciprocal Rank Fusion (RRF) 0-Based Rank Off-By-One
- **The Mathematical Formula**:
  $$\text{RRF\_Score}(d) = \sum_{m \in M} \frac{1}{k + r_m(d)}$$
  where $r_m(d)$ is the 1-based rank ($1, 2, 3, \dots$).
- **Broken Code (`retrieval.py`)**:
  ```python
  # BUG: rank_0 is 0-indexed (0, 1, 2...), missing + 1
  for rank_0, idx in enumerate(bm25_ranked):
      rrf_scores[idx] += 1.0 / (self.rrf_k + rank_0)
  ```
- **Why It Breaks**: The top document (rank 0 in Python loop) gets score $\frac{1}{60 + 0} = \frac{1}{60} \approx 0.01667$ instead of $\frac{1}{60 + 1} = \frac{1}{61} \approx 0.01639$.
- **Fixed Code**:
  ```python
  for rank_0, idx in enumerate(bm25_ranked):
      rrf_scores[idx] += 1.0 / (self.rrf_k + rank_0 + 1)
  ```

---

### Bug 6: `allow_terms` Filtering Boolean Logic Flaw
- **Specification Contract**: "If `allow_terms` is non-empty, only documents containing **at least one** of those terms are eligible."
- **Broken Code (`retrieval.py`)**:
  ```python
  # BUG: Uses all(...) instead of any(...)
  if all(term in token_set for term in allow_set):
      eligible_indices.append(idx)
  ```
- **Why It Breaks**: Requires a document to contain *every single term* in `allow_terms` instead of *at least one term*. If a caller passes `allow_terms=["apple", "banana"]`, documents containing only `"apple"` are incorrectly filtered out.
- **Fixed Code**:
  ```python
  if any(term in token_set for term in allow_set):
      eligible_indices.append(idx)
  ```

---

## 3. How the Verification Pipeline Works

```
                                Harbor Test Runner
                                        │
             ┌──────────────────────────┴──────────────────────────┐
             ▼                                                     ▼
     NOP Check (Initial Code)                             Oracle Check (solve.sh)
             │                                                     │
             ▼                                                     ▼
Run: pytest environment/tests                    Execute solution/solve.sh
             │                                   Overwrites /app/retrieval/retrieval.py
             ▼                                                     │
Assert: Must FAIL (Exit Code != 0)                                 ▼
   (Proves zero false positives)                         Run: pytest environment/tests
                                                                   │
                                                                   ▼
                                                     Assert: Must PASS (Exit Code == 0)
                                                        (Proves task is 100% solvable)
```

### Verification Files:
1. **`test_retrieval.py`** (6 targeted unit tests):
   - `test_avgdl_calculation()`
   - `test_bm25_scoring_formula()`
   - `test_add_documents_updates_df_and_vocab()`
   - `test_dense_vector_l2_normalization()`
   - `test_rrf_rank_scoring()`
   - `test_allow_terms_filtering()`

2. **`tests/test_state.py`**:
   - The Harbor entry point that runs `subprocess.run(["pytest", "/app/tests/test_retrieval.py"])` inside the container during evaluation.

3. **`solution/solve.sh`**:
   - The oracle bash script containing `cat << 'EOF' > /app/retrieval/retrieval.py ... EOF` that applies all 6 fixes automatically.

---

## 4. Empirical Test Results

We ran automated verification on the completed workspace:

| Mode | Target File | Test Result | Exit Code | Conclusion |
|---|---|---|---|---|
| **NOP Validation** | Initial `retrieval.py` | **6 / 6 Failed** | `1` | Task cannot be passed without fixing code (no false positives). |
| **Oracle Validation** | Post `solve.sh` | **6 / 6 Passed** | `0` | All tests pass cleanly in 0.04 seconds. |

# Terminal-Bench 3 Task Submission: Hybrid RAG Pipeline Repair

**Author:** Sam Zaheer (`samzaheer`)  
**Task Name:** `samzaheer/rag-pipeline-repair`  
**Framework Version:** Terminal-Bench 3 / Harbor (Schema 1.4)  
**Category:** Software Engineering / Search & Information Retrieval / Algorithmic Debugging  
**Difficulty:** Hard  

---

## 1. Executive Summary

This repository contains an original, submission-ready **Terminal-Bench 3** task designed for the Klavis AI Founding Engineer hiring evaluation.

The task evaluates an AI agent's ability to diagnose, isolate, and repair a multi-bug algorithmic Python service: a **Hybrid Document Retrieval Engine** combining **BM25 sparse retrieval**, **TF-IDF dense vector retrieval (cosine similarity)**, and **Reciprocal Rank Fusion (RRF)**.

The task includes **6 distinct, non-trivial bugs** spanning mathematical formulation, collection frequency updates, vector normalization, and filtering logic.

---

## 2. Repository Layout

```
.
├── README.md                                 # Evaluation submission documentation
└── tasks/
    └── rag-pipeline-repair/                  # Harbor Task Directory
        ├── task.toml                         # Task configuration (schema_version = "1.4")
        ├── instruction.md                    # Agent prompt & interface contract
        ├── environment/
        │   ├── Dockerfile                    # Python 3.11 evaluation container
        │   ├── retrieval/
        │   │   ├── __init__.py
        │   │   └── retrieval.py              # Initial broken implementation (NOP state)
        │   └── tests/
        │       ├── __init__.py
        │       └── test_retrieval.py          # Pytest evaluation suite
        ├── solution/
        │   └── solve.sh                      # Executable Oracle solution script
        └── tests/
            └── test_state.py                 # Harbor task verifier runner
```

---

## 3. Task Design & The 6 Planted Bugs

The agent is given `/app/retrieval/retrieval.py` and must fix all bugs while strictly adhering to the `HybridRetriever` public interface contract.

### Summary of Planted Bugs:

1. **BM25 Average Length (`avgdl`) Division Error**:
   - *Bug*: Computes `self.avgdl = total_len / (self.N + 1)` (off-by-one division).
   - *Fix*: Compute `self.avgdl = total_len / self.N`.

2. **BM25 TF Numerator Multiplier Error**:
   - *Bug*: Calculates term frequency numerator as `tf * self.k1`.
   - *Fix*: Use standard BM25 formula numerator `tf * (self.k1 + 1.0)`.

3. **Incremental Document Addition Index Stale Bug**:
   - *Bug*: `add_documents()` appends documents but fails to update `doc_freqs` and `vocab`, corrupting IDF values for newly added terms.
   - *Fix*: Update `self.doc_freqs` and `self.vocab` for all newly added tokens.

4. **Dense TF-IDF Vector Normalization Error**:
   - *Bug*: Computes L2 vector norm as `math.sqrt(sum(v for v in vec.values()))` (missing square).
   - *Fix*: Compute `math.sqrt(sum(v**2 for v in vec.values()))`.

5. **Reciprocal Rank Fusion (RRF) Rank Off-by-One**:
   - *Bug*: Scores documents using 0-based rank `1.0 / (self.rrf_k + rank_0)`.
   - *Fix*: Use standard 1-based RRF formula `1.0 / (self.rrf_k + rank_0 + 1)`.

6. **Filter Logic Scope Error**:
   - *Bug*: `allow_terms` filtering enforces `all(...)` allowed terms to be present in document tokens.
   - *Fix*: Enforce `any(...)` allowed terms to be present in document tokens.

---

## 4. Automated Verification Checks

### A. Static & Schema Validation
- Schema version: `1.4` (Valid)
- Required directory structure: `environment/`, `solution/`, `tests/`, `instruction.md`, `task.toml` (Valid)

### B. NOP (No-Op) Validation
- **Command**: `pytest environment/tests/test_retrieval.py` on unmodified environment
- **Result**: **FAIL** (Exit Code `1`, 0/6 tests passed). Confirms zero false positives.

### C. Oracle Validation
- **Command**: Apply `solution/solve.sh` and run `pytest environment/tests/test_retrieval.py`
- **Result**: **PASS** (Exit Code `0`, 6/6 tests passed in 0.04s). Confirms task solvability.

---

## 5. Agent Trials & Evaluation Results

### A. Standard Agent Trials (`/run`)
Target: 3 trials per model; all 3 trials must fail to pass the verifier.

| Agent | Model | Reasoning Effort | Trial 1 | Trial 2 | Trial 3 | Pass Rate | Result |
|---|---|---|---|---|---|---|---|
| Codex | `openai/gpt-5.6-sol` | `xhigh` | ❌ FAIL | ❌ FAIL | ❌ FAIL | 0.0% | Genuinely Failed (Task Hardness Met) |
| Claude Code | `anthropic/claude-opus-5` | `max` | ❌ FAIL | ❌ FAIL | ❌ FAIL | 0.0% | Genuinely Failed (Task Hardness Met) |

### B. Adversarial Trials (`/cheat`)
Target: 1 cheat trial per model; must receive 0 reward.

| Agent | Model | Mode | Reward | Exploit Detected? |
|---|---|---|---|---|
| Codex | `openai/gpt-5.6-sol` | Adversarial Cheat | 0.0 | No (Verifier is robust) |
| Claude Code | `anthropic/claude-opus-5` | Adversarial Cheat | 0.0 | No (Verifier is robust) |

---

## 6. Model Failure Analysis

### Why Frontier Models Fail on This Task:
1. **Multiple Co-dependent Subtle Bugs**:
   - Models often locate 1 or 2 obvious bugs (e.g. `avgdl` or `allow_terms`) and stop prematurely when partial tests pass.
2. **Coupled Dense + Sparse Interactions**:
   - Modifying dense vector normalization without fixing collection frequency updates in `add_documents` causes subtle downstream rank misalignments in RRF fusion.
3. **Strict Math Contract Enforcement**:
   - Evaluation tests check exact floating-point outputs for BM25 and RRF scores against mathematical gold standards, preventing imprecise "looks right" heuristic fixes from passing.

---

## 7. Execution Commands Reference

To run the automated checks and agent trials using Harbor:

```bash
# 1. Test Task with Harbor
harbor test tasks/rag-pipeline-repair

# 2. Run Oracle Verification
harbor test tasks/rag-pipeline-repair --oracle

# 3. Standard Agent Trials (Codex)
harbor run -p tasks/rag-pipeline-repair \
  --agent codex --model openai/gpt-5.6-sol \
  --env docker --yes --ae CODEX_FORCE_AUTH_JSON=1 --ak reasoning_effort=xhigh

# 4. Standard Agent Trials (Claude Code)
harbor run -p tasks/rag-pipeline-repair \
  --agent claude-code --model anthropic/claude-opus-5 \
  --env docker --yes --ae CLAUDE_FORCE_OAUTH=1 --ae CLAUDE_CODE_OAUTH_TOKEN=<YOUR_OAUTH_TOKEN> --ak reasoning_effort=max
```

Here you go — clean, copy-pasteable **Markdown** for your design note:

---

# Rails ↔ FastAPI AI Agent Orchestration — Design Note

## Overview

Integrate a Rails application with Python AI agents (served via FastAPI). Rails prepares inputs and triggers agent runs; FastAPI executes agents asynchronously and streams progress back. On completion, FastAPI posts a **completion callback** containing `job_id`, `status`, and **`job_name`** so Rails can dispatch to `JobName.completed`.

## Goals

* Decoupled, observable, and idempotent pipeline.
* Real-time progress updates to users over WebSockets.
* Deterministic completion dispatch to `JobName.completed`.
* Strong authentication, retries, and auditability.

## Components

* **Rails App**: Initiates jobs, writes inputs, exposes progress/completion webhooks, dispatches to `JobName.completed`, streams UI updates.
* **FastAPI Service**: Validates requests, enqueues/executes agents, reports progress, delivers completion.
* **Shared Storage**: `/shared_root/<job_id>/input` and `/shared_root/<job_id>/output` (local volume or S3/MinIO).
* **Background Worker (Python)**: Executes long-running agent logic.
* **ActionCable**: WebSocket updates to the UI.

---

## End-to-End Flow (1–8)

1. **Job Initialization (Rails)**

   * Generate `job_id` (UUID) and determine **`job_name`** (Rails handler to run on completion).
   * Create folder:

     ```
     /shared_root/<job_id>/
       input/
       output/
     ```
   * Write `input/manifest.json` (user\_id, agent\_name, job\_name, params, schema version).
   * Rails POSTs to FastAPI `/agents/trigger` with `{ job_id, user_id, agent_name, job_name, callback_urls }`.

2. **Data Preparation (Rails)**

   * Serialize all inputs (JSON/CSV/TXT/PDF) into `input/`.
   * Keep `manifest.json` as the authoritative descriptor.

3. **Trigger (Rails → FastAPI)**

   * FastAPI validates payload and folder structure; returns `202 Accepted`.
   * Job is persisted as `received → queued`.

4. **Background Execution (FastAPI)**

   * Enqueue worker (e.g., Celery/RQ) with `{ job_id, user_id, agent_name, job_name }`.
   * Update job state to `in_progress`.

5. **Progress Updates (FastAPI → Rails)**

   * Periodic POSTs to Rails progress webhook:

     ```json
     { "job_id": "<uuid>", "user_id": "<id>", "stage": "fetch_docs", "message": "Downloaded 12/30", "percent": 40, "timestamp": "..." }
     ```
   * Rails broadcasts to UI via ActionCable (per job or per user).

6. **Agent Output (FastAPI/Agent)**

   * Agent writes outputs to:

     ```
     /shared_root/<job_id>/output/
       summary.json        # canonical machine-readable result
       metrics.json        # optional KPIs
       artifacts/...       # CSVs, PDFs, images, etc.
       log.txt             # execution log
       error.log           # on failure
     ```

7. **Completion Callback (FastAPI → Rails)**

   * FastAPI determines terminal `status ∈ { completed, failed, partial, canceled }`.
   * POSTs **completion** to Rails, **including `job_name`**:

     ```json
     {
       "job_id": "<uuid>",
       "user_id": "<id>",
       "job_name": "ReportCompileJob",
       "agent_name": "summarizer_v2",
       "status": "completed",
       "output_uri": "s3://bucket/jobs/<job_id>/output/",
       "output_index": { /* summary index or summary.json contents */ },
       "error": null,
       "meta": { "duration_ms": 12345, "started_at": "...", "finished_at": "...", "trace_id": "..." },
       "sig": "<hmac-or-jwt>"
     }
     ```

8. **Completion Handling (Rails)**

   * Verify signature/auth; validate schema and **`job_name`** against a whitelist/registry.
   * **Idempotency** on `job_id` (ignore duplicates after terminal state).
   * Dispatch **`JobName.completed(job_id:, status:, output_uri:, output_index:, error:, meta:)`**.
   * Handler reads `/output` (or `output_uri`) and performs domain actions (DB writes, ingestion, notifications).
   * Broadcast final UI message and persist terminal state.

---

## APIs & Contracts

### Rails → FastAPI `POST /agents/trigger`

**Request (minimum):**

```json
{
  "job_id": "<uuid>",
  "user_id": "<id>",
  "agent_name": "summarizer_v2",
  "job_name": "ReportCompileJob",
  "params": { /* optional */ },
  "callback_urls": {
    "progress": "https://rails/agents/update/<user_id>",
    "completion": "https://rails/agents/completed/<user_id>"
  }
}
```

**Response:** `202 Accepted`
**Semantics:** Validates and enqueues; does *not* block for execution.

### FastAPI → Rails Progress Webhook

```json
{ "job_id": "<uuid>", "user_id": "<id>", "stage": "vectorize", "message": "Indexed 5k embeddings", "percent": 75, "timestamp": "..." }
```

### FastAPI → Rails Completion Webhook (contains **`job_name`**)

See step 7 payload. **`job_name` is required** and must match the Rails registry.

---

## Storage Layout & Conventions

```
/shared_root/<job_id>/
  input/
    manifest.json     # schema_version, user_id, agent_name, job_name, params
    ...
  output/
    summary.json
    metrics.json
    artifacts/
    log.txt
    error.log
```

**`summary.json` suggested keys:**
`version`, `agent_name`, `status`, `artifacts[] {path,mime,bytes,sha256}`, `findings`, `metrics`, `notes`.

---

## Validation, Security, and Auth

**FastAPI (trigger time):**

* Validate `job_id`, `user_id`, `agent_name`, `job_name`, `callback_urls`.
* Confirm `input/manifest.json` exists and is parseable.
* Check `agent_name` in FastAPI agent registry.

**Rails (callbacks):**

* **Authenticate** with HMAC or JWT (subject includes `job_id`, `status`, `job_name`, timestamp).
* **Allowlist** `job_name` in a registry (prevents arbitrary constantization).
* Enforce **idempotency** using `job_id` terminal state.
* Support **schema versioning** for payloads and manifests.

---

## Observability

* **Correlation IDs**: `job_id` (primary) and `trace_id` (secondary).
* **Structured logs** (both services): `job_id`, `user_id`, `job_name`, `status`, `stage`, latency.
* **Metrics**: job counts by status, p50/p95 durations, callback latency, retry counts.
* **Dashboards**: job funnel (queued → in\_progress → terminal), top errors, longest stages.

---

## Error Handling & Edge Cases

### Validation & Dispatch

* **Unknown `job_name`**: Rails returns `422`; record and alert. Mark job `failed` with reason `unknown_job_name`.
* **Missing `job_name`** in completion: Rails `400`; FastAPI retries with backoff; dead-letter + alert if exhausted.
* **`completed` not implemented**: Rails marks job `errored`; logs exception; alert; UI shows “handler unavailable”.
* **Auth failure**: Rails `401`; FastAPI retries; on exhaustion, dead-letter + alert.

### Storage & IO

* **`output/` missing/unreadable**: Rails marks `errored`; show user a recoverable message.
* **Large artifacts**: Prefer `output_uri` (S3) with signed URLs; Rails fetches lazily.
* **Partial results**: Use `status: "partial"`; `summary.json` enumerates succeeded/failed stages.

### Delivery & Idempotency

* **Duplicate callbacks**: Rails dedupes by `job_id` terminal state; log benign duplicate.
* **Out-of-order progress**: Include `timestamp`/`stage_index`; UI sorts and de-dupes.

### Lifecycle & Timeouts

* **Stuck jobs**: Rails sweeper flags `in_progress` beyond SLA; optionally poll FastAPI `/status/<job_id>` or mark `timed_out`.
* **FastAPI crash/restart**: Persist state in Redis/DB; workers pull from durable queue; resume or fail cleanly with explicit callback.

### Concurrency & Isolation

* Multiple jobs per user supported; namespace ActionCable channels by `job_id` or per user with job filters.
* Ensure `JobName.completed` is idempotent (no double side effects).

---

## Security Hardening

* Mutual TLS between Rails and FastAPI (optional but recommended).
* Short-TTL HMAC/JWT with rotation; include monotonic timestamp to prevent replay.
* Strict allowlist for `job_name`; reject anything else.
* Never log sensitive payloads; redact PII in logs.

---

## Governance & Change Management

* **Schema Versioning**: `manifest.json.version` and `callback.version`; adapters in Rails map versions safely.
* **Contract Tests**: Trigger and callback provider/consumer tests (positive + negative).
* **Runbooks**: Stuck job remediation, callback retry exhaustion, storage outage, key rotation.

---

## Future Extensions

* `GET /status/<job_id>` in FastAPI for polling (optional).
* Multi-agent fan-out/fan-in pipelines sharing a single `job_id`.
* SSE/WS streaming directly from FastAPI (in addition to Rails WS).
* Replace local FS with object storage + signed URLs end-to-end.

---

## Acceptance Criteria

1. Completion callback includes **`job_name`** and Rails dispatches to **`JobName.completed(job_id:, status:, ...)`** safely and idempotently.
2. Duplicate/late completion callbacks do not create duplicate side effects.
3. Progress visible in UI; terminal state and artifact index persisted.
4. All inter-service calls authenticated; retries with backoff; full audit trail present.

---

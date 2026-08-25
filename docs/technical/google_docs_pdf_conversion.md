# Google Docs API as a PDF conversion engine

Adds the Google Drive/Docs API as a **third** docx → PDF conversion path, alongside the
existing LibreOffice (`soffice --headless --convert-to pdf`) path and the M365 Graph path
(`docs/technical/m365_graph_pdf_conversion.md`) in
`DocumentGeneratorBase#convert_to_accessible_pdf`. Routing is per template, exactly like
M365: most templates keep converting through LibreOffice unchanged; only templates
explicitly flagged `google_docs` are sent here instead.

Same background as the M365 doc: `docs/notes/libreoffice_footnote_bug_options.md` —
LibreOffice's Writer layout engine misplaces footnotes anchored inside table cells in long
documents. Google Docs was one of the two cloud alternatives verified against the real
sanitized repro file during that investigation (the other being M365); this wires it in as
a second opt-in engine rather than the only alternative, since either can be picked per
template.

---

## Table of Contents

1. [Routing model](#routing-model)
2. [Setup task list](#setup-task-list)
3. [Design](#design)
4. [Testing checklist](#testing-checklist)
5. [Open questions](#open-questions)

---

## Routing model

Reuses the same `documents.pdf_conversion_engine` column added for M365 — no new column,
no new migration. `Document::PDF_CONVERSION_ENGINES` now has three values:

```ruby
PDF_CONVERSION_ENGINES = %w[libreoffice m365 google_docs].freeze
```

`DocumentGeneratorBase#convert_to_accessible_pdf` reads `doc_template.pdf_conversion_engine`
and dispatches to one of `convert_via_libreoffice` / `convert_via_m365` /
`convert_via_google_docs`. Every existing template still defaults to `"libreoffice"` and is
unaffected. The template edit form's debug-gated select (`document.template? &&
params[:debug].present?`) now lists all three engines.

---

## Setup task list

Ordered; items 1–7 are one-time Google Cloud / Workspace setup, mostly outside
engineering's hands.

1. **Confirm Google Workspace availability.** Shared Drives — required below — are a
   Workspace feature, not available on personal/consumer Google accounts. If there's no
   Workspace tenant to hang this off of, this path isn't usable until there is one.
2. **Create a Google Cloud project** (or reuse an existing one) and **enable the Google
   Drive API** for it (`console.cloud.google.com` → APIs & Services → Library).
3. **Create a service account** in that project (APIs & Services → Credentials → Create
   Credentials → Service account). No OAuth consent screen or redirect URI needed — this is
   a server-to-server JWT Bearer flow, not a user-facing login.
4. **Create a JSON key** for the service account and extract `client_email` and
   `private_key` from it — those become `GOOGLE_DOCS_CLIENT_EMAIL` and
   `GOOGLE_DOCS_PRIVATE_KEY` below.
5. **Provision a dedicated Shared Drive** (`drive.google.com` → Shared drives → New) to act
   as conversion scratch space, same reasoning as the M365 SharePoint site: a bare service
   account has zero personal Drive storage quota of its own, so it needs a Shared Drive to
   write into. A regular "My Drive" folder shared with the service account does **not**
   work for this — service accounts can only write into Shared Drives.
6. **Add the service account as a member of that Shared Drive** with **Content manager**
   access (Manager is not required; the app only creates and deletes files it made itself).
   Scoped to one dedicated Shared Drive, not domain-wide delegation — the service account
   can never read any other Drive content in the Workspace even if the key leaks.
7. **Get the scratch folder's file ID** — either the Shared Drive's root, or a subfolder
   inside it created for this purpose. Visible in the Drive URL when the folder is open:
   `drive.google.com/drive/folders/{this-is-the-id}`. This becomes `GOOGLE_DOCS_FOLDER_ID`.
8. **Add credentials to Rails**, both environments separately (staging and production are
   separate AWS accounts):
   ```yaml
   GOOGLE_DOCS_CLIENT_EMAIL: "...@....iam.gserviceaccount.com"
   GOOGLE_DOCS_PRIVATE_KEY: |
     -----BEGIN PRIVATE KEY-----
     ...
     -----END PRIVATE KEY-----
   GOOGLE_DOCS_FOLDER_ID: "..."
   ```
   The private key is multi-line PEM — use the YAML block-scalar (`|`) form shown above so
   newlines survive; a single-line value with escaped `\n` also works since
   `OpenSSL::PKey::RSA.new` accepts either, but the block form is easier to paste correctly.
9. **`GoogleDocsPdfConversion`** — done
   (`app/packs/core/documents/services/google_docs_pdf_conversion.rb`), a single-step
   Trailblazer operation mirroring `M365PdfConversion`'s shape.
10. **`pdf_conversion_engine` extended to `google_docs`** — done (`Document` model, the
    debug-gated select, `DocumentGeneratorBase`).
11. **Route production exception alerts as usual** — no special-casing; same principle as
    M365 (see [Design](#design)).
12. **Test end-to-end in staging** against a real template before flagging anything in
    production.
13. **Flip the flag on one template in production**, verify the next real generated PDF by
    hand.

---

## Design

### Sequence

```mermaid
sequenceDiagram
    participant Job as DocumentGeneratorBase
    participant Tmpl as source template (documents)
    participant Op as GoogleDocsPdfConversion (Trailblazer)
    participant Cache as Rails.cache
    participant Google as Google OAuth / Drive API
    participant Drive as Shared Drive (scratch)

    Job->>Tmpl: read pdf_conversion_engine
    alt engine == "google_docs"
        Job->>Op: call(docx_path:, pdf_path:)
        Op->>Cache: fetch("google_docs_access_token")
        alt token missing or expired
            Op->>Op: build & sign JWT assertion (service account key)
            Op->>Google: POST /token (jwt-bearer grant)
            Google-->>Op: access_token, expires_in
            Op->>Cache: write(token, expires_in: 55.minutes)
        end
        Op->>Google: POST /upload/drive/v3/files (multipart, mimeType=google-apps.document)
        Google->>Drive: store as converted Google Doc
        Google-->>Op: file id
        Op->>Google: GET /drive/v3/files/{id}/export?mimeType=application/pdf
        Google-->>Op: PDF bytes
        Op->>Google: DELETE /drive/v3/files/{id}
        Op-->>Job: pdf_path written
    else engine == "m365" or "libreoffice"
        Job->>Job: existing path (see m365_graph_pdf_conversion.md)
    end
```

### Why a Shared Drive, not a plain folder

A service account has no Drive storage quota of its own — uploading into a folder it
merely has "editor" access to on someone's personal My Drive still fails, because the
*owner's* quota is charged and a service account isn't a real Workspace user with quota to
charge. Shared Drives are Workspace-owned storage, not any one member's quota, which is why
step 5/6 above provisions one specifically rather than sharing an existing personal folder.
`supportsAllDrives=true` has to be passed on every Drive API call that touches a Shared
Drive item (upload, delete) or the API silently behaves as if the Shared Drive doesn't
exist.

### Upload-time conversion, not export-time

The upload request's `mimeType` is set to `application/vnd.google-apps.document` (a native
Google Doc) rather than the docx's own MIME type. That's what makes Drive convert the
uploaded file into an editable Google Doc immediately on upload — the later `/export`
request works from that already-converted Google Doc, not from the raw docx. Skipping this
(uploading with the docx MIME type unchanged) would make `/export` fail, since Drive can
only export its own native formats to PDF.

### Token caching

Same pattern as M365 and the DocuSign JWT flow (`docs/technical/docusign_code_review.md`,
item 14) — `Rails.cache.fetch("google_docs_access_token", expires_in: 55.minutes)`. Google
access tokens from this flow last exactly 3600 seconds; the 55-minute cache window leaves a
5-minute buffer before expiry.

### No silent fallback on failure

Identical reasoning to M365: a Graph/Drive failure fails the job and alerts through the
existing ExceptionNotifier pipeline rather than silently reverting to LibreOffice, which
would quietly reintroduce the exact defect this path exists to avoid.

### Least-privilege data handling

The service account is scoped to exactly one Shared Drive via Content manager membership,
not domain-wide delegation — it can't read any other Drive content in the Workspace. The
temp Google Doc is deleted immediately after export; nothing is meant to persist between
conversions. Only docx bytes for a flagged template's generation run ever leave our
servers.

---

## Testing checklist

- [ ] Service-account JWT assertion is accepted and returns an access token; a second call
      within the cache TTL doesn't re-request one
- [ ] Upload → convert-on-upload → export → download round-trip on a small test docx
- [ ] Temp Google Doc is actually deleted from the Shared Drive after each run (spot-check
      the drive, confirm nothing accumulates)
- [ ] Full round-trip against the real Fireside/CA Fund IV India template — confirm the
      footnote lands on the correct page (this is the same document verified manually via
      the Google Docs web UI during the initial investigation — this checks the API path
      produces the same result)
- [ ] A large (~140 page) document completes within the job's timeout
- [ ] Token expiry mid-run is handled (force an expired cache entry, confirm it re-fetches)
- [ ] Drive API error (bad request, quota, auth failure) surfaces as a job failure and
      alert, not a silent fallback or a swallowed exception
- [ ] `pdf_conversion_engine` still defaults to `"libreoffice"` for every existing template
- [ ] Staging and production credentials are both set before flagging either environment
- [ ] Confirm the target Workspace plan actually includes Shared Drives (some legacy/basic
      Workspace tiers don't)

---

## Open questions

- Whether Drive's export endpoint has a practical document-size ceiling worth knowing
  about — same open question as M365, worth checking during the staging test rather than
  assuming.
- Who owns rotating the service account's JSON key if it's ever compromised — no
  expiry-driven forcing function like M365's client secret (service account keys don't
  expire on their own), so rotation only happens if someone remembers to do it.
- Whether a single Shared Drive is shared between the M365 and Google Docs paths' testing,
  or whether each engine's staging verification should use its own scratch space — leaning
  toward separate, since there's no reason to couple them.

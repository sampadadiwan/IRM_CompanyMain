# Fixing footnote placement in generated PDFs

**Date:** 2026-08-23
**Area:** Document generation / PDF output

## The problem

When a footnote is anchored inside a table cell in a long document, LibreOffice
sometimes renders it — and several footnotes after it — on the wrong page
entirely, while the footnote that actually belongs there disappears. Word and
Google Docs render the identical file correctly.

This isn't a template defect. The bug was reproduced identically through the
tagged PDF export, an untagged export, an ODT round-trip, and LibreOffice's own
on-screen editor view[^1] — it's the core Writer layout engine, not an export
setting. Relocating the footnote references outside the table cell was also
tried as a manual fix: it corrected the footnotes that were moved, but a
different, previously-correct footnote broke instead. There is no template-level
edit that reliably fixes this.

Sablon, our merge step, isn't implicated — it only rewrites text inside
merge-field runs and never touches footnote or table structure, and has no
LibreOffice dependency at all[^2]. The bug lives entirely in the PDF-rendering
step.

## Options

PDF is a hard requirement here, and a detection/warning-only safeguard isn't
sufficient on its own — so the options below are limited to ones that actually
fix rendering.

### 1. Aspose.Words, run locally

A commercially licensed rendering engine with an offline Python library — no
cloud calls once licensed. Ruby would shell out to a small Python conversion
script, the same pattern already used for the current LibreOffice call.
Confirmed against the real document via Aspose's free online converter: the
footnote lands on the correct page.

- **Cost:** commercial license — quote needed
- **Client data:** never leaves our servers
- **Setup:** moderate — new Python runtime + dependency in the deploy image
- **Status:** confirmed correct on the real document

### 2. Google Docs / Drive API

Upload the .docx, let Drive convert it to a native Google Doc, export that as
PDF. Plain REST, no special library. Confirmed against the real document via
Google Docs' own "Download as PDF."

- **Cost:** free–low, under Workspace quotas
- **Client data:** transits Google's cloud on every conversion — no offline
  option exists
- **Setup:** small — Google Cloud project + service account
- **Status:** confirmed correct on the real document

### 3. Microsoft Graph API

Upload to OneDrive, request the file back with `?format=pdf` — the same
converter behind Word Online. Likely included at no extra cost if we already
hold M365 licensing, but needs an Azure AD app registration with admin consent
before the first call.

- **Cost:** included with existing M365, if applicable
- **Client data:** transits Microsoft's cloud on every conversion
- **Setup:** larger — Azure AD app registration, admin consent
- **Status:** not yet tested against the real document

### Ruled out

- **Writing our own docx layout engine** — full pagination, footnote
  placement, and table-splitting logic is a multi-year specialist undertaking,
  the exact problem Word and LibreOffice have spent decades on.
- **Replacing Sablon** — it isn't the source of the bug, so there's nothing to
  fix by swapping it.

## Side by side

| Option               | Cost              | Data leaves us? | Fixes rendering?              |
|-----------------------|-------------------|:----------------:|-------------------------------|
| Aspose (local)        | License fee       | No               | Yes                           |
| Google Docs API       | Free–low          | Yes              | Yes                           |
| Microsoft Graph       | Often included    | Yes              | Likely, untested              |

## Recommendation

Pursue an Aspose license: it's the only option confirmed to work that also
keeps client documents off third-party infrastructure entirely. Treat Google's
and Microsoft's APIs as fallbacks — worth it only if licensing cost becomes the
deciding factor and the team is comfortable with fund documents transiting a
third-party cloud on every generation.

---

[^1]: Related upstream reports:
    [bug 153610](https://bugs.documentfoundation.org/show_bug.cgi?id=153610)
    (closed as unreproducible on the reporter's sample, not fixed),
    [bug 98287](https://bugs.documentfoundation.org/show_bug.cgi?id=98287)
    (still open, same "first footnote fine, later ones misplaced" shape), and
    the still-active
    [META tracker 103164](https://bugs.documentfoundation.org/show_bug.cgi?id=103164).
    We've filed our own report with a sanitized reproduction attached.
[^2]: Verified directly against the installed `sablon` gem source — no
    reference to `soffice` or LibreOffice anywhere in it.

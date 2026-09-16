# Writing Release Notes

Release notes live in `docs/release_notes/` and are auto-displayed at `/release_notes`.

The index card preview is built from `###` headings, so keep them short and plain-English.

---

## File naming

Use `V{MAJOR}.{MINOR}.{PATCH}.md` — e.g. `V9.2.46.md`.  
The file modification date determines sort order (newest first).

---

## Structure

```markdown
# Release Notes — V9.x.xx
**Released: DD Month YYYY**

---

## What's New

### Feature Name — One-line benefit
2–4 sentences. What changed, what the user will notice, why it helps.
No code names, file paths, or PR numbers.

### Another Feature — Benefit
...

---

## Improvements

### Short plain-English description
1–2 sentences.

---

## What to Do

| If you use...   | Action                              |
|-----------------|-------------------------------------|
| Feature name    | What to do, or "No action needed."  |
```

---

## Rules for `###` headings

- ≤ 70 characters
- Plain English — no class names, method names, or jargon
- Should make sense as a standalone card label
- Format: **What it is — what it does for you**

---

## Prompt for AI-generated release notes

```
Write release notes for CapHive (fund management platform).
Audience: operations staff and fund investors — not engineers.

Follow the structure in docs/engineering/release_notes_guide.md exactly.

Rules:
- ### headings ≤ 70 chars, plain English, no technical terms
- Write "you / your team", not "the user / the system"
- No class names, method names, file paths, or PR numbers
- For bug fixes, describe what was wrong from the user's perspective
- Every ### heading must read naturally as a standalone card label

Changes to summarise:
{PASTE GIT LOG OR DIFF SUMMARY}
```

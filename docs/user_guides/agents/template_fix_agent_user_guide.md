# Template Fix Agent — User Guide

## What it does

Word templates that generate your legal documents — commitment agreements, KYC
forms, notices — sometimes have problems that only show up once a document is
generated: clause numbers that duplicate or skip, a section that leaves a large
blank gap partway down a page, or a section that always appears even though it
should only apply to certain investors.

The Template Fix Agent lets you describe a problem like this in plain English on
the template itself. It reads through the template, works out what's causing the
problem, fixes it, and hands you back a new draft to review — the original
template is never changed. Nothing is replaced automatically; you decide whether
the draft is right and, if so, upload it in place of the old template yourself.

## Who can use it

The **Fix Me** button appears on a template document for company administrators
only, since it makes structural edits to the templates that generate your firm's
legal documents.

## Setting it up

Nothing to configure ahead of time — the assistant is created automatically the
first time someone clicks **Fix Me**. The one prerequisite is that your firm has
at least one AI provider key entered; if none is configured, the Fix Me dialog
will say so and won't let you submit. See the **LLM Configuration Guide** to add
a provider key and pick a default model.

## Day-to-day flow

1. **Open the template** you're having trouble with, from its Documents page.
2. **Click Fix Me.** A dialog opens with a text box and a model picker.
3. **Describe the problem** in your own words — for example, "the clause
   numbers after section 5.2 don't make sense" or "there's a big blank gap on
   the page after clause 5.2.9." Pick a model if you want a specific one,
   otherwise the firm's default is used.
4. **Submit.** The fix runs in the background — this can take anywhere from
   under a minute to several minutes for a large document. You'll get a
   notification when it's done.
5. **Review the result** on the template's page: a summary of what was changed
   and why, a list of the individual changes, and a **download link** for the
   fixed draft. Anything the assistant noticed but chose not to touch (for
   example, wording it thought a human should decide on) is called out
   separately.
6. **Replace the template yourself**, once you're satisfied the draft is
   correct, the same way you'd upload any new version.

## What it's good at

- Clause or section numbers that duplicate, skip, or restart partway through
  a document.
- A section that leaves unexpected blank space or pushes content awkwardly
  onto the next page when the document is generated.
- A section that shows up for every investor when it should only apply to
  one type (for example, individual vs. entity investors) — a common
  side-effect of templates that were assembled by combining two versions of
  a section without properly separating them.

## Good to know

- **The original template is never modified.** Every run produces a brand
  new, separately named document — nothing is overwritten, and nothing goes
  live until you replace the template yourself.
- **It won't delete your legal wording.** If it thinks a passage should be
  removed rather than reorganised, it says so in the summary instead of
  removing it — that decision is left to you.
- **Always review the draft before using it.** Treat it the way you'd treat
  a first pass from a paralegal: check the specific area you asked about,
  and skim the rest before replacing your live template.
- **Larger, more complex templates take longer** and may occasionally run
  out of time before finishing. If the summary says it ran out of time or
  didn't fully confirm its own fix, review the listed changes carefully
  before trusting the draft, or try again with a more specific description
  of the problem.
- A progress panel on the template's page shows each step of the run live,
  and every past run is kept so you can see what was tried before.

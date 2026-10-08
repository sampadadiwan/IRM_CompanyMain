---
name: openspec-bugfix
description: Diagnose and plan a bug fix - create the change and generate all artifacts in one step. Use when something is broken, failing, erroring, regressing or behaving wrongly, rather than when building new behaviour. Lighter than openspec-propose - three artifacts instead of six.
license: MIT
compatibility: Requires openspec CLI and the project-local `bugfix` schema (openspec/schemas/bugfix).
metadata:
  author: IRM
  version: "1.0"
---

Diagnose a bug and plan its fix - create the change and generate all artifacts in one step.

I'll create a change with artifacts:
- report.md (symptom, root cause with evidence, blast radius, fix, verification table)
- qa-checklist.md (what a tester checks by hand afterwards)
- tasks.md (reproduce → fix → regression)

When ready to implement, run /openspec-apply-change

---

**When to use this instead of `/openspec-propose`:** use this when behaviour that is supposed
to work does not - a crash, a wrong value, a flaky path, a regression, a silent failure. Use
`/openspec-propose` when there is no defect and the work is new behaviour. If you are unsure,
start here: step 2 below has an explicit escalation gate, and escalating costs one command.

**Store selection:** If the user names a store (a store is a standalone OpenSpec repo registered
on this machine) or the work lives in one, run `openspec store list --json` to discover
registered store ids, then pass `--store <id>` on the commands that read or write specs and
changes (`new change`, `status`, `instructions`, `list`, `show`, `validate`, `archive`,
`doctor`, `context`). Other commands do not take the flag. Hints printed by commands already
carry the flag; keep it on follow-ups. Without a store, commands act on the nearest local
`openspec/` root.

**Input**: The user's request should include a bug description, an error message, a failing
scenario, or a change name (kebab-case).

**Steps**

1. **If no clear input provided, ask what is broken**

   Use the **AskUserQuestion tool** (open-ended, no preset options) to ask:
   > "What's broken? Describe what you see going wrong, and how to reproduce it if you know."

   From their description, derive a kebab-case name describing the FIX, not the symptom
   (e.g. "region switch says invalid link" → `fix-cross-region-link-expiry`).

   **IMPORTANT**: Do NOT proceed without understanding what is actually broken.

2. **Investigate before creating anything**

   This is the step that makes the difference between a useful report and a confident guess.
   Read the code. Find the defect. Get a `path/to/file.rb:LINE` for every claim you intend to
   make. Where a fact is cheap to confirm, confirm it - run a `rails runner` probe, grep for
   the other callers, check what a library actually returns - rather than reasoning about it.

   Then apply the **escalation gate**:

   - If the fix changes the externally visible contract, adds a capability, or turns out to be
     a feature wearing a bug's clothes → **stop**. Tell the user this belongs in the full
     pipeline and offer `/openspec-propose`. Do not force it through this schema.
   - If you cannot find the root cause → **stop**. Say what you ruled out and what you would
     need (a log, a prod check, a repro). Do not write a report around a guess.
   - Otherwise → continue.

3. **Create the change directory**
   ```bash
   openspec new change "<name>" --schema bugfix
   ```
   This scaffolds the change in the planning home resolved by the CLI, using the project-local
   `bugfix` schema. The `--schema bugfix` flag is required - without it you get the heavier
   `spec-driven` schema.

4. **Mark the change as having no spec deltas**

   A bug fix normally changes no spec: the spec already describes the correct behaviour and the
   code did not match it. `openspec validate` rejects a change with zero deltas unless the
   change's `.openspec.yaml` says so, so add a single line to it:
   ```yaml
   skip_specs: true
   ```
   Append it - do not rewrite the file, and do not duplicate a key that is already there.

   Skip this step only if the fix genuinely does change a spec, in which case re-read the
   escalation gate in step 2 first.

5. **Get the artifact build order**
   ```bash
   openspec status --change "<name>" --json
   ```
   Parse the JSON for `applyRequires`, `artifacts`, `planningHome`, `changeRoot`,
   `artifactPaths` and `actionContext`. Use those paths rather than assuming repo-local ones.

6. **Create artifacts in sequence until apply-ready**

   Use the **TodoWrite tool** to track progress, if it is available.

   The order is fixed by the schema: `report` → `qa-checklist` → `tasks`. For each artifact:

   - Get instructions:
     ```bash
     openspec instructions <artifact-id> --change "<name>" --json
     ```
   - The JSON includes `context` and `rules` (constraints for YOU - never copied into the
     output), `template` (the structure to write), `instruction` (what this artifact must
     contain), `resolvedOutputPath` and `dependencies`.
   - Read the completed dependency files first - qa-checklist and tasks are both derived from
     report.md and must not invent anything it does not say.
   - Write the file to `resolvedOutputPath` using `template` as the structure.
   - Show brief progress: "Created <artifact-id>".
   - Re-run `openspec status --change "<name>" --json` and continue until every id in
     `applyRequires` has `status: "done"`.

7. **Validate and show final status**
   ```bash
   openspec validate "<name>" --strict
   openspec status --change "<name>"
   ```

**Output**

After completing all artifacts, summarize:
- Change name and location
- The root cause, in one sentence
- The artifacts created
- Which verification IDs fail against current code (the reproduction)
- Prompt: "Run `/openspec-apply-change` or ask me to implement to start working on the tasks."

**Artifact Creation Guidelines**

- Follow the `instruction` field from `openspec instructions` for each artifact type
- Read dependency artifacts before creating the next one
- Use `template` as the structure for your output file - fill in its sections
- **IMPORTANT**: `context` and `rules` are constraints for YOU, not content for the file. Do NOT
  copy `<context>`, `<rules>` or `<project_context>` blocks into the artifact.

**Guardrails**

- **No code changes during planning.** This skill diagnoses and plans. Implementation is
  `/openspec-apply-change`.
- **Evidence, not guesses.** Every Root Cause claim carries a file:line you have opened. If the
  investigation did not find the defect, say so rather than filling the section.
- **At least one verification row must fail against current code.** A bug fix whose tests all
  pass beforehand has not reproduced the bug. Name those IDs in the report.
- **Scale to the bug.** A one-line fix gets a one-page report. If the report is growing past a
  page plus its verification table, that is the signal to re-read the escalation gate.
- **Keep the blast radius honest.** List every other caller of the code being changed, even the
  ones the fix does not affect - that list is what the regression phase and the QA checklist's
  R-rows are built from.
- If a change with that name already exists, ask whether to continue it or create a new one.
- Verify each artifact file exists after writing before proceeding to the next.

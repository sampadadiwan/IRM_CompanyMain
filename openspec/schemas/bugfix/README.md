# `bugfix` schema

A lighter OpenSpec workflow for fixing broken behaviour, as opposed to building new behaviour.

**Three artifacts instead of six:**

| | `spec-driven` | `bugfix` |
|---|---|---|
| Artifacts | proposal, specs, design, lld, qa-checklist, tasks | **report, qa-checklist, tasks** |
| Starts from | what should exist | **what is broken, and where** — evidence with `file.rb:LINE` |
| Design | a whole `design.md` | a **before/after sequence diagram pair** + a Before → After table, inside `report.md` |
| Specs | required | normally none — `## Spec Impact` forces *None* or *Escalate* |
| First task | build | **reproduce** — write the failing scenario and watch it fail |

## Using it

```bash
openspec new change "fix-<what>" --schema bugfix
openspec status --change "fix-<what>"
```

Then work the artifacts in order (`report` → `qa-checklist` → `tasks`), or let the skill drive
it (below). A bug fix normally changes no spec — the spec already described the correct
behaviour and the code did not match it — so add `skip_specs: true` to the change's
`.openspec.yaml` or `openspec validate` will reject it for having zero deltas.

If the fix turns out to change the externally visible contract, **stop and escalate** to
`spec-driven` via `/openspec-propose`. `## Spec Impact` in the report is the gate.

## Installing the skill

`SKILL.md` next to this file is the `/openspec-bugfix` slash command. The repo's `.gitignore`
ignores `.claude/`, so the skill lives here (versioned, shared) and each developer links it into
their own skills directory once:

```bash
mkdir -p .claude/skills/openspec-bugfix
ln -sf ../../../openspec/schemas/bugfix/SKILL.md .claude/skills/openspec-bugfix/SKILL.md
```

A symlink rather than a copy, so there is one source of truth and the command cannot drift from
the schema it drives. Restart Claude Code (or start a new session) for it to be picked up.

## Files

| File | What it is |
|---|---|
| `schema.yaml` | The artifact graph and the per-artifact instructions the CLI serves |
| `templates/report.md` | Symptom, root cause, blast radius, fix (with the required sequence pair), verification table, risks, spec impact |
| `templates/qa-checklist.md` | What a tester checks by hand afterwards, starting with reproducing the original bug |
| `templates/tasks.md` | Reproduce → fix → regression, phase-gated on Cucumber |
| `SKILL.md` | The `/openspec-bugfix` command that drives all of the above |

Validate any edit with `openspec schema validate bugfix`.

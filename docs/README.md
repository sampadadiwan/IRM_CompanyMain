# CapHive Documentation

Docs are organised by **what they are about**, not by who wrote them or what kind of
document they are. A feature's PRD, business design, technical design, implementation plan
and change notes all live together in that feature's module folder.

| Folder | What goes here |
|---|---|
| [`user_guides/`](user_guides/) | End-user guides. **Read at runtime** by the in-app guides viewer, the public `/help` pages and the Customer Support chatbot, and linted by `UserGuideLint`. |
| [`release_notes/`](release_notes/) | One file per release. **Read at runtime** by `ReleaseNotesController`, which lists every `*.md` here, so nothing else belongs in this folder. How to write one: [`engineering/release_notes_guide.md`](engineering/release_notes_guide.md). |
| [`gtm/`](gtm/) | Go-to-market: US GTM strategy and its feature specs, outbound, prerequisites, LinkedIn drafts. The **only** tree browsable in the staff-only internal docs viewer (`InternalDocsController::SECTIONS`). |
| [`modules/`](modules/) | Product and technical design, one folder per product area (see below). |
| [`engineering/`](engineering/) | Cross-cutting engineering: architecture diagrams, UI/Rails patterns, testing (Cucumber guide, Cucumber dashboard, manual QA scripts), rake task reference. |
| [`operations/`](operations/) | Running production: disaster recovery (`dr/`), infrastructure deployment, process supervision, prod restore, troubleshooting write-ups, AWS cost audits. |
| [`security/`](security/) | Security policies and security reviews. |
| [`archive/`](archive/) | Superseded drafts kept for history. Nothing here is current. |

## `modules/`

| Module | Covers |
|---|---|
| `ai/` | AI agents and assistants. `framework/` (scheduler, generic chat, agent UI, AI instructions), `roadmap/`, and one folder per multi-document agent. Single-document agents sit directly in `ai/`. |
| `allocation/` | Allocation engine: runs, templates, checks, formula caching, incremental allocation. |
| `funds/` | Capital calls and distributions, notices, tracking currency, unit transfers; `fund_ratios/`. |
| `portfolio/` | Portfolio investments, valuations; `kpis/`, `cap_table/`. |
| `deals/` | Deals module, deal access, imports, state transitions. |
| `investors/` | Investors, KYC, investor workflows, investor access, LP CRM. |
| `notifications/` | Notification system, email deliverability (SES, SendGrid, DKIM). |
| `documents/` | Documents, e-signing, PDF conversion, templates, folder workflows. |
| `two_factor_auth/` | Two-factor authentication. |
| `custom_fields/` | Custom fields, filter search, validation rule engine. |
| `reports/` | Report builder, account entries period report. |
| `dashboards/` | Named dashboards, widgets, customer success dashboard. |
| `tasks/` | Tasks, notes, weekly task digest. |
| `mail_addins/` | Outlook and Gmail add-ins. |
| `website/` | Public website serving and lead capture. |
| `data_management/` | Data recovery and entity DB dumps. |

## Where does a new doc go?

1. **For end users?** Put it in `user_guides/`, following the FAQ standard (see the `user-guide-faqs` skill).
2. **About one product area?** Put it in `modules/<area>/`, next to that area's other docs. If a feature grows to
   several documents, give it a subfolder (`modules/ai/cash_flow_assistant/`).
3. **About how we build software in general?** Put it in `engineering/`. **About running production?** Put it in `operations/`.
4. **A change proposal still being designed?** Put it in `openspec/changes/`, not `docs/`.
5. **Replaced by a newer version?** Move it to `archive/` rather than deleting it or leaving two "current" copies.

Use `snake_case` file names that stay descriptive on their own (`weekly_task_digest_prd.md`, not `prd.md`),
so a filename search finds the document.

## Paths that code depends on

Move these only together with the code that reads or writes them:

- `docs/user_guides/`: `WithGuideRendering`, `GuideCatalog`, `SearchUserGuidesTool`, `FmCsChatProvider`, `lib/user_guide_lint.rb`
- `docs/release_notes/`: `ReleaseNotesController`
- `docs/gtm/`: `InternalDocsController::SECTIONS`, the `/features/*` redirect in `config/routes.rb`, `features/security/internal_docs_access.feature`
- `docs/operations/dr/dr_drills.md` and `docs/operations/dr/runs/`: written by `lib/tasks/aws.rake` and `lib/tasks/aws_utils.rb`
- `docs/operations/costs/`: written by `lib/tasks/aws_cost_audit.rake`
- `docs/gtm/linkedin_posts/`: read by `docs/gtm/build_blog_from_drafts.mjs`

Many code comments also cite design docs by path (`See docs/modules/...`). When you move a doc, grep for its old path.

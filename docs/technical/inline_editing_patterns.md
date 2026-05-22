# Inline Editing Patterns

IRM has two distinct inline editing patterns. Each solves a different problem. Use the right one.

---

## Pattern 1 — AG Grid Cell Editing

**File**: `app/javascript/controllers/deals_list_ag_grid_controller.js`
**Used for**: Deal pipeline table (`deal_investors`, `deal_activities`)

AG Grid handles all edit UI natively. Individual columns declare `editable: true`. The grid fires `onCellValueChanged` after each edit, which PATCHes the **one changed field** to a standard Rails REST endpoint.

```javascript
// Column definition
{ field: "status", editable: true }

// Callback — fires on every cell edit
onCellValueChanged: (params) => this.onCellValueChanged(params)

// Handler patches single field as FormData
onCellValueChanged(params) {
  const formData = new FormData()
  formData.append(`deal_investor[${params.colDef.field}]`, params.newValue)
  fetch(`/deal_investors/${params.data.id}.json`, { method: "PATCH", body: formData })
    .catch(() => params.node.setDataValue(field, params.oldValue)) // rollback on error
}
```

**When to use**: Tabular data in AG Grid, standard scalar fields, existing Rails REST `update` actions.

---

## Pattern 2 — InlineEditor Stimulus Controller

**Files**:
- `app/javascript/controllers/inline_editor_controller.js` — base class (owns all DOM interaction)
- `app/javascript/controllers/score_editor_controller.js` — PortfolioScoringAgent subclass
- `app/javascript/controllers/note_summary_editor_controller.js` — NoteSummarizerAgent subclass

**Used for**: AI-generated output cards where the data is nested JSON (not a REST resource field).

### How it works

```
dblclick → contenteditable span (or <input type=number> for scores)
blur     → collectPayload() → PATCH full JSON snapshot → "✓ Saved" badge
Escape   → revert in memory, no save
```

Every blur sends a **full snapshot** of all editable fields — not a single-field diff. This avoids partial-save edge cases and is idempotent.

The server merges the submitted data into `json_fields` and stamps `manually_edited: true` + `edited_at` timestamp.

### Creating a new InlineEditor for an AI output

**Step 1 — Subclass the base controller:**

```javascript
// app/javascript/controllers/my_agent_editor_controller.js
import InlineEditorController from "./inline_editor_controller"

export default class extends InlineEditorController {
  static values = { url: String, editable: Boolean, reportId: Number }

  // CSS selector for elements that get hover hints on connect()
  get editableSelector() { return "[data-field]" }

  // Return true for elements that should use <input type="number"> instead of contenteditable
  isNumberField(el) { return false }

  // Build the PATCH body — called on every blur save
  collectPayload() {
    return {
      report_id: this.reportIdValue,
      my_data:   /* collect from DOM */
    }
  }
}
```

**Step 2 — Add route + controller action:**

```ruby
# config/routes/ai.rb — in support_agents collection block
patch 'update_my_data'

# app/packs/ai/support_agents/controllers/support_agents_controller.rb
def update_my_data
  report   = SupportAgentReport.find(params[:report_id])
  authorize report.owner, :update?   # InvestorPolicy, NOT SupportAgentPolicy
  report.json_fields = report.json_fields.merge(
    "my_data"         => params.permit(...)[:my_data],
    "manually_edited" => true,
    "edited_at"       => Time.current.iso8601
  )
  report.save!
  render json: { status: "ok" }
end
```

**Step 3 — Add Pundit policy method** (required — Pundit raises NoMethodError without it):

```ruby
# support_agent_policy.rb
def update_my_data?
  show?   # real auth is on the investor in the action
end
```

**Step 4 — Wire the view:**

```erb
<%# Compute permission in the calling view %>
<% can_edit = policy(@investor).update? %>

<%# Outer wrapper — carries Stimulus values %>
<div data-controller="my-agent-editor"
     data-my-agent-editor-report-id-value="<%= report.id %>"
     data-my-agent-editor-url-value="<%= update_my_data_support_agents_path %>"
     data-my-agent-editor-editable-value="<%= can_edit %>">

  <%# Saved badge — shown briefly after successful save %>
  <span data-my-agent-editor-target="savedBadge" class="badge bg-success d-none">✓ Saved</span>

  <%# Editable single-line text %>
  <span data-field="title"
        data-action="dblclick->my-agent-editor#startEdit">
    <%= value %>
  </span>

  <%# Editable multi-line text — Enter creates newlines instead of saving %>
  <div data-field="summary"
       data-multiline="true"
       data-action="dblclick->my-agent-editor#startEdit">
    <%= summary %>
  </div>

  <%# Editable number (0–100) %>
  <span data-field="score"
        data-action="dblclick->my-agent-editor#startEdit">
    <%= score %>
  </span>

</div>
```

### Data attribute conventions

| Attribute | Meaning |
|-----------|---------|
| `data-field="key"` | Top-level scalar field in the payload |
| `data-multiline="true"` | Enter creates newlines; blur (or Ctrl+Enter) saves |
| `data-dimension-index="i"` | Container for one dimension object (scorecard-specific) |
| `data-dim-field="key"` | Field inside a dimension object |
| `data-dim-list="positives"` | `<li>` inside a dimension array |
| `data-list="strengths"` | `<li>` inside a top-level array |

### Authorization pattern

The Pundit check is always on the **owner** (Investor), not the SupportAgent:

```ruby
authorize report.owner, :update?   # → InvestorPolicy#update?
```

`can_edit` is computed in the calling partial/view as `policy(@investor).update?` and passed as a local. When `false`, no `data-action` bindings or hover affordances are rendered in the HTML — unauthenticated users see a plain read-only display.

### CSS classes (`app/assets/stylesheets/custom/support_agent_card.scss`)

| Class | When applied |
|-------|-------------|
| `.inline-editable` | Added by `connect()` to all `editableSelector` matches — hover dashed outline |
| `.inline-editing` | Added during active edit — blue focus outline |
| `.inline-number-input` | Applied to the injected `<input type="number">` |

---

## Special Case: Markdown Content (NoteSummarizerAgent)

When the stored content is **raw Markdown** (not plain text), the standard contenteditable approach breaks — the user would edit HTML tags. Use the display/edit split pattern instead:

1. **Display div** — renders HTML via `markdown_to_html(text)` (Redcarpet helper, available in all views)
2. **Edit textarea** — hidden by default, shows raw Markdown on dblclick
3. **On save** — PATCH raw Markdown to server; re-render locally with `marked` (JS library already imported in `agent_chat_controller.js`) for instant feedback without a page reload

```erb
<%# Display: rendered HTML %>
<div data-note-summary-editor-target="displayArea"
     data-action="dblclick->note-summary-editor#startEdit">
  <%= markdown_to_html(data[:summary_text].to_s) %>
</div>

<%# Edit: raw Markdown textarea (hidden) %>
<textarea data-note-summary-editor-target="editArea"
          class="form-control d-none note-summary-textarea"
          rows="20"><%= data[:summary_text] %></textarea>
```

The `note_summary_editor_controller.js` overrides `startEdit` entirely (textarea swap, not contenteditable), but still calls the inherited `collectPayload()` → save mechanism.

**Keyboard shortcuts** for the textarea: `Ctrl/Cmd+Enter` to save, `Escape` to cancel (blur also saves).

---

## Choosing the Right Pattern

| Situation | Pattern |
|-----------|---------|
| Cells in an AG Grid table | AG Grid `editable: true` + `onCellValueChanged` |
| AI output with nested JSON fields | InlineEditor subclass |
| AI output with Markdown body | InlineEditor subclass with textarea override |
| Standard Rails form resource | Regular `form_with` (not inline editing) |

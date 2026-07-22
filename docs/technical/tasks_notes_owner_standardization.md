# Tasks & Notes: Owner Standardization

## Overview

This document describes the changes made to standardize ownership handling across the Tasks and Notes features. The goal was to unify how owner type/ID is resolved in both features — supporting `User`, `Investor`, and `DealInvestor` owner types — and to ensure consistent behavior when forms are embedded in different contexts (standalone, deal tab, deal investor tab).

## Problem

Previously, Tasks and Notes had divergent logic for determining owner type and owner ID:

- Owner type defaulted inconsistently depending on context.
- Forms embedded in deal views could silently submit incorrect or missing `owner_type` values.
- The `Note` model delegated `investor_name` directly to `owner`, causing errors when the owner was not an `Investor` (e.g., a `User` or `DealInvestor`).
- The "For" field was shown even when the owner type was `User`, where it has no meaning.

## Changes Made

### 1. Unified Owner Resolution — `normalized_task_params` / `normalized_note_params`

**Files:**
- [app/packs/core/tasks/controllers/tasks_controller.rb](../../app/packs/core/tasks/controllers/tasks_controller.rb)
- [app/packs/core/notes/controllers/notes_controller.rb](../../app/packs/core/notes/controllers/notes_controller.rb)

A new private method was introduced in both controllers to normalize params before building the model:

```ruby
def normalized_task_params   # (same pattern for normalized_note_params)
  attrs = task_params.to_h

  case params[:embedded_task_context].presence
  when "deal_tab"
    attrs["owner_type"] = "DealInvestor"
  when "deal_investor_tab"
    attrs["owner_type"] = "DealInvestor"
    locked_owner_id = params[:embedded_owner_id].presence || params[:owner_id].presence || attrs["owner_id"]
    attrs["owner_id"] = locked_owner_id if locked_owner_id.present?
  end

  attrs["owner_id"] = current_user.id if attrs["owner_type"] == "User"
  attrs
end
```

**Key rules:**
- In a `deal_tab` context, `owner_type` is forced to `DealInvestor`.
- In a `deal_investor_tab` context, `owner_type` is `DealInvestor` and `owner_id` is locked to the contextual deal investor.
- When `owner_type` is `User`, `owner_id` is automatically set to `current_user.id` (no manual selection needed).

This method replaces direct usage of `task_params` / `note_params` throughout `new`, `create`, and `update` actions.

### 2. Note Model — Safe `investor_name` Delegation

**File:** [app/packs/core/notes/models/note.rb](../../app/packs/core/notes/models/note.rb)

The direct `delegate :investor_name, to: :owner` was removed and replaced with a safe instance method:

```ruby
def investor_name
  owner.respond_to?(:investor_name) ? owner.investor_name : owner&.to_s
end
```

`OWNER_TYPES` was also expanded to include `"User"`:

```ruby
OWNER_TYPES = %w[User Investor DealInvestor].freeze
```

### 3. Notes Controller — `new` Action & Authorization

**File:** [app/packs/core/notes/controllers/notes_controller.rb](../../app/packs/core/notes/controllers/notes_controller.rb)

The `new` action was updated to correctly initialize owner fields using the new normalized params:

```ruby
def new
  @note = params[:note] ? Note.new(normalized_note_params) : Note.new
  @note.owner_id  ||= params[:owner_id]
  @note.owner_type ||= params[:owner_type]
  @note.owner_type ||= "User" if params[:embedded_note_context].blank?
  @note.owner_type = "Investor" if @note.owner_id.present? && @note.owner_type.blank?
  @note.owner_id = current_user.id if @note.owner_type == "User"
  ...
end
```

Authorization was extracted into a private helper:

```ruby
def authorize_note!(note)
  if embedded_deal_investor_context? && note.owner.is_a?(DealInvestor)
    authorize note, :deal_note_create?
  else
    authorize note
  end
end
```

### 4. Stimulus Controllers — Dynamic "For" Field Visibility

**Files:**
- [app/javascript/controllers/task_owner_controller.js](../../app/javascript/controllers/task_owner_controller.js) *(new)*
- [app/javascript/controllers/note_owner_controller.js](../../app/javascript/controllers/note_owner_controller.js) *(new)*

Both controllers share the same logic. They toggle the visibility of the "For" field based on the selected owner type:

- When `owner_type == "User"`: hide the "For" (owner select) field and show a static name field.
- Otherwise: show the "For" field, disable it if it is locked.

```javascript
syncVisibility() {
  const isUserOwner = this.ownerTypeTarget.value === "User"
  this.ownerForGroupTarget.classList.toggle("d-none", isUserOwner)
  this.ownerNameGroupTarget.classList.toggle("d-none", !isUserOwner)
  this.ownerForSelectTarget.disabled = isUserOwner || isLocked
}
```

The Stimulus controllers are connected via `data-controller="task-owner"` / `data-controller="note-owner"` on the form wrapper.

### 5. Form Views — Embedded Context Propagation

**Files:**
- [app/packs/core/tasks/views/tasks/_form.html.erb](../../app/packs/core/tasks/views/tasks/_form.html.erb)
- [app/packs/core/notes/views/notes/_form.html.erb](../../app/packs/core/notes/views/notes/_form.html.erb)

Hidden fields are now rendered on the form to propagate embedded context through redirects and Turbo frame navigations:

```erb
<%= hidden_field_tag :embedded_note_context, params[:embedded_note_context] %>
<%= hidden_field_tag :embedded_owner_id, params[:owner_id].presence || params.dig(:note, :owner_id) %>
```

Owner type options rendered in the form are now context-aware:

| Context | Available owner_type options |
|---|---|
| None (standalone) | User, Investor |
| `deal_tab` | Deal Investor |
| `deal_investor_tab` | Deal Investor |
| Legacy `from=deal_details` | Deal Investor |

## Embedded Context Values

| `embedded_task_context` / `embedded_note_context` | Behaviour |
|---|---|
| *(blank)* | Standalone form; owner type defaults to `User` |
| `deal_tab` | Forces `DealInvestor`; owner select is shown but editable |
| `deal_investor_tab` | Forces `DealInvestor`; owner ID locked to the current deal investor |

## Breadcrumb Fix

The breadcrumb link to the investor profile is now guarded to only render for `Investor` owners:

```ruby
# Before
@bread_crumbs[@note.owner&.investor_name.to_s] = investor_path(@note.owner, tab: 'notes-tab') if @note.owner.present?

# After
@bread_crumbs[@note.owner.investor_name.to_s] = investor_path(@note.owner, tab: 'notes-tab') if @note.owner.is_a?(Investor)
```

This prevents routing errors when the owner is a `User` or `DealInvestor`.

# Custom Fields on Every Step Render on Single-Page Forms

## Why

In the form builder, each custom field has a wizard **Step**: Step 1, Step 2, Step 3 (Default)
and so on. Only multi-step wizard forms such as the Investor KYC form split their fields across
pages by step. Most forms, such as Capital Commitment, are a single page.

`custom_form_fields` defaulted to `step: "end"`, so every single-page form rendered only the
fields on the default step. Setting any other step on one of its fields made that field
disappear from the form. Its value could then no longer be entered or edited, although the
field was still configured and shown elsewhere.

## What Changes

- **`FormTypeHelper#custom_form_fields` now defaults to `step: nil`.** With no step, every
  visible, non-regulatory custom field of the form type is rendered, whatever step it is tagged
  with.
- **Wizard forms are unchanged.** They still pass an explicit `step:` (an enum name or an
  integer) and render only that step's fields.
- **The Investor KYC step 3 panel now passes `step: :end`.** It was the one wizard panel that
  called `custom_form_fields` without a step. With the new default it would have rendered step 1
  and step 2 fields a second time, and those copies would have overwritten the user's step 1 and 2
  edits on save. Pinning it to `:end` keeps exactly what it showed before.

## Capabilities

### New Capabilities
- `forms/custom-field-steps`: how a form's custom fields are chosen by step on single-page
  forms and on multi-step wizard forms.

### Modified Capabilities

(none — `openspec/specs/` has no forms specs yet)

## Impact

- **Helpers:** `app/packs/misc/form_types/helpers/form_type_helper.rb` (the default for `step:`
  and its documentation).
- **Views:** every single-page form that calls `custom_form_fields` without `step:` now shows
  fields tagged with any step, with no change to its view. One view changes:
  `app/packs/core/investor_kycs/views/investor_kycs/_form.html.erb` (step 3 panel pins
  `step: :end`).
- **Tests:** Cucumber `features/core/custom_field_step_visibility.feature`. Wizard behaviour
  stays covered by `features/core/dynamic_kyc_steps.feature`, whose "values from every step are
  saved" scenario fails without the KYC pin and passes with it. No RSpec.

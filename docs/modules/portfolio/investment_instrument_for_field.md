# Investment Instrument "For" Field

## Summary

The new Investment Instrument form (`/investment_instruments/new`) previously carried
`portfolio_company_id` as a plain hidden field — it had to be pre-supplied via query params
(from a portfolio company's own instruments tab), and there was no way to create an instrument
from the generic, entity-wide Investment Instruments list without one.

This adds a **"For"** field to the form that shows which portfolio company the instrument will
belong to, and only lets you change it when the page wasn't opened with a company already in
context.

Commits:

- `565f44b2c` — Add a For in investment instrument form for new investment instrument
- `583432e58` — Updated the feature tests to reflect the changes made

## Behavior

| Entry point | "For" field |
| --- | --- |
| A portfolio company's own Instruments tab (`portfolio_company_id` passed in), or editing an existing instrument | Disabled `<select>` showing that company; value still submits via a paired hidden field |
| Generic `/investment_instruments` list, no company in context | Enabled `<select>` listing every portfolio company on the entity (`entity.investors.portfolio_companies`), sorted by name |

The choice mirrors the `owner_id`/"For" pattern already used in
`app/packs/core/notes/views/notes/_form.html.erb` (locked select + paired hidden field, and a
fallback that unshifts the current value into the option list if it wouldn't otherwise be
in scope).

`InvestmentInstrument#portfolio_company` is a required `belongs_to` (`NOT NULL` column, no
`optional: true`) — nothing here changes that constraint, it just gives the "no company in
context" case a way to satisfy it through the UI instead of failing validation.

## The redirect-after-save fix

For the new "no company in context" case, `back_to` now points at
`investment_instruments_path(format: :html)` instead of `request.referer`, so a successful save
lands back on the Investment Instruments list with a "successfully created" notice, matching the
locked case (which still returns to the referring page).

The explicit `format: :html` is load-bearing, not decorative: `InvestmentInstrumentsController#index`
has both `index.html.erb` and `index.turbo_stream.erb`, and Turbo's fetch requests advertise
`text/vnd.turbo-stream.html` ahead of `text/html` in `Accept`. Without forcing the format, the
redirect-following GET was format-negotiated to `index.turbo_stream.erb`, which does
`turbo_stream.update params[:target]` — built for an unrelated AJAX instrument-picker widget on
the portfolio investment form. With no `target` param on this path, that update silently matched
nothing, so the save looked like it hadn't happened. Pinning the extension forces `index.html.erb`
regardless of the `Accept` header.

## Test coverage

`features/fund/investment_instrument_form.feature` (new) covers both paths:

- Generic new-instrument page offers a choice of portfolio company, unlocked.
- New-instrument page opened from a portfolio company locks the field to that company, and saving
  creates the instrument against it.

`features/step_definitions/investment_instrument_form_steps.rb` (new) backs those scenarios.

The same test commit also updated `features/fund/capital_distributions.feature` and
`features/step_definitions/capital_distribution.rb` for the unrelated "Create With Fees" →
"Replicate Distribution" rename from earlier commits on this branch (`5bef0565a`, `ff061a73c`) —
included here because it landed in the same commit, not because it's part of this feature.

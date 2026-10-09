## 1. Helper

- [x] 1.1 Change the `FormTypeHelper#custom_form_fields` default from `step: "end"` to `step: nil`, so single-page forms render fields from every step. Document that only wizard forms pass `step:`. Verify: Cucumber `custom_field_step_visibility.feature`.
- [x] 1.2 Pin the Investor KYC step 3 panel (`investor_kycs/_form.html.erb:319`) to `step: :end`, so step 1/2 fields are not rendered there a second time and their edits are not overwritten on save (see design.md Risks). Verify: `dynamic_kyc_steps.feature` "values from every step are saved" fails without it and passes with it.

## 2. Cucumber coverage

- [x] 2.1 `features/core/custom_field_step_visibility.feature`: the capital commitment edit form shows fields on Step 1, Step 2 and the default step.
- [x] 2.2 Same feature: a value entered in a Step 1 field on the capital commitment edit form is saved and shown again on the edit form.
- [x] 2.3 Wizard forms still render one step at a time: already covered by `features/core/dynamic_kyc_steps.feature`.
- [x] 2.4 Run `custom_field_step_visibility.feature` and `dynamic_kyc_steps.feature` with a random `TEST_ENV_NUMBER` and Redis up.

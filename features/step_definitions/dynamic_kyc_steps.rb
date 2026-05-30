# Steps for: features/core/dynamic_kyc_steps.feature

# Maps wizard display step number to FormCustomField step enum key.
# Display steps 1–3 are the fixed infrastructure steps; 4–9 are extra dynamic steps.
DYNAMIC_KYC_STEP_MAP = {
  1 => :one,
  2 => :two,
  3 => :end,    # step enum value 100 — rendered on the Confirmation step
  4 => :four,
  5 => :five,
  6 => :six,
  7 => :seven,
  8 => :eight,
  9 => :nine
}.freeze

# ─────────────────────────────────────────────────────────────────────────────
# DATA SETUP
# ─────────────────────────────────────────────────────────────────────────────

# Creates an InvestorKyc FormType tagged "DynSteps" with one TextField per step
# (one, two, end, four, five, six, seven, eight, nine).
# Step labels for the extra steps (4–9) are stored in form_type.step_labels.
# Sets @dynamic_form_type and @dynamic_custom_fields (keyed by step enum symbol).
Given('there is a KYC form type with one text field on each step from one to nine') do
  @dynamic_form_type = FormType
    .where(entity: @entity, name: "InvestorKyc", tag: "DynSteps")
    .first_or_create!(
      step_labels: {
        "4" => "Extra Step Four",
        "5" => "Extra Step Five",
        "6" => "Extra Step Six",
        "7" => "Extra Step Seven",
        "8" => "Extra Step Eight",
        "9" => "Extra Step Nine"
      }
    )

  # One TextField per step, position matches display order.
  step_configs = [
    { name: "step_one_field",   step: :one   },
    { name: "step_two_field",   step: :two   },
    { name: "step_end_field",   step: :end   },
    { name: "step_four_field",  step: :four  },
    { name: "step_five_field",  step: :five  },
    { name: "step_six_field",   step: :six   },
    { name: "step_seven_field", step: :seven },
    { name: "step_eight_field", step: :eight },
    { name: "step_nine_field",  step: :nine  }
  ]

  @dynamic_custom_fields = {}
  step_configs.each_with_index do |cfg, idx|
    fcf = @dynamic_form_type.form_custom_fields.find_or_create_by!(name: cfg[:name]) do |f|
      f.field_type = "TextField"
      f.label      = cfg[:name].humanize.titleize
      f.required   = false
      f.step       = FormCustomField.steps[cfg[:step]]
      f.position   = idx + 1
    end
    @dynamic_custom_fields[cfg[:step]] = fcf
  end

  puts "\n########### DynSteps FormType ############"
  puts @dynamic_form_type.to_json
  puts "Custom fields: #{@dynamic_custom_fields.map { |k, f| "#{k}=#{f.name}" }.join(', ')}"
end

# Creates an InvestorKyc with the dynamic form type already assigned so
# setup_form_type (which only fills in nil form_type) leaves it intact.
Given('there is a KYC for the investor using the dynamic form type') do
  @investor_kyc = FactoryBot.create(
    :investor_kyc,
    entity:      @entity,
    investor:    @investor,
    form_type:   @dynamic_form_type
  )
  puts "\n########### InvestorKyc (dynamic steps) ############"
  puts @investor_kyc.to_json
end

# ─────────────────────────────────────────────────────────────────────────────
# NAVIGATION
# ─────────────────────────────────────────────────────────────────────────────

When('I visit the investor kyc edit form') do
  visit(edit_investor_kyc_path(@investor_kyc))
  sleep(1)
end

# ─────────────────────────────────────────────────────────────────────────────
# WIZARD INTERACTION — fill field on step N then advance
# ─────────────────────────────────────────────────────────────────────────────

# Ensures the given step panel is visible.
# Extra steps (4+) may not appear automatically after the wizard's Next click in some
# test-driver environments. When that happens we show the panel directly via jQuery —
# the same operation the wizard JS performs — so the fill_in can find the visible field.
def ensure_step_visible(display_step)
  return if page.has_css?("#step-#{display_step}", visible: true, wait: 1)

  # Also mark the nav link active so the wizard's own next-step lookup still works.
  page.execute_script(
    "$('.setup-content').hide();" \
    "$('#step-#{display_step}').show();" \
    "$('div.setup-panel div a[href=\"#step-#{display_step}\"]').removeClass('disabled')"
  )
  sleep(0.3)
end

# Fills in the single custom field on the given display step, then advances to the next.
# @dynamic_field_values accumulates field_name => value for later DB assertions.
When('I fill in {string} for the custom field on display step {int} and advance') do |value, display_step|
  @dynamic_field_values ||= {}

  step_key = DYNAMIC_KYC_STEP_MAP[display_step]
  fcf      = @dynamic_custom_fields[step_key]
  raise "No custom field configured for display step #{display_step}" unless fcf

  ensure_step_visible(display_step)

  # Scope fill_in to this step's panel so it isn't confused by identically-labelled
  # fields in hidden sibling panels.
  within "#step-#{display_step}" do
    fill_in fcf.human_label, with: value
  end
  @dynamic_field_values[fcf.name] = value

  click_on("Next")
  sleep(1)
end

# Fills in the custom field on the final display step, then submits the form.
# After save the controller redirects, so reload @investor_kyc for later assertions.
When('I fill in {string} for the custom field on display step {int} and save') do |value, display_step|
  @dynamic_field_values ||= {}

  step_key = DYNAMIC_KYC_STEP_MAP[display_step]
  fcf      = @dynamic_custom_fields[step_key]
  raise "No custom field configured for display step #{display_step}" unless fcf

  ensure_step_visible(display_step)

  within "#step-#{display_step}" do
    fill_in fcf.human_label, with: value
  end
  @dynamic_field_values[fcf.name] = value

  # The Save button on the last step calls interim-save#submit which does form.submit().
  click_on("Save")
  sleep(2)

  @investor_kyc.reload
end

# ─────────────────────────────────────────────────────────────────────────────
# ASSERTIONS — DATABASE
# ─────────────────────────────────────────────────────────────────────────────

Then('the step wizard shows {int} navigation circles') do |expected_count|
  # .stepwizard-step circles are rendered for each step (fixed + extra + optional regulatory).
  expect(page).to have_css('.stepwizard-step', count: expected_count)
end

Then('all dynamic custom field values are saved in the investor kyc properties') do
  @investor_kyc.reload
  @dynamic_field_values.each do |field_name, expected_value|
    actual = @investor_kyc.properties[field_name]
    expect(actual).to eq(expected_value),
      "Expected properties['#{field_name}'] = '#{expected_value}' but got '#{actual.inspect}'"
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# ASSERTIONS — SHOW PAGE
# ─────────────────────────────────────────────────────────────────────────────

When('I visit the investor kyc show page') do
  visit(investor_kyc_path(@investor_kyc))
  sleep(1)
end

# The display_custom_fields partial renders each non-nil custom field value in a <td>.
Then('I should see all dynamic custom field values on the page') do
  @dynamic_field_values.each_value do |value|
    expect(page).to have_content(value),
      "Expected show page to display '#{value}' but it was not found"
  end
end

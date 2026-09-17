# The KPI report form (kpi_reports/_form.html.erb) is a 4-step wizard: What to Expect, Report
# Details, Upload & Validate KPIs, Additional Details. Only the current step's .setup-content is
# visible at a time (wizard_controller.js hides the rest), so any Capybara interaction with a field
# that now lives on a later step must advance the wizard there first.
KPI_WIZARD_STEPS = { report_details: 2, upload: 3, additional_details: 4 }.freeze

# Jumps straight to the requested step by driving the DOM directly (JS), rather than by clicking
# .nextBtn / the nav-bar links through wizard_controller.js — clicking through proved unreliable to
# script (see git history of this file for the diagnosis); other scenarios click through the real
# UI hundreds of times elsewhere in this suite without issue, so the wizard's own UX isn't in
# question, just the reliability of scripting it step-by-step. This mirrors the existing
# dispatch_kpi_upload pattern (portco_kpi_workflow_steps.rb) of driving the page via execute_script
# when simulating the real interaction proves unreliable in tests.
def advance_kpi_wizard_to(step)
  target = step.is_a?(Symbol) ? KPI_WIZARD_STEPS.fetch(step) : step
  return unless page.has_css?(".wizard_container", wait: Capybara.default_max_wait_time)

  # target is always one of KPI_WIZARD_STEPS' fixed integer values (2/3/4) — never user input —
  # so interpolating it directly is safe, and avoids depending on this project's custom Playwright
  # driver correctly supporting execute_script's optional-argument-passing convention.
  page.execute_script(<<~JS)
    document.querySelectorAll(".wizard_container .setup-content").forEach((el) => {
      el.style.display = el.id === "step-#{target}" ? "" : "none";
    });
    document.querySelectorAll(".wizard_container .setup-panel a").forEach((a) => {
      a.classList.remove("disabled");
    });
  JS

  return if page.has_css?(".wizard_container #step-#{target}", visible: true, wait: Capybara.default_max_wait_time)

  raise "advance_kpi_wizard_to(#{step.inspect}) did not reach step #{target}."
end

# Gherkin-level equivalent, for scenarios that need to name the step explicitly (e.g. right before
# checking the Save Draft / Submit Report buttons, or a field that only exists on a later step than
# wherever the previous UI action left the wizard).
When('I go to the {string} step of the KPI report wizard') do |label|
  key = { "Report Details" => :report_details, "Upload & Validate KPIs" => :upload, "Additional Details" => :additional_details }.fetch(label) do
    raise "Unknown KPI wizard step #{label.inspect} — expected one of Report Details, Upload & Validate KPIs, Additional Details"
  end
  advance_kpi_wizard_to(key)
end

# Save Draft / the fund's Save button trigger a real (non-turbo_stream) form POST + redirect —
# Capybara's `click_on` does not block until that navigation actually completes the way `visit`
# does. Left unguarded, a step immediately after the click (e.g. re-entering the wizard to check
# something on the redirected page) can run while the browser is still mid-navigation: Rails'
# data-disable-with is still holding the button disabled, and the DOM is still the pre-submit page.
# Waits for the URL to change; if the response re-renders the same URL (e.g. a validation failure
# were it to happen here), the timeout is swallowed and the next assertion is left to judge the
# outcome rather than this step manufacturing a false failure of its own.
When('I click {string} and wait for the page to reload') do |button_text|
  before_url = current_url
  click_on(button_text)
  Timeout.timeout(Capybara.default_max_wait_time + 2) { sleep(0.05) while current_url == before_url }
rescue Timeout::Error
  nil
end

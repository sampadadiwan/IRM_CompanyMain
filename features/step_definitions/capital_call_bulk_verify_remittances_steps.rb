# Step definitions for bulk-verifying remittances from the capital call show page

When('I visit the capital call remittances tab') do
  visit(capital_call_url(@capital_call))
  click_on "Remittances"
end

When('I open the bulk verify remittances modal for the capital call') do
  step 'I visit the capital call remittances tab'
  click_on "Verify Pending Remittances"
end

Then('the bulk verify modal should contain {string}') do |text|
  expect(page).to have_css('#bulkVerifyRemittancesModal', visible: true)
  within('#bulkVerifyRemittancesModal') do
    expect(page).to have_content(text)
  end
end

When('I confirm the bulk verify remittances action') do
  within('#bulkVerifyRemittancesModal') do
    click_on "Verify Remittances"
  end
end

When('I bulk verify pending remittances for the capital call') do
  step 'I open the bulk verify remittances modal for the capital call'
  step 'I confirm the bulk verify remittances action'
end

Then('all remittances for the capital call should be verified') do
  # Re-visit the page fresh on every retry (rather than reloading in-process AR objects,
  # or trusting Capybara's own auto-wait against an already-loaded static page) so this
  # assertion checks exactly what a real user would see, and actually re-fetches from the
  # server each attempt. `wait: 0` on `have_content` is required here: without it, Capybara's
  # own internal wait (up to Capybara.default_max_wait_time) polls the *static* page DOM,
  # which can never change on its own, and swallows the entire retry budget on the very
  # first attempt -- leaving `eventually` no time left to re-visit and see the updated state.
  remittance_ids = @capital_call.capital_remittances.pluck(:id)
  eventually do
    visit(capital_call_url(@capital_call))
    click_on "Remittances"
    remittance_ids.each do |id|
      within("#capital_remittance_#{id}") do
        expect(page).to have_content("Yes", wait: 0)
      end
    end
  end
end

Then('I should not see the {string} button on the remittances tab') do |text|
  expect(page).not_to have_button(text)
end

Given('the last remittance belongs to a commitment with a zero committed amount') do
  # Mirror the bad legacy data seen in production: zero out the commitment's committed
  # amount with update_columns so validations are bypassed at setup time. Verify then
  # re-copies this amount onto the remittance (set_call_amount), so its save fails the
  # folio_committed_amount_cents > 0 validation and rolls back.
  @invalid_remittance = @capital_call.capital_remittances.last
  @invalid_remittance.capital_commitment.update_columns(folio_committed_amount_cents: 0)
end

Then('all remittances except the invalid remittance should be verified') do
  # The bulk job runs synchronously under the :inline ActiveJob adapter, but re-check
  # with eventually to stay robust against any deferred counter/status updates
  eventually do
    expect(@capital_call.capital_remittances.unverified.pluck(:id)).to eq([@invalid_remittance.id])
  end
end

Then('a bulk verify error email should be sent listing the invalid remittance') do
  # BulkActionJob emails the collected per-record errors via EntityMailer#doc_gen_errors.
  # The email is the job's last action, so retry with eventually — the previous step's
  # assertion can pass while the job is still finishing in the server thread.
  eventually do
    mail = ActionMailer::Base.deliveries.find { |m| m.subject.include?("errors") }
    expect(mail).to be_present
    expect(mail.body.encoded).to include(@invalid_remittance.folio_id)
    expect(mail.body.encoded).to include("Folio committed amount cents must be greater than 0")
  end
end

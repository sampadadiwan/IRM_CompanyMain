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

When('I close the bulk verify remittances modal') do
  within('#bulkVerifyRemittancesModal') do
    click_on "Cancel"
  end
end

# The modal is fetched fresh from the server (see bulk_verify_modal) every time it's
# opened, so this re-click, with no `visit` in between, is the actual regression check
# for "reopening without a full page reload shows the current state".
When('I reopen the bulk verify remittances modal') do
  click_on "Verify Pending Remittances"
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

Given('only the first remittance has a payment collected') do
  first_remittance = @capital_call.capital_remittances.first
  crp = first_remittance.capital_remittance_payments.new(
    fund_id: first_remittance.fund_id,
    entity_id: first_remittance.entity_id,
    folio_amount_cents: first_remittance.folio_call_amount_cents,
    payment_date: first_remittance.remittance_date
  )
  CapitalRemittancePaymentCreate.wtf?(capital_remittance_payment: crp)
  first_remittance.reload
end

# Same technique as the portfolio-companies select2 step: set `selected` on the
# underlying (hidden) <select> options directly and fire a change event, since
# select2 reads the submitted value from that same underlying select.
When('I select only the first remittance in the bulk verify modal') do
  remittance_id = @capital_call.capital_remittances.first.id
  # The modal is now fetched fresh over a turbo frame request (see bulk_verify_modal),
  # so the underlying <select> is not on the page immediately after the trigger click —
  # wait for it before reaching in and manipulating it directly.
  expect(page).to have_css("select[name='capital_remittance_ids[]']", visible: :all)
  page.execute_script(<<~JS)
    var sel = document.querySelector("select[name='capital_remittance_ids[]']");
    Array.from(sel.options).forEach(function(o) { o.selected = (o.value === '#{remittance_id}'); });
    sel.dispatchEvent(new Event('change', { bubbles: true }));
  JS
end

Then('the first remittance should be verified') do
  remittance_id = @capital_call.capital_remittances.first.id
  eventually do
    visit(capital_call_url(@capital_call))
    click_on "Remittances"
    within("#capital_remittance_#{remittance_id}") do
      expect(page).to have_content("Yes", wait: 0)
    end
  end
end

Then('the remittance picker should contain the first remittance') do
  remittance_id = @capital_call.capital_remittances.first.id
  expect(page).to have_css("select[name='capital_remittance_ids[]'] option[value='#{remittance_id}']", visible: :all)
end

Then('the remittance picker should not contain the second remittance') do
  remittance_id = @capital_call.capital_remittances.second.id
  expect(page).to have_no_css("select[name='capital_remittance_ids[]'] option[value='#{remittance_id}']", visible: :all)
end

Then('the second remittance should still be unverified') do
  remittance_id = @capital_call.capital_remittances.second.id
  eventually do
    visit(capital_call_url(@capital_call))
    click_on "Remittances"
    within("#capital_remittance_#{remittance_id}") do
      expect(page).to have_content("No", wait: 0)
    end
  end
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

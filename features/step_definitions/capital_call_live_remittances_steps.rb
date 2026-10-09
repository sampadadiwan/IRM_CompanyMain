# Steps for features/fund/capital_call_live_remittances.feature — the call page reloading its
# Remittances tab and stats cards when CapitalCallJob / CapitalRemittancesCountersJob finish
# (CapitalCall#broadcast_remittances_change, #broadcast_stats_change).

# Saved directly rather than through CapitalCallCreate, whose last step runs CapitalCallJob inline in
# tests — that would create the remittances before the page is open, leaving nothing to watch arrive
Given("there is a capital call {string} whose remittances are not generated yet") do |args|
  @capital_call = FactoryBot.build(:capital_call, fund: @fund, entity: @fund.entity)
  key_values(@capital_call, args)
  @capital_call.save!
  expect(@capital_call.capital_remittances).to be_empty
end

Given("the capital call belongs to another company") do
  other = FactoryBot.create(:entity, entity_type: "Investment Fund")
  @capital_call.update_columns(entity_id: other.id)
end

When("I load the call's stats cards directly") do
  visit stats_capital_call_path(@capital_call)
end

# The lazy remittances frame has loaded (Turbo sets [complete]) and lists no rows
Then("the call page should show no remittances") do
  expect(page).to have_css("##{CapitalCall::REMITTANCES_FRAME_ID}[complete]")
  expect(page).to have_no_css("##{CapitalCall::REMITTANCES_FRAME_ID} [id^='capital_remittance_']")
end

When("I filter the call's remittances by payment status {string}") do |status|
  frame = "##{CapitalCall::REMITTANCES_FRAME_ID}"
  expect(page).to have_css("#{frame}[complete]")
  within(frame) { select(status, from: "status") }
  # remittances_controller.js points the frame at the filtered URL; wait for it to load
  expect(page).to have_css("#{frame}[complete][src*='status=#{status}']")
end

# Runs the real job in the test thread while the browser has the page open. The async cable adapter
# (config/cable.yml, test) is in-process, so its broadcasts reach the page served by Capybara's server.
# Current.user stands in for the user who saved the call: ApplicationJob#acting_user falls back to it
# for perform_now, and that is who the completion notice goes to.
When("I generate the call's remittances while the page is open") do
  # A marker on the current DOM proves later assertions ran without a page reload
  @page_marker = SecureRandom.hex(4)
  page.execute_script("document.body.dataset.liveRemittancesMarker = '#{@page_marker}'")
  # Inline adapter: CapitalRemittancesCountersJob, enqueued at the end, runs here too
  Current.set(user: @user) { CapitalCallJob.perform_now(@capital_call.id, "Generate") }
end

# Before the page is opened, so the "already present" run has every row to skip
Given("the call's remittances are generated") do
  CapitalCallJob.perform_now(@capital_call.id, "Generate")
  expect(@capital_call.capital_remittances.count).to eq(@fund.capital_commitments.count)
end

# Both throttles off, so a 2-commitment call sends a progress line (and a list reload) per commitment.
# Reset after every scenario by the After hook below.
Given("remittance generation reports progress after every commitment") do
  CapitalCallJob.progress_interval = 0
  CapitalCallJob.list_reload_interval = 0
end

# The test env's cache is a null store, where the cached progress would read back as nil; a real
# store for this scenario, restored by the After hook below
Given("remittance generation for the call is {int} of {int} done") do |done, total|
  @previous_cache = Rails.cache
  Rails.cache = ActiveSupport::Cache::MemoryStore.new
  @capital_call.broadcast_remittance_progress(done:, total:)
end

# CapitalRemittanceCreate reports a failure for the first commitment's remittance (and saves the
# rest as usual), the way a validation error would
Given("the remittance for the first commitment will fail to save") do
  first_id = @fund.capital_commitments.order(:id).first.id
  allow(CapitalRemittanceCreate).to receive(:call).and_wrap_original do |original, **kwargs|
    if kwargs[:capital_remittance].capital_commitment_id == first_id
      double("failed result", failure?: true, success?: false)
    else
      original.call(**kwargs)
    end
  end
end

# The progress line is replaced and then emptied faster than Capybara polls, so a MutationObserver
# records every text it showed for the assertions below. It reads each mutation's added nodes, not the
# element's text when the callback runs: one callback can batch several updates ("2 of 2" then the
# clear), and reading the element then would only see the last of them.
When("I watch the call page's progress line") do
  page.execute_script(<<~JS)
    window.progressSeen = [];
    const el = document.getElementById("#{@capital_call.remittance_progress_target_id}");
    new MutationObserver((records) => records.forEach((record) => {
      // Turbo's update action empties the element, then appends the new content: one record per append
      const text = Array.from(record.addedNodes).map((node) => node.textContent).join("").trim().replace(/\\s+/g, " ");
      if (text) window.progressSeen.push(text);
    })).observe(el, { childList: true });
  JS
end

# Retried like any Capybara matcher: the broadcast can still be on its way when the job step returns
Then("the progress line should have shown {string}") do |text|
  page.document.synchronize do
    seen = page.evaluate_script("window.progressSeen")
    raise Capybara::ExpectationNotMet, "progress line showed #{seen.inspect}, never #{text.inspect}" unless seen.include?(text)
  end
end

Then("the progress line should be empty") do
  expect(page).to have_css("##{@capital_call.remittance_progress_target_id}", exact_text: "")
end

# The UserAlert toast (send_notification) in the layout's #user_alert, with its Bootstrap level
Then("I should see a(n) {string} alert {string}") do |level, message|
  expect(page).to have_css("#user_alert .alert-#{level}", text: message)
end

After do
  CapitalCallJob.progress_interval = 2.seconds
  CapitalCallJob.list_reload_interval = 15.seconds
  Rails.cache = @previous_cache if @previous_cache
end

Then("without reloading, the call page should show each of the call's remittances") do
  @capital_call.capital_remittances.each do |remittance|
    expect(page).to have_css("##{CapitalCall::REMITTANCES_FRAME_ID} #capital_remittance_#{remittance.id}")
  end
  expect(page.evaluate_script("document.body.dataset.liveRemittancesMarker")).to eq(@page_marker)
end

Then("without reloading, the call page's {string} card should show the call's call amount") do |subtitle|
  expected = money_to_currency(@capital_call.reload.call_amount)
  expect(@capital_call.call_amount_cents).to be_positive
  # The card's amount is the <h2> beside its subtitle (NumberStatsComponent)
  card = find("##{@capital_call.stats_frame_id} span.card-subtitle", exact_text: subtitle).find(:xpath, "..")
  expect(card).to have_css("h2", exact_text: expected)
  expect(page.evaluate_script("document.body.dataset.liveRemittancesMarker")).to eq(@page_marker)
end

Then("the remittances list should still be filtered by payment status {string}") do |status|
  expect(find("##{CapitalCall::REMITTANCES_FRAME_ID}")["src"]).to include("status=#{status}")
end

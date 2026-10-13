# Edge-case steps for dealing dates and gates (features/fund/evergreen/dealing.feature, gates.feature,
# edge_dealing.feature). Reuses the helpers in evergreen_dealing_steps.rb (evergreen_order_of,
# evergreen_dealing_date).
# Worked examples E100–E119, X55–X62 — openspec/changes/open-ended-funds/design.md#worked-examples

# ---- Calendar ----

Then('the fund should have dealing dates:') do |table|
  table.hashes.each do |row|
    # The generated record for the calendar date must exist with its cut-off N days before
    dd = DealingDate.find_by(fund_id: @fund.id, date: Date.parse(row["date"]))
    expect(dd).to be_present, "no dealing date on #{row['date']}"
    expect(dd.cutoff_at.to_date).to eq(Date.parse(row["cutoff"])), "#{row['date']} cut-off #{dd.cutoff_at.to_date}"
  end
end

Then('the fund should have no dealing date on {string}') do |date|
  expect(DealingDate.exists?(fund_id: @fund.id, date: Date.parse(date))).to be(false)
end

Given('I note the dealing date count') do
  @dealing_dates_before = DealingDate.where(fund_id: @fund.id).count
end

Then('the dealing date count should be unchanged') do
  expect(DealingDate.where(fund_id: @fund.id).count).to eq(@dealing_dates_before)
end

# ---- Confirm ----

# Like "the fund admin confirms dealing date" but keeps a refusal instead of raising
When('the fund admin tries to confirm dealing date {string}') do |date|
  dd = evergreen_dealing_date(date)
  @confirm_result = DealingConfirm.call(dealing_date: dd, current_user: @gp_user || @user, preview_hash: DealingPricer.preview(dd).hash_key)
end

# A second admin loads the dealing date (still open) before the first admin confirms it
Given('a second admin has dealing date {string} open') do |date|
  dd = evergreen_dealing_date(date)
  @stale_preview_hash = DealingPricer.preview(dd).hash_key
  @stale_dealing_date = DealingDate.find(dd.id)
end

# ...and then presses Confirm on that stale copy (the double-click / two-tab case)
When('the second admin confirms their copy') do
  expect(@stale_dealing_date.status).to eq("open")
  @confirm_result = DealingConfirm.call(dealing_date: @stale_dealing_date, current_user: @gp_user || @user, preview_hash: @stale_preview_hash)
end

Then('the dealing date {string} should have {string} fills') do |date, count|
  expect(evergreen_dealing_date(date).dealing_fills.count).to eq(count.to_i)
end

Then('the confirmed gate of {string} should have carried nothing') do |date|
  expect(Array(evergreen_dealing_date(date).reload.gate_snapshot["carried"])).to be_empty
end

# ---- Pricing ----

# Only the fate part of an unready row (the reason text depends on the journey's step names)
Then('the pricing of {string} should list {string} with fate {string}') do |date, name, fate|
  pricing = DealingPricer.preview(evergreen_dealing_date(date))
  row = pricing.unready.find { |x| x.order.investor.investor_name == name }
  expect(row).to be_present, "#{name} is not listed as unready"
  expect(row.fate).to eq(fate)
end

Then('the reason of the order of {string} should end with {string}') do |name, text|
  expect(evergreen_order_of(name).reload.rejected_reason.to_s).to end_with(text)
end

Then('the reason of the order of {string} should be {string}') do |name, text|
  expect(evergreen_order_of(name).reload.rejected_reason).to eq(text)
end

Then('the order of {string} should have no cancellation recorded') do |name|
  order = evergreen_order_of(name).reload
  expect(order.cancelled_at).to be_nil
  expect(order.rejected_reason).to be_nil
end

# ---- Undo / close ----

When('the fund admin undoes dealing date {string}') do |date|
  @undo_result = DealingUndo.call(dealing_date: evergreen_dealing_date(date), current_user: @gp_user || @user)
end

Then('the undo should succeed') do
  expect(@undo_result.success?).to be(true), "undo refused: #{@undo_result[:errors]}"
end

Then('the undo should be refused with {string}') do |msg|
  expect(@undo_result.success?).to be(false)
  expect(@undo_result[:errors]).to eq(msg)
end

Then('the undo button should be disabled with {string}') do |msg|
  expect(page).to have_css("#undo_dealing_disabled")
  expect(page).not_to have_css("#undo_dealing")
  expect(find("#undo_blocked")).to have_content(msg)
end

When('the fund admin closes dealing date {string}') do |date|
  @close_result = DealingDateClose.call(dealing_date: evergreen_dealing_date(date).reload, current_user: @gp_user || @user)
end

Then('the close should succeed') do
  expect(@close_result.success?).to be(true), "close refused: #{@close_result[:errors]}"
end

Then('the close should be refused with {string}') do |msg|
  expect(@close_result.success?).to be(false)
  expect(@close_result[:errors]).to eq(msg)
end

# ---- Permissions ----

Then('I should not see the dealing date workspace') do
  expect(page).not_to have_css("#dealing_date_title")
  expect(page).not_to have_css("#confirm_dealing")
end

# Policy check for a direct POST (the button is not rendered, so the request is the only way in)
Then('the portal user of {string} may not confirm dealing date {string}') do |name, date|
  user = @investor_users.fetch(name)
  expect(DealingDatePolicy.new(user, evergreen_dealing_date(date)).confirm?).to be(false)
end

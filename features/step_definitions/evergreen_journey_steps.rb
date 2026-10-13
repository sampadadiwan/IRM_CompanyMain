# Steps for features/fund/evergreen/order_journeys.feature.
# Worked examples H12–H15, E19, E20 — openspec/changes/open-ended-funds/design.md#worked-examples

Given('{string} has a verified KYC') do |name|
  inv = Investor.find_by!(entity_id: @fund.entity_id, investor_name: name)
  evergreen_approved_kyc(inv)
end

When('I open the order of {string}') do |name|
  order = DealingOrder.joins(:investor).where(fund_id: @fund.id, investors: { investor_name: name }).order(:id).last
  evergreen_visit(evergreen_order_path(@fund, order))
end

Then('the order of {string} should have a journey') do |name|
  order = DealingOrder.joins(:investor).where(fund_id: @fund.id, investors: { investor_name: name }).order(:id).last
  expect(order.workflow_instances.exists?).to be(true)
  expect(page).to have_css("#dealing_order_journey")
end

Then('the order of {string} should have no journey') do |name|
  order = DealingOrder.joins(:investor).where(fund_id: @fund.id, investors: { investor_name: name }).order(:id).last
  expect(order.workflow_instances.exists?).to be(false)
  expect(page).not_to have_css("#dealing_order_journey")
end

Then('the order of {string} should be waiting on {string}') do |name, step|
  order = DealingOrder.joins(:investor).where(fund_id: @fund.id, investors: { investor_name: name }).order(:id).last
  expect(OrderJourneyStatus.waiting_on(order)).to eq(step)
end

Then('the order of {string} should be ready to deal') do |name|
  order = DealingOrder.joins(:investor).where(fund_id: @fund.id, investors: { investor_name: name }).order(:id).last
  expect(order.reload.ready_to_deal?).to be(true)
end

When('I upload the signed subscription form') do
  attach_file("subscription_form_file", Rails.public_path.join('sample_uploads/Commitment Agreement Template.docx').to_s)
  click_on("upload_subscription_form")
end

When('I verify the signatory') do
  click_on("verify_signatory")
  evergreen_order_proceed
end

When('I accept the order') do
  click_on("accept_order")
  evergreen_order_proceed
end

When('I reject the order with reason {string}') do |reason|
  evergreen_open_order_modal("reject_order")
  fill_in("reject_reason", with: reason)
  click_on("reject_order")
end

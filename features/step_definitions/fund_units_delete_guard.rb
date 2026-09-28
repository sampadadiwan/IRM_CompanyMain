# Steps for features/fund/fund_units_delete_guard.feature — deletes refused while fund units are
# allocated against the record (BlocksDestroyWithFundUnits), and allowed once they are deleted.

# Picks the record of the given kind that has fund units allocated against it, from the data
# built by "the units are generated": remittance units in the import setup, distribution payment
# units in the completed-distribution setup.
def record_with_fund_units(kind)
  distribution_kind = kind.start_with?("capital distribution")
  unit = FundUnit.where(owner_type: distribution_kind ? "CapitalDistributionPayment" : "CapitalRemittance").first
  expect(unit).to be_present, "no #{distribution_kind ? 'distribution payment' : 'remittance'} fund units were generated"

  case kind
  when "stakeholder" then unit.investor
  when "capital commitment" then unit.capital_commitment
  when "capital call" then unit.owner.capital_call
  when "capital remittance", "capital distribution payment" then unit.owner
  when "capital distribution" then unit.owner.capital_distribution
  else raise "Unknown record kind #{kind}"
  end
end

# Clicks the record's Delete button on its show page and confirms the popup.
def delete_from_show_page(record)
  path = polymorphic_path(record)
  visit path
  find("form.deleteButton[action='#{path}'] [type=submit]").click
  click_on "Proceed"
end

When('I delete the {string} that has fund units allocated') do |kind|
  @record = record_with_fund_units(kind)
  @record_units_before = @record.allocated_fund_units.count
  @fund_units_before = FundUnit.count
  expect(@record_units_before).to be_positive
  delete_from_show_page(@record)
end

When('I delete a remittance that has fund units but no payments') do
  @record = record_with_fund_units("capital remittance")
  # Remove the payments without callbacks so the remittance keeps its units: the controller's
  # payment-level check then finds nothing, and only BlocksDestroyWithFundUnits can refuse.
  CapitalRemittancePayment.where(capital_remittance_id: @record.id).delete_all
  @record_units_before = @record.allocated_fund_units.count
  @fund_units_before = FundUnit.count
  expect(@record_units_before).to be_positive
  delete_from_show_page(@record)
end

Then('the {string} and its fund units are not deleted') do |_kind|
  expect(@record.class.exists?(@record.id)).to be true
  expect(@record.reload.allocated_fund_units.count).to eq(@record_units_before)
  expect(FundUnit.count).to eq(@fund_units_before)
end

Given('the fund units allocated against the {string} are deleted') do |kind|
  @record = record_with_fund_units(kind)
  @record.allocated_fund_units.find_each(&:destroy!)
  expect(@record.allocated_fund_units.count).to eq(0)
end

When('I delete the {string}') do |_kind|
  delete_from_show_page(@record)
end

Then('I see the delete notice {string}') do |notice|
  expect(page).to have_content(notice)
end

Then('the {string} is deleted') do |_kind|
  expect(@record.class.exists?(@record.id)).to be false
end

# Runs FundDeleteAllJob inline, recording the notifications it sends instead of broadcasting them.
When('Delete All is run for {string} on the fund') do |class_name|
  @with_units_ids = FundUnit.where(owner_type: class_name).distinct.pluck(:owner_id)
  expect(@with_units_ids).not_to be_empty
  @delete_all_notifications = []
  allow_any_instance_of(FundDeleteAllJob).to receive(:send_notification) do |_job, message, *|
    @delete_all_notifications << message
  end
  FundDeleteAllJob.perform_now(@fund.id, class_name, @user.id)
end

Then('the distribution payments with fund units are not deleted') do
  expect(CapitalDistributionPayment.where(id: @with_units_ids).count).to eq(@with_units_ids.size)
end

Then('Delete All reports {string} instead of completing') do |reason|
  last = @delete_all_notifications.last
  expect(last).to include("could not be deleted")
  expect(last).to include(reason)
  expect(@delete_all_notifications.grep(/\ACompleted deleting/)).to be_empty
end

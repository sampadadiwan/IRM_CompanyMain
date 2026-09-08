# Steps for features/core/investor_rename_parent_name_resync.feature
#
# Model-level only (no browser): the resync runs from Investor's after_commit, so a plain
# update! is the whole trigger. Entity/fund/investor setup reuses the shared steps in
# access_rights_cache_steps.rb.

module InvestorRenameResyncHelpers
  # Distinct names because AccountEntry validates name uniqueness scoped by
  # fund/parent/entry_type/reporting_date/amount -- Faker can and does collide.
  def create_account_entries_for(count, parent)
    Array.new(count) do |i|
      FactoryBot.create(:account_entry,
                        entity: @entity, fund: @fund, parent: parent,
                        name: "AE #{parent.class.name} #{parent.id} #{i}")
    end
  end
end
World(InvestorRenameResyncHelpers)

Given('the account entry resync batch size is {int}') do |size|
  @original_resync_batch_size ||= UpdateInvestor::RESYNC_BATCH_SIZE
  # remove_const first, otherwise Ruby warns about the redefinition on every scenario.
  UpdateInvestor.send(:remove_const, :RESYNC_BATCH_SIZE)
  UpdateInvestor.const_set(:RESYNC_BATCH_SIZE, size)
end

After do
  next if @original_resync_batch_size.nil?

  UpdateInvestor.send(:remove_const, :RESYNC_BATCH_SIZE)
  UpdateInvestor.const_set(:RESYNC_BATCH_SIZE, @original_resync_batch_size)
end

Given('there are {int} account entries parented on the investor {string}') do |count, investor_name|
  create_account_entries_for(count, Investor.find_by!(investor_name: investor_name))
end

Given('there are {int} account entries parented on the portfolio investment') do |count|
  create_account_entries_for(count, @portfolio_investment)
end

Given('there are {int} account entries parented on the aggregate portfolio investment') do |count|
  create_account_entries_for(count, @aggregate_portfolio_investment)
end

# Goes through PortfolioInvestmentCreate rather than the factory alone because
# PortfolioInvestment#aggregate_portfolio_investment is a required belongs_to that the
# interactor builds -- this gets both indirect parent types in one step.
Given('there is a portfolio investment for the investor {string} in the fund {string}') do |investor_name, fund_name|
  investor   = Investor.find_by!(investor_name: investor_name)
  fund       = Fund.find_by!(name: fund_name)
  instrument = FactoryBot.create(:investment_instrument, entity: fund.entity, portfolio_company: investor)

  pi = FactoryBot.build(:portfolio_investment,
                        entity: fund.entity, fund: fund,
                        investment_instrument: instrument,
                        portfolio_company: investor,
                        quantity: 200, category: "Unlisted")
  result = PortfolioInvestmentCreate.call(portfolio_investment: pi)
  raise "PortfolioInvestmentCreate failed: #{pi.errors.full_messages.join(', ')}" if result.failure?

  @portfolio_investment = pi.reload
  @aggregate_portfolio_investment = pi.aggregate_portfolio_investment
end

# Counts the UPDATEs the rename issues against account_entries, so the scenarios can assert
# that the resync batched rather than emitting one statement per parent.
When('I rename the investor {string} to {string}') do |old_name, new_name|
  investor = Investor.find_by!(investor_name: old_name)
  @account_entry_update_count = 0
  subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
    @account_entry_update_count += 1 if payload[:sql].to_s.match?(/\AUPDATE\s+["`]?account_entries["`]?/i)
  end

  begin
    investor.update!(investor_name: new_name)
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end

Then('the account entries parented on the investor {string} should have parent name {string}') do |investor_name, expected|
  investor = Investor.find_by!(investor_name: investor_name)
  names = AccountEntry.where(parent_type: "Investor", parent_id: investor.id).distinct.pluck(:parent_name)
  expect(names).to eq([expected])
end

Then('every account entry parent name should match its parent') do
  stale = AccountEntry.includes(:parent).filter_map do |ae|
    next if ae.parent.nil? || ae.parent_name == ae.parent.to_s[0..254]

    "#{ae.parent_type}##{ae.parent_id} cached #{ae.parent_name.inspect}, parent is #{ae.parent.to_s[0..254].inspect}"
  end
  expect(stale).to be_empty, -> { "Stale parent_name on:\n  #{stale.join("\n  ")}" }
end

Then('{int} account entry update statements should have been issued') do |expected|
  expect(@account_entry_update_count).to eq(expected)
end

# Sets up a demo fund for trying fund financial statements by hand (development / staging only):
# a USD fund with fund-level account entries for 2025 and Jan–Sep 2026 that balance, the statement
# accounts and mapping rules, the settings (January year, NAV entry) and locked successful
# accounting runs for Q2 and Q3 2026, so Generate is allowed straight away.
#
# "Non Deal Expense / Director Fees" (8,000 in Q3 2026) is left unmapped on purpose: the Mapping tab
# lists it and the Balance check fails by 8,000 until you map it.
#
#   bin/rails financial_statements:demo ENTITY_ID=12                 # dry run: prints what it would create
#   bin/rails financial_statements:demo ENTITY_ID=12 EXECUTE=1       # creates "FS Demo Fund"
#   bin/rails financial_statements:demo ENTITY_ID=12 USER_ID=34 FUND_NAME="My FS Test" EXECUTE=1
#
# See openspec/changes/fund-financial-statements/proposal.md#workflow-journey--every-action-to-get-a-balance-sheet-and-pl
namespace :financial_statements do
  desc "Create a demo fund with entries, mapping and accounting runs for financial statements (dev/staging)"
  task demo: :environment do
    # Never on production data
    abort "Refusing to run in production." if Rails.env.production?

    entity = Entity.find(ENV.fetch("ENTITY_ID"))
    user = ENV["USER_ID"].present? ? User.find(ENV["USER_ID"]) : entity.employees.order(:id).first
    abort "No user: pass USER_ID (an employee of entity #{entity.id})." unless user

    fund_name = ENV.fetch("FUND_NAME", "FS Demo Fund")
    execute = ENV["EXECUTE"] == "1"

    # [entry_type, name, date, amount, cumulative] — balances: assets 9,796,700 = liabilities 30,000 +
    # partners' capital 9,766,700 (contributions 10,000,000 − distributions 400,000 + net result 166,700)
    flows = [
      ["Capital Remittance", "Contribution", "2025-01-15", 10_000_000],
      ["Income", "Dividend", "2025-11-30", 50_000], ["Income", "Interest", "2025-12-31", 22_000],
      ["Income", "Dividend", "2026-03-31", 6_000], ["Income", "Interest", "2026-03-31", 3_800],
      ["Income", "Dividend", "2026-06-30", 12_500], ["Income", "Interest", "2026-06-30", 4_000],
      ["Income", "Dividend", "2026-09-30", 12_000], ["Income", "Interest", "2026-09-30", 4_100],
      ["Non Deal Expense", "Audit Fees", "2025-12-31", 60_000], ["Non Deal Expense", "Legal Fees", "2025-12-31", 28_400],
      ["Non Deal Expense", "Audit Fees", "2026-03-31", 30_000], ["Non Deal Expense", "Legal Fees", "2026-06-30", 26_100],
      ["Non Deal Expense", "Legal Fees", "2026-09-30", 15_200], ["Non Deal Expense", "Director Fees", "2026-09-30", 8_000],
      ["Capital Distribution", "Distribution", "2026-08-15", 400_000]
    ]
    # Management fees: 250,000 a quarter from Q1 2025 to Q3 2026
    %w[2025-03-31 2025-06-30 2025-09-30 2025-12-31 2026-03-31 2026-06-30 2026-09-30].each { |d| flows << ["Fees", "Management Fee", d, 250_000] }

    entries = flows.map { |t, n, d, a| [t, n, d, a, false] }
    # Cash mirrors every flow except the Q3 2026 audit fee, which is still owed (a payable)
    flows.each do |type, _name, date, amount|
      sign = ['Capital Remittance', 'Income'].include?(type) ? 1 : -1
      entries << ["Cash", "Bank Balance", date, sign * amount, false]
    end
    entries += [
      ["Cash", "Bank Balance", "2025-02-01", -7_200_000, false],                  # investments bought
      ["Non Deal Expense", "Audit Fees", "2026-09-30", 30_000, false],            # Q3 audit fee, accrued
      ["Payable", "Audit Fee Payable", "2026-09-30", 30_000, true],
      ["Portfolio FMV", "Investments at FMV", "2025-12-31", 8_000_000, true],
      ["Portfolio FMV", "Investments at FMV", "2026-06-30", 8_800_000, true],
      ["Portfolio FMV", "Investments at FMV", "2026-09-30", 9_200_000, true],
      ["Portfolio FMV", "Unrealised Gain", "2025-12-31", 800_000, false],
      ["Portfolio FMV", "Unrealised Gain", "2026-06-30", 800_000, false],
      ["Portfolio FMV", "Unrealised Gain", "2026-09-30", 400_000, false],
      ["NAV", "NAV Post Carry", "2026-09-30", 9_766_700, true]
    ]

    # [name, type, flip]
    accounts = [
      ["Investments at fair value", "asset", false], ["Cash", "asset", false],
      ["Accrued expenses", "liability", false],
      ["Contributions", "capital", false], ["Distributions", "capital", true],
      ["Dividend income", "income", false], ["Interest income", "income", false],
      ["Management fees", "expense", false], ["Professional fees", "expense", false],
      ["Change in unrealised gain", "gain_loss", false]
    ]
    # [entry_type, name ("" = any), account or :excluded]
    rules = [
      ["Portfolio FMV", "Investments at FMV", "Investments at fair value"], ["Cash", "", "Cash"],
      ["Payable", "", "Accrued expenses"], ["Capital Remittance", "Contribution", "Contributions"],
      ["Capital Distribution", "Distribution", "Distributions"], ["Income", "Dividend", "Dividend income"],
      ["Income", "Interest", "Interest income"], ["Fees", "Management Fee", "Management fees"],
      ["Non Deal Expense", "Audit Fees", "Professional fees"], ["Non Deal Expense", "Legal Fees", "Professional fees"],
      ["Portfolio FMV", "Unrealised Gain", "Change in unrealised gain"], ["NAV", "", :excluded]
    ]

    puts "Entity #{entity.id} #{entity.name}; user #{user.id} #{user.email}"
    puts "Fund: #{fund_name} (USD) — #{entries.size} fund-level entries, #{accounts.size} accounts, #{rules.size} rules,"
    puts "accounting runs 01/04/2026–30/06/2026 and 01/07/2026–30/09/2026 (Success, locked)."
    unless execute
      puts "Dry run. Add EXECUTE=1 to create it."
      next
    end

    # Search indexing is skipped for the demo records (as AccountEntryAllocationJob does)
    Chewy.strategy(:bypass) do
      ActiveRecord::Base.transaction do
        fund = Fund.create!(entity:, name: fund_name, currency: "USD", unit_types: "A", details: "Demo fund for financial statements")
        entries.each do |type, name, date, amount, cumulative|
          AccountEntry.create!(entity:, fund:, entry_type: type, name:, reporting_date: Date.parse(date), amount_cents: amount * 100,
                               cumulative:, notes: "financial_statements:demo")
        end

        # Settings, core statements (with starter layouts) and the statement formula
        setup = FinancialStatementSetup.new(fund)
        setup.ensure!
        fund.reload.financial_statement_setting.update!(fiscal_year_start_month: 1, nav_entry_type: "NAV", nav_entry_name: "NAV Post Carry")
        by_name = accounts.to_h do |name, type, flip|
          account = FinancialStatementAccount.create!(fund:, entity:, name:, account_type: type, flip_sign: flip)
          # Placed under its section of the Balance Sheet / P&L (capital also on the Changes statement)
          setup.place_account(account)
          [name, account]
        end
        rules.each do |type, name, target|
          FinancialStatementMappingRule.create!(fund:, entity:, entry_type: type, name:, excluded: target == :excluded,
                                                account: target == :excluded ? nil : by_name.fetch(target))
        end

        # The accounting runs Generate needs (no formulas are run; they only mark the periods done)
        [%w[2026-04-01 2026-06-30], %w[2026-07-01 2026-09-30]].each do |from, to|
          # Created unlocked (as the allocate screen does, rule engine skipped), then locked by flag: the
          # default rule "allocation_run_already_locked" refuses saving a run whose locked is true
          run = WithValidationRules.skip do
            AllocationRun.create!(entity:, fund:, user:, start_date: Date.parse(from), end_date: Date.parse(to), run_allocations: true,
                                  status: "Success")
          end
          run.update_column(:locked, true)
        end
        puts "Created fund #{fund.id}. Open: /financial_statements?fund_id=#{fund.id}"
      end
    end
  end
end

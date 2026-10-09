# Sets up a fund for trying the AI-drafted mapping (development / staging only):
#   - a USD fund with fund-level account entries for 2025 and Jan–Sep 2026 that balance;
#   - locked successful accounting runs for Q2 and Q3 2026 (so you can Generate after approving);
#   - NO financial statement set-up — you start from "Suggest from statements";
#   - fake FY 2025 financial statements of that fund, as a PDF and an Excel file, that agree with the
#     entries, for you to upload.
#
# One deliberate gap to exercise the review screen: the statements print "Other expenses 1,150",
# which comes from an entry "Tax / TDS". If the AI doesn't place it, that line shows ⚠ and TDS is
# listed under "Entries not placed on any line" — move it to Other expenses and the line turns ✓.
# In Q3 2026 "Non Deal Expense / Director Fees" (8,000) is new, so after approving it appears as
# Unmapped when you preview or generate Q3 2026.
#
#   bin/rails financial_statements:demo_ai ENTITY_ID=12                       # dry run
#   bin/rails financial_statements:demo_ai ENTITY_ID=12 USER_ID=34 EXECUTE=1  # creates "FS AI Demo Fund" + files
#
# The AI call itself needs an AI key: the entity's own (entity settings) or the app credentials.
# See docs/user_guides/financial_statements_user_guide.md ("Starting from last year's statements").
namespace :financial_statements do
  desc "Create a fund and fake FY2025 statements for testing the AI-drafted mapping (dev/staging)"
  task demo_ai: :environment do
    # Never on production data
    abort "Refusing to run in production." if Rails.env.production?

    entity = Entity.find(ENV.fetch("ENTITY_ID"))
    user = ENV["USER_ID"].present? ? User.find(ENV["USER_ID"]) : entity.employees.order(:id).first
    abort "No user: pass USER_ID (an employee of entity #{entity.id})." unless user

    fund_name = ENV.fetch("FUND_NAME", "FS AI Demo Fund")
    execute = ENV["EXECUTE"] == "1"
    out_dir = Rails.root.join("tmp/financial_statements_demo")

    # [entry_type, name, date, amount] movements; cash mirrors each (in for contributions / income, out otherwise)
    flows = [
      ["Capital Remittance", "Contribution", "2025-01-15", 10_000_000],
      ["Income", "Dividend", "2025-11-30", 50_000], ["Income", "Interest", "2025-12-31", 22_000],
      ["Income", "Dividend", "2026-03-31", 6_000], ["Income", "Interest", "2026-03-31", 3_800],
      ["Income", "Dividend", "2026-06-30", 12_500], ["Income", "Interest", "2026-06-30", 4_000],
      ["Income", "Dividend", "2026-09-30", 12_000], ["Income", "Interest", "2026-09-30", 4_100],
      ["Non Deal Expense", "Audit Fees", "2025-12-31", 60_000], ["Non Deal Expense", "Legal Fees", "2025-12-31", 28_400],
      # The deliberate gap: printed as "Other expenses" on the FY 2025 statements
      ["Tax", "TDS", "2025-12-31", 1_150],
      ["Non Deal Expense", "Audit Fees", "2026-03-31", 30_000], ["Non Deal Expense", "Legal Fees", "2026-06-30", 26_100],
      ["Non Deal Expense", "Legal Fees", "2026-09-30", 15_200], ["Non Deal Expense", "Director Fees", "2026-09-30", 8_000],
      ["Capital Distribution", "Distribution", "2026-08-15", 400_000]
    ]
    %w[2025-03-31 2025-06-30 2025-09-30 2025-12-31 2026-03-31 2026-06-30 2026-09-30].each { |d| flows << ["Fees", "Management Fee", d, 250_000] }

    entries = flows.map { |t, n, d, a| [t, n, d, a, false] }
    flows.each do |type, _name, date, amount|
      sign = ["Capital Remittance", "Income"].include?(type) ? 1 : -1
      entries << ["Cash", "Bank Balance", date, sign * amount, false]
    end
    # FY 2025 closes at: investments 8,000,000 + cash 1,782,450 = 9,782,450 = partners' capital
    # (10,000,000 − 217,550 net result). Q3 2026 closes at 9,765,550 (Director Fees included).
    entries += [
      ["Cash", "Bank Balance", "2025-02-01", -7_200_000, false],
      ["Non Deal Expense", "Audit Fees", "2026-09-30", 30_000, false],
      ["Payable", "Audit Fee Payable", "2026-09-30", 30_000, true],
      ["Portfolio FMV", "Investments at FMV", "2025-12-31", 8_000_000, true],
      ["Portfolio FMV", "Investments at FMV", "2026-06-30", 8_800_000, true],
      ["Portfolio FMV", "Investments at FMV", "2026-09-30", 9_200_000, true],
      ["Portfolio FMV", "Unrealised Gain", "2025-12-31", 800_000, false],
      ["Portfolio FMV", "Unrealised Gain", "2026-06-30", 800_000, false],
      ["Portfolio FMV", "Unrealised Gain", "2026-09-30", 400_000, false],
      ["NAV", "NAV Post Carry", "2025-12-31", 9_782_450, true],
      ["NAV", "NAV Post Carry", "2026-09-30", 9_765_550, true]
    ]

    puts "Entity #{entity.id} #{entity.name}; user #{user.id} #{user.email}"
    puts "Fund: #{fund_name} (USD) — #{entries.size} fund-level entries, accounting runs Q2 + Q3 2026 (Success, locked),"
    puts "no statement set-up; fake FY 2025 statements (PDF + Excel) written to #{out_dir}."
    unless execute
      puts "Dry run. Add EXECUTE=1 to create it."
      next
    end

    fund = nil
    # Search indexing is skipped for the demo records (as AccountEntryAllocationJob does)
    Chewy.strategy(:bypass) do
      ActiveRecord::Base.transaction do
        fund = Fund.create!(entity:, name: fund_name, currency: "USD", unit_types: "A", details: "Demo fund for the AI-drafted statement mapping")
        entries.each do |type, name, date, amount, cumulative|
          AccountEntry.create!(entity:, fund:, entry_type: type, name:, reporting_date: Date.parse(date), amount_cents: amount * 100,
                               cumulative:, notes: "financial_statements:demo_ai")
        end
        # Created unlocked with the rule engine skipped (as the allocate screen does), then locked by flag:
        # the default rule "allocation_run_already_locked" refuses saving a run whose locked is true
        [%w[2026-04-01 2026-06-30], %w[2026-07-01 2026-09-30]].each do |from, to|
          run = WithValidationRules.skip do
            AllocationRun.create!(entity:, fund:, user:, start_date: Date.parse(from), end_date: Date.parse(to), run_allocations: true,
                                  status: "Success")
          end
          run.update_column(:locked, true)
        end
      end
    end

    # The fake FY 2025 statements, as the fund's auditors might have printed them
    FileUtils.mkdir_p(out_dir)
    base = out_dir.join("#{fund.id}_#{fund_name.parameterize}_FY2025_statements")
    File.binwrite("#{base}.pdf", FinancialStatementsDemoAi.pdf(fund_name))
    FinancialStatementsDemoAi.xlsx(fund_name).serialize("#{base}.xlsx")

    puts "Created fund #{fund.id}."
    puts "Statements to upload:\n  #{base}.pdf\n  #{base}.xlsx"
    puts "Next: open /financial_statements?fund_id=#{fund.id} → Suggest from statements → upload one file,"
    puts "      Statements as at 31/12/2025, P&L period from 01/01/2025 → Read the statements."
  end
end

# The fake statements' content and rendering (PDF via FerrumPdf, as the app's own PDFs; Excel via caxlsx).
# Figures agree with the demo_ai entries at 31 Dec 2025.
module FinancialStatementsDemoAi
  # [label, amount or nil (heading), style] — style: :heading, :line, :total
  STATEMENTS = {
    "Statement of Assets, Liabilities and Partners' Capital as at 31 December 2025" => [
      ["Assets", nil, :heading], ["Investments at fair value", 8_000_000, :line], ["Cash and cash equivalents", 1_782_450, :line],
      ["Total assets", 9_782_450, :total],
      ["Liabilities", nil, :heading], ["Total liabilities", 0, :total],
      ["Net assets", 9_782_450, :total],
      ["Partners' capital", nil, :heading], ["Contributions", 10_000_000, :line], ["Accumulated net result", -217_550, :line],
      ["Total partners' capital", 9_782_450, :total]
    ],
    "Statement of Operations for the year ended 31 December 2025" => [
      ["Investment income", nil, :heading], ["Dividend income", 50_000, :line], ["Interest income", 22_000, :line],
      ["Total investment income", 72_000, :total],
      ["Expenses", nil, :heading], ["Management fees", 1_000_000, :line], ["Professional fees", 88_400, :line],
      ["Other expenses", 1_150, :line], ["Total expenses", 1_089_550, :total],
      ["Net investment loss", -1_017_550, :total],
      ["Net change in unrealised gain on investments", 800_000, :line],
      ["Net decrease in net assets from operations", -217_550, :total]
    ],
    "Statement of Changes in Partners' Capital for the year ended 31 December 2025" => [
      ["Partners' capital, beginning of year", 0, :line], ["Capital contributions", 10_000_000, :line],
      ["Net decrease in net assets from operations", -217_550, :line],
      ["Partners' capital, end of year", 9_782_450, :total]
    ]
  }.freeze
  ROW_CSS = { heading: "h", line: "l", total: "t" }.freeze
  SHEET_NAMES = ["Balance Sheet", "Operations", "Changes in Capital"].freeze

  def self.money(value)
    return "" if value.nil?

    text = ActiveSupport::NumberHelper.number_to_delimited(value.abs)
    value.negative? ? "(#{text})" : text
  end

  def self.html(fund_name)
    sections = STATEMENTS.map do |title, rows|
      body = rows.map do |label, amount, style|
        css = ROW_CSS[style]
        "<tr class='#{css}'><td>#{ERB::Util.h(label)}</td><td class='n'>#{money(amount)}</td></tr>"
      end.join
      "<section><h2>#{ERB::Util.h(title)}</h2><table><tr><th></th><th class='n'>2025<br>USD</th></tr>#{body}</table></section>"
    end.join
    <<~HTML
      <html><head><meta charset="utf-8"><style>
        body { font-family: Georgia, serif; font-size: 12px; color: #111; margin: 36px; }
        h1 { font-size: 18px; margin: 0 0 4px; } .sub { color: #555; margin-bottom: 24px; }
        h2 { font-size: 14px; margin: 28px 0 8px; border-bottom: 1px solid #333; padding-bottom: 4px; }
        table { width: 100%; border-collapse: collapse; } td, th { padding: 3px 4px; } .n { text-align: right; width: 140px; }
        tr.h td { font-weight: bold; padding-top: 10px; } tr.l td:first-child { padding-left: 18px; }
        tr.t td { font-weight: bold; border-top: 1px solid #333; }
        section { page-break-inside: avoid; } .note { margin-top: 30px; color: #555; font-size: 10px; }
      </style></head><body>
        <h1>#{ERB::Util.h(fund_name)}</h1>
        <div class="sub">Audited financial statements — year ended 31 December 2025 · All amounts in US Dollars</div>
        #{sections}
        <div class="note">The accompanying notes are an integral part of these financial statements. (Demo document generated for testing.)</div>
      </body></html>
    HTML
  end

  def self.pdf(fund_name)
    FerrumPdf.browser(timeout: 60)
    FerrumPdf.render_pdf(html: html(fund_name), pdf_options: { format: :A4, print_background: true })
  end

  def self.xlsx(fund_name)
    package = Axlsx::Package.new
    bold = package.workbook.styles.add_style(b: true)
    number = package.workbook.styles.add_style(format_code: "#,##0;(#,##0)")
    total = package.workbook.styles.add_style(b: true, format_code: "#,##0;(#,##0)")
    STATEMENTS.each_with_index do |(title, rows), i|
      package.workbook.add_worksheet(name: SHEET_NAMES[i]) do |sheet|
        sheet.add_row [fund_name], style: bold
        sheet.add_row [title], style: bold
        sheet.add_row ["", "2025 (USD)"], style: bold
        rows.each do |label, amount, style|
          sheet.add_row [style == :line ? "  #{label}" : label, amount], style: [style == :line ? nil : bold, style == :total ? total : number]
        end
        sheet.column_widths 60, 18
      end
    end
    package
  end
end

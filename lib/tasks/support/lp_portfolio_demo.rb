# Builds a self-contained demo of the LP folio portfolio & company dashboard feature, for reviewing the screens by
# hand (openspec/changes/lp-folio-portfolio-dashboard). Development / staging data only.
#
# It creates its own fund manager entity (so its entity-wide LP layouts never touch a real one) with:
#   - a fund team user (Meera) and two LP users (Ravi: one folio; Priya: two folios)
#   - Growth Fund I (INR) on "Allocated, with their own share", with the allocation and Your FMV formulas
#   - five portfolio companies bought through PortfolioInvestmentCreate and valued (EvergreenDemoPortfolio)
#   - folio allocation entries matching business-rules.md#shared-setup (Ravi excused from Bluefin)
#   - Actual and Budget KPIs, a founder video, the LP layouts "LP" and "LP, FinTech" and an internal Default
#   - company switches: Acme, Bluefin, Paywise, Fenix shared; Cedar not shared (to see "not shared yet")
# Re-running reuses everything that already exists and prints the review URLs again.
require_relative "evergreen_demo_portfolio"
require_relative "evergreen_demo_fund"

class LpPortfolioDemo
  ENTITY_NAME = "LP Portfolio Demo Capital".freeze
  DOMAIN = "lp-portfolio-demo.example.com".freeze
  PASSWORD = "password".freeze
  FUND_NAME = "Growth Fund I (LP demo)".freeze
  CRORE_CENTS = 1_000_000_000
  AS_OF = Date.new(2026, 9, 30)

  # company, instrument, purchases [[shares, cost ₹ Cr]], per-share value ₹, tags, shared with LPs?
  HOLDINGS = [
    ["Acme Robotics", "Series B CCPS", [[40_000, 10.0], [60_000, 15.0]], 4_000, "Robotics", true],
    ["Bluefin Health", "Series A CCPS", [[80_000, 20.0]], 2_750, "HealthTech", true],
    ["Cedar Logistics", "Series A CCPS", [[50_000, 15.0]], 3_600, "", false],
    ["Paywise Payments", "Series A CCPS", [[30_000, 6.0]], 3_000, "Fintech, NBFC", true],
    ["Fenix Mobility", "Seed CCPS", [[50_000, 5.0]], 1_000, "", true],
    ["Fenix Mobility", "Series A CCPS", [[40_000, 8.0]], 2_000, "", true]
  ].freeze

  # Shown by the Data Card widget
  SECTORS = { "Acme Robotics" => "Industrial Robotics", "Bluefin Health" => "HealthTech", "Cedar Logistics" => "Logistics",
              "Paywise Payments" => "Fintech", "Fenix Mobility" => "EV Mobility" }.freeze

  # LP name, first name, folios [[folio_id, committed ₹ Cr]]
  LPS = [["Ravi Menon", "Ravi", [["F-012", 10]]], ["Priya Shah", "Priya", [["F-050", 5], ["F-051", 5]]]].freeze

  # folio, formula (:cost / :fmv), company, instrument, purchase (1-based), ₹ Cr — business-rules.md#shared-setup
  ENTRIES = [
    ["F-012", :cost, "Acme Robotics", "Series B CCPS", 1, 1.00], ["F-012", :cost, "Acme Robotics", "Series B CCPS", 2, 1.50],
    ["F-012", :fmv, "Acme Robotics", "Series B CCPS", 1, 4.00],
    ["F-012", :cost, "Cedar Logistics", "Series A CCPS", 1, 1.50], ["F-012", :fmv, "Cedar Logistics", "Series A CCPS", 1, 1.80],
    ["F-012", :cost, "Bluefin Health", "Series A CCPS", 1, 0.00], # excused
    ["F-050", :cost, "Acme Robotics", "Series B CCPS", 1, 1.00], ["F-050", :fmv, "Acme Robotics", "Series B CCPS", 1, 1.20],
    ["F-050", :cost, "Bluefin Health", "Series A CCPS", 1, 0.00], # excused
    ["F-051", :cost, "Acme Robotics", "Series B CCPS", 1, 0.50], ["F-051", :fmv, "Acme Robotics", "Series B CCPS", 1, 0.60],
    ["F-051", :cost, "Bluefin Health", "Series A CCPS", 1, 1.00], ["F-051", :fmv, "Bluefin Health", "Series A CCPS", 1, 1.10],
    ["F-051", :cost, "Paywise Payments", "Series A CCPS", 1, 0.30], ["F-051", :fmv, "Paywise Payments", "Series A CCPS", 1, 0.45],
    ["F-051", :cost, "Fenix Mobility", "Series A CCPS", 1, 0.40], ["F-051", :fmv, "Fenix Mobility", "Series A CCPS", 1, 0.40]
  ].freeze

  # layout name -> [[widget, size, metadata]]; a method, as app constants aren't loaded when rake reads this file
  def layouts
    data_card = DashboardWidget::LP_STARTER_METADATA["Data Card"]
    {
      "LP" => [["Data Card", "Medium", data_card], ["Key Kpis", "Medium", nil], ["Kpis", "XL", nil], ["Valuations", "XL", nil],
               ["Portfolio Stats", "XL", nil], ["Embed Document", "XL", "{name: 'Founder Video'}"]],
      "LP, FinTech" => [["Data Card", "Medium", data_card], ["Kpis", "XL", nil], ["Portfolio Investments", "XL", nil]],
      "Default" => [["Data Card", "Medium", data_card], ["Notes", "XL", nil], ["Captable", "XL", nil], ["Kpis", "XL", nil]]
    }
  end

  def initialize(execute:, out: $stdout, host: "http://localhost:3000")
    @execute = execute
    @out = out
    @host = host
  end

  def run
    print_plan
    return say("DRY RUN — nothing created. Set EXECUTE=1 to build it.") unless @execute

    # Inline jobs (valuations recompute FMV) and no emails, as the other demo tasks do
    quietly { build }
    print_urls
  end

  private

  def print_plan
    say("LP portfolio demo: entity \"#{ENTITY_NAME}\", fund \"#{FUND_NAME}\", #{HOLDINGS.size} holdings, LPs #{LPS.map(&:first).join(', ')}, " \
        "layouts LP / LP, FinTech / Default; every login's password is \"#{PASSWORD}\"")
  end

  def build
    @entity = Entity.find_by(name: ENTITY_NAME) || create_entity
    @fm_user = fm_user
    @fund = @entity.funds.find_by(name: FUND_NAME)
    return say("  Already seeded — reusing fund #{@fund.id}") if @fund

    create_fund
    create_holdings
    create_lps
    create_entries
    configure_fund_view
    create_kpis
    create_documents_and_switches
    create_layouts
    say("  Built fund #{@fund.id}")
  end

  # ---------- Fund manager ----------

  def create_entity
    entity = Entity.create!(name: ENTITY_NAME, entity_type: "Investment Fund", primary_email: "ops@#{DOMAIN}", currency: "INR", units: "Crores")
    %i[enable_funds enable_units enable_fund_portfolios enable_investors enable_kycs enable_documents enable_account_entries enable_kpis]
      .each { |p| entity.permissions.set(p) }
    entity.save!(validate: false)
    entity
  end

  def fm_user
    User.find_by(email: "meera@#{DOMAIN}") || new_user(@entity, "Meera", "Iyer", "meera@#{DOMAIN}", permissions: User.permissions.keys).tap do |user|
      %i[company_admin approver].each { |role| user.add_role(role) }
    end
  end

  def new_user(entity, first_name, last_name, email, permissions: nil)
    attrs = { entity:, first_name:, last_name:, email:, password: PASSWORD, call_code: "91", phone: "9876543210", accept_terms: true }
    attrs[:permissions] = permissions if permissions
    User.create!(attrs)
  end

  # ---------- Fund and holdings ----------

  def create_fund
    @fund = Fund.create!(entity: @entity, name: FUND_NAME, currency: "INR", unit_types: "Class A", category: "Category II",
                         start_date: Date.new(2024, 1, 1), first_close_date: Date.new(2024, 1, 1), show_portfolios: true)
    @formulas = {
      cost: formula("Allocated Portfolio Cost"),
      fmv: formula("Allocated Portfolio FMV")
    }
  end

  # The holding-level allocation formulas the LP view reads; disabled, so no allocation run rewrites the demo entries
  def formula(name)
    FundFormula.create!(fund: @fund, entity: @entity, name:, rule_type: "AllocatePortfolioInvestment", formula: "0",
                        entry_type: "Portfolio Allocation", enabled: false)
  end

  def create_holdings
    @holdings = {}
    HOLDINGS.each do |company, instrument_name, purchases, per_share, tags, _shared|
      pc = instrument = nil
      purchases.each_with_index do |(shares, crores), index|
        pc, instrument = EvergreenDemoPortfolio.buy(@fund, name: company, shares:, bought_on: Date.new(2025, 1, 1) + index.months,
                                                           cost_cents: (crores * CRORE_CENTS).round, notes: "LP portfolio demo",
                                                           instrument_name:)
      end
      pc.update!(tag_list: tags.presence, sector: SECTORS[company], city: "Bengaluru")
      shares = purchases.sum(&:first)
      EvergreenDemoPortfolio.value(@fund, pc, instrument, date: AS_OF, per_share_cents: per_share * 100, shares:)
      @holdings[[company, instrument_name]] = AggregatePortfolioInvestment.find_by!(fund: @fund, portfolio_company: pc, investment_instrument: instrument)
    end
  end

  # ---------- LPs ----------

  def create_lps
    @folios = {}
    LPS.each do |name, first_name, folios|
      lp_entity, investor = lp_investor(name)
      user = User.find_by(email: "#{first_name.downcase}@#{DOMAIN}") ||
             new_user(lp_entity, first_name, name.split.last, "#{first_name.downcase}@#{DOMAIN}")
      user.update!(curr_role: "investor")
      InvestorAccess.find_or_create_by!(investor:, email: user.email) do |ia|
        ia.entity_id = @entity.id
        ia.user = user
        ia.first_name = user.first_name
        ia.last_name = user.last_name
        ia.approved = true
      end
      AccessRight.find_or_create_by!(owner: @fund, access_type: "Fund", metadata: "Investor", access_to_investor_id: investor.id, entity_id: @entity.id)
      folios.each { |folio_id, crores| @folios[folio_id] = commitment(investor, folio_id, crores) }
    end
  end

  def lp_investor(name)
    email = "demo+#{Digest::MD5.hexdigest("lp-#{name}").first(10)}@example.com"
    lp_entity = Entity.find_by(primary_email: email) || Entity.create!(name:, entity_type: "Investor", primary_email: email)
    investor = @entity.investors.find_by(investor_name: name) ||
               @entity.investors.create!(investor_name: name, investor_entity: lp_entity, category: "LP", primary_email: email, city: "Mumbai")
    [lp_entity, investor]
  end

  def commitment(investor, folio_id, crores)
    cc = CapitalCommitment.new(entity: @entity, fund: @fund, investor:, folio_id:, unit_type: "Class A", fund_close: "First Close",
                               folio_currency: "INR", commitment_date: Date.new(2024, 1, 1),
                               orig_folio_committed_amount_cents: crores * CRORE_CENTS, onboarding_completed: true, notes: "LP portfolio demo")
    result = CapitalCommitmentCreate.call(capital_commitment: cc)
    raise "Commitment #{folio_id}: #{cc.errors.full_messages.to_sentence.presence || result[:errors]}" unless result.success?

    cc
  end

  # ---------- Folio allocation entries ----------

  def create_entries
    ENTRIES.each do |folio_id, kind, company, instrument, purchase, crores|
      cc = @folios.fetch(folio_id)
      purchase_pi = @holdings.fetch([company, instrument]).portfolio_investments.order(:id).to_a[purchase - 1]
      formula = @formulas.fetch(kind)
      AccountEntry.create!(entity: @entity, fund: @fund, capital_commitment: cc, investor: cc.investor, folio_id:, fund_formula: formula,
                           name: formula.name, entry_type: formula.entry_type, parent: purchase_pi,
                           amount_cents: (crores * CRORE_CENTS).round, reporting_date: AS_OF)
    end
  end

  def configure_fund_view
    @fund.update!(lp_portfolio_view: :allocated_with_share, lp_allocation_fund_formula: @formulas[:cost], lp_fmv_fund_formula: @formulas[:fmv])
  end

  # ---------- Company data, switches and layouts ----------

  # Acme: Actual KPIs for four quarters plus one Budget quarter (LPs must never see it); Paywise: Actual KPIs
  def create_kpis
    kpi_series("Acme Robotics", "Actual", { "Revenue" => [48.2, 52.9, 57.1, 62.0], "EBITDA" => [4.1, 5.0, 6.3, 7.4] })
    kpi_series("Acme Robotics", "Budget", { "Revenue" => [nil, nil, nil, 70.0] })
    kpi_series("Paywise Payments", "Actual", { "Loan Book" => [120.0, 138.0, 151.0, 166.0], "GNPA %" => [1.8, 1.7, 1.6, 1.5] })
  end

  def kpi_series(company, tag, kpis)
    pc = @entity.investors.portfolio_companies.find_by!(investor_name: company)
    quarters = [AS_OF - 9.months, AS_OF - 6.months, AS_OF - 3.months, AS_OF].map(&:end_of_month)
    kpis.each do |kpi_name, values|
      mapping = InvestorKpiMapping.find_or_create_by!(entity_id: @entity.id, investor: pc, standard_kpi_name: kpi_name) do |m|
        m.reported_kpi_name = kpi_name
        m.category = "Income Statement"
        m.show_in_report = true
      end
      quarters.zip(values).each do |as_of, value|
        next if value.nil?

        report = KpiReport.find_or_create_by!(entity_id: @entity.id, portfolio_company_id: pc.id, as_of:, tag_list: tag, period: "Quarter") { |r| r.user_id = @fm_user.id }
        Kpi.create!(entity_id: @entity.id, kpi_report: report, portfolio_company_id: pc.id, investor_kpi_mapping: mapping, name: kpi_name, value:)
      end
    end
  end

  def create_documents_and_switches
    acme = @entity.investors.portfolio_companies.find_by!(investor_name: "Acme Robotics")
    video = Rails.root.join("features/support/fixtures/founder_video.mp4")
    Document.create!(entity: @entity, owner: acme, name: "Founder Video", user: @fm_user, folder: acme.document_folder, file: File.new(video, "r")) if video.exist?
    HOLDINGS.each do |company, _instrument, _purchases, _per_share, _tags, shared|
      @entity.investors.portfolio_companies.find_by!(investor_name: company).update!(show_to_lps: shared)
    end
  end

  def create_layouts
    layouts.each do |layout, widgets|
      next if DashboardWidget.exists?(entity_id: @entity.id, dashboard_name: DashboardWidget::PORTFOLIO_COMPANY_DASHBOARD, name: layout)

      widgets.each_with_index do |(widget, size, metadata), index|
        DashboardWidget.create!(entity_id: @entity.id, dashboard_name: DashboardWidget::PORTFOLIO_COMPANY_DASHBOARD, name: layout,
                                widget_name: widget, size:, position: index + 1, tags: widget, metadata:, enabled: true, display_name: true)
      end
    end
  end

  # ---------- Output ----------

  def print_urls
    company = ->(name) { @entity.investors.find_by!(investor_name: name) }
    ravi = @entity.investors.find_by!(investor_name: "Ravi Menon")
    acme_holding = @holdings&.dig(["Acme Robotics", "Series B CCPS"]) ||
                   AggregatePortfolioInvestment.find_by!(fund: @fund, portfolio_company: company.call("Acme Robotics"))
    say("\nLogins (password \"#{PASSWORD}\"): fund team meera@#{DOMAIN} · LPs ravi@#{DOMAIN}, priya@#{DOMAIN}\n")
    say("Fund team (log in as Meera):")
    url("Fund › Edit › Features (LP portfolio view)", "/funds/#{@fund.id}/edit")
    url("Fund page", "/funds/#{@fund.id}")
    url("Acme company page (Show/Hide from LPs, notice, Misc › Preview as LP…)", "/investors/#{company.call('Acme Robotics').id}")
    url("Paywise company page (\"LP, FinTech\" layout notice)", "/investors/#{company.call('Paywise Payments').id}")
    url("Cedar company page (not shared — Show to LPs button)", "/investors/#{company.call('Cedar Logistics').id}")
    url("Widget settings: \"LP\" layout", "/dashboard_widgets?q[dashboard_name_eq]=Portfolio+Company+Dashboard&q[name_eq]=LP")
    url("Widget settings: \"LP, FinTech\" layout", "/dashboard_widgets?q[dashboard_name_eq]=Portfolio+Company+Dashboard&q[name_eq]=LP%2C+FinTech")
    url("Add widget to \"LP\" (LP-safe types only)", "/dashboard_widgets/new?dashboard_widget[dashboard_name]=Portfolio+Company+Dashboard&dashboard_widget[name]=LP")
    url("Preview Acme as Ravi", "/lp/portfolio_companies/#{company.call('Acme Robotics').id}/preview?investor_id=#{ravi.id}&fund_id=#{@fund.id}")
    url("Preview Bluefin as Ravi (refused — he was excused)", "/lp/portfolio_companies/#{company.call('Bluefin Health').id}/preview?investor_id=#{ravi.id}&fund_id=#{@fund.id}")
    url("Acme holding page (no Preview/Show Portfolio buttons; moved-to-company notice)", "/aggregate_portfolio_investments/#{acme_holding.id}")
    say("LPs (log in as Ravi, then Priya):")
    url("Fund page (Portfolio section)", "/funds/#{@fund.id}")
    url("Holdings list (banner, Your Cost / FMV, totals; Acme a link, Cedar plain)", "/aggregate_portfolio_investments?fund_id=#{@fund.id}")
    url("Portfolio dashboard (fund-wide charts hidden)", "/funds/#{@fund.id}/dashboard?dashboard_name=Portfolio+Dashboard")
    url("Acme company page (holdings card, \"LP\" layout, founder video)", "/lp/portfolio_companies/#{company.call('Acme Robotics').id}")
    url("Cedar company page (\"No company information has been shared yet.\")", "/lp/portfolio_companies/#{company.call('Cedar Logistics').id}")
    url("Bluefin company page (Ravi: refused · Priya: opens)", "/lp/portfolio_companies/#{company.call('Bluefin Health').id}")
    url("Paywise company page (Priya: \"LP, FinTech\" layout)", "/lp/portfolio_companies/#{company.call('Paywise Payments').id}")
    url("Fenix company page (Priya: Series A only)", "/lp/portfolio_companies/#{company.call('Fenix Mobility').id}")
    url("Old holding link (redirects to the company page)", "/aggregate_portfolio_investments/#{acme_holding.id}?preview=true")
  end

  def url(label, path)
    say("  #{label}\n    #{@host}#{path}")
  end

  def quietly(&)
    adapter = ActiveJob::Base.queue_adapter
    deliveries = ActionMailer::Base.perform_deliveries
    ActiveJob::Base.queue_adapter = EvergreenDemoFund::InlineDropDelayedAdapter.new(method(:say))
    ActionMailer::Base.perform_deliveries = false
    yield
  ensure
    ActiveJob::Base.queue_adapter = adapter
    ActionMailer::Base.perform_deliveries = deliveries
  end

  def say(msg)
    @out.puts(msg)
  end
end

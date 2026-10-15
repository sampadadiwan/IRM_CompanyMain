# Demo portfolio-company data for lib/tasks/portco_demo.rake. Development / staging data only.
#
# For each company: 12 quarters of KPIs (5 income statement, 3 balance sheet, 2 operational), 6 half-yearly
# per-share valuations and generated PDFs (IC note, board minutes, investor presentations, annual summaries).
# With a USD fund it also creates the records the two US sample documents describe — Harborview's commitment
# (side letter) and the fund's Aster Labs secondary purchase (stock purchase agreement).
#
# Every figure comes from a per-company seeded Random, so re-runs and dry runs print the same numbers.
require "hexapdf"
require_relative "evergreen_demo_portfolio"

module PortcoDemo
  CRORE = 10_000_000
  MILLION = 1_000_000
  # Profiles are written in USD millions a quarter; an INR company is scaled by this rough rate
  INR_PER_USD = 85

  # The sample documents in public/sample_uploads and the records they describe
  SIDE_LETTER = {
    file: "public/sample_uploads/US_Growth_Fund_LP_Side_Letter.docx", investor: "Harborview Institutional Investments LLC",
    folio_id: "HARBORVIEW-01", date: Date.new(2026, 9, 30)
  }.freeze
  SPA = {
    file: "public/sample_uploads/US_Stock_Purchase_Agreement_CP_CS.docx", company: "Aster Labs, Inc.",
    shares: 250_000, price: 2.50, date: Date.new(2026, 9, 30), issued_shares: 9_000_000
  }.freeze

  # The fund's demo LPs: [name, folio id, commitment in USD millions (scaled for INR), city]. A USD fund's
  # first LP is Harborview, whose commitment carries the side letter; every LP gets a verified KYC.
  LPS = {
    usd: [[SIDE_LETTER[:investor], SIDE_LETTER[:folio_id], 1.0, "Wilmington"], ["Crescent Public Pension Trust", "DEMO-LP-01", 2.0, "Sacramento"],
          ["Maple Ridge Family Office LLC", "DEMO-LP-02", 1.5, "Boston"], ["Alder University Endowment", "DEMO-LP-03", 0.75, "New Haven"]],
    inr: [["Vridhi Insurance Co Ltd", "DEMO-LP-01", 1.0, "Mumbai"], ["Sundaram Family Trust", "DEMO-LP-02", 2.0, "Chennai"],
          ["Aravalli Family Office LLP", "DEMO-LP-03", 1.5, "Jaipur"], ["Kaveri Endowment Trust", "DEMO-LP-04", 0.75, "Bengaluru"]]
  }.freeze

  # One profile per sector. Money is USD millions a quarter; ops are [label, base, quarterly growth, :stock|:flow].
  # cost: the sector's cost-of-sales label (standard KPI "COGS"); var: other variable costs (% of revenue);
  # fixed: quarterly fixed opex; raise: [quarter index, amount]; basis: :revenue (EV/TTM revenue) or :book (P/B);
  # markdown: [valuation index, factor] for a company that takes a down-round.
  PROFILES = [
    { name: { inr: SPA[:company], usd: SPA[:company] }, sector: "B2B SaaS", cost: "Cost of Revenue",
      rev: 0.55, growth: 0.07, seasonality: {}, cogs: [0.24, 0.20], var: [0.18, 0.14], fixed: 0.45, fixed_growth: 0.03, da: 0.03,
      equity: 6.0, liabilities: 1.2, liab_growth: 0.03, raise: nil, shares: SPA[:issued_shares], basis: :revenue, multiple: 7.0,
      ops: [["Paying Customers", 140, 0.06, :stock], ["Employees", 48, 0.03, :stock]],
      thesis: ["Vertical workflow software with net revenue retention above 115%", "Land-and-expand motion inside mid-market accounts",
               "Path to EBITDA breakeven within eight quarters without further dilution"],
      risks: [["Enterprise sales cycles lengthen", "Self-serve tier and partner channel"],
              ["Key engineering attrition", "ESOP refresh and senior hiring plan"]] },
    { name: { inr: "Kirana Fresh Retail Pvt Ltd", usd: "FreshCart Markets Inc." }, sector: "Grocery Retail", cost: "COGS",
      rev: 7.0, growth: 0.045, seasonality: { 12 => 1.12, 3 => 0.97, 6 => 0.95, 9 => 0.98 }, cogs: [0.78, 0.76], var: [0.085, 0.08],
      fixed: 0.95, fixed_growth: 0.02, da: 0.02, equity: 9.0, liabilities: 6.0, liab_growth: 0.03, raise: [5, 6.0],
      shares: 12_000_000, basis: :revenue, multiple: 1.6, ops: [["Store Count", 120, 0.05, :stock], ["Orders", 1_450_000, 0, :flow]],
      thesis: ["Dense neighbourhood store network with sub-30-minute delivery", "Private label mix rising from 8% to 15% of sales",
               "Store-level payback under 24 months"],
      risks: [["Quick-commerce price competition", "Private label margins and loyalty programme"],
              ["Store rollout execution", "Cluster-based expansion and standard store format"]] },
    { name: { inr: "Tandoor Express Foods Pvt Ltd", usd: "Ember Grill Restaurants Inc." }, sector: "QSR / Restaurants",
      cost: "Food & Packaging Cost", rev: 3.2, growth: 0.05, seasonality: { 12 => 1.08, 3 => 0.95, 6 => 0.97, 9 => 1.0 },
      cogs: [0.32, 0.30], var: [0.34, 0.34], fixed: 0.95, fixed_growth: 0.025, da: 0.04, equity: 7.0, liabilities: 3.0,
      liab_growth: 0.02, raise: [7, 5.0], shares: 15_000_000, basis: :revenue, multiple: 2.8,
      ops: [["Outlet Count", 85, 0.05, :stock], ["Orders", 2_100_000, 0, :flow]],
      thesis: ["Profitable unit economics at outlet level from month six", "Delivery share balanced with dine-in footfall",
               "Central kitchens support expansion into new cities"],
      risks: [["Food inflation", "Menu engineering and annual supplier contracts"],
              ["Aggregator commission increases", "Own app ordering and loyalty"]] },
    { name: { inr: "Urban Loom D2C Pvt Ltd", usd: "Threadline Apparel Inc." }, sector: "D2C Consumer Brand", cost: "COGS",
      rev: 2.4, growth: 0.06, seasonality: { 12 => 1.2, 3 => 0.9, 6 => 0.92, 9 => 1.05 }, cogs: [0.42, 0.39], var: [0.40, 0.34],
      fixed: 0.42, fixed_growth: 0.02, da: 0.015, equity: 5.0, liabilities: 1.5, liab_growth: 0.02, raise: [4, 4.0],
      shares: 20_000_000, basis: :revenue, multiple: 2.2, ops: [["Orders", 210_000, 0, :flow], ["Employees", 160, 0.02, :stock]],
      thesis: ["Repeat purchase rate above 40% within 12 months", "Marketing spend falling as a share of revenue",
               "Offline shop-in-shops extend reach at low capex"],
      risks: [["Rising customer acquisition costs", "CRM-led retention and referral programme"],
              ["Inventory build-up", "Weekly sell-through reviews and drop-based launches"]] },
    { name: { inr: "Sahaay Finserv Ltd", usd: "Keystone Credit Corp." }, sector: "Lending / NBFC", cost: "Interest Expense",
      rev: 2.0, growth: 0.06, seasonality: {}, cogs: [0.45, 0.42], var: [0.12, 0.12], fixed: 0.48, fixed_growth: 0.03, da: 0.01,
      equity: 12.0, liabilities: 40.0, liab_growth: 0.06, raise: [8, 10.0], shares: 25_000_000, basis: :book, multiple: 2.4,
      ops: [["Active Borrowers", 38_000, 0.06, :stock], ["Employees", 420, 0.03, :stock]],
      thesis: ["Secured small-business loans with gross NPA below 2%", "Diversified borrowing from banks and capital markets",
               "Branch-light origination keeps opex-to-AUM falling"],
      risks: [["Asset quality in a downturn", "Collateral cover and early-warning collections"],
              ["Cost of funds rising", "Longer-tenor borrowing and rating upgrade"]] },
    { name: { inr: "SwiftRoute Logistics Pvt Ltd", usd: "Relay Freight Inc." }, sector: "Logistics", cost: "Line-haul Cost",
      rev: 4.5, growth: 0.05, seasonality: { 12 => 1.1, 3 => 0.96, 6 => 0.95, 9 => 1.0 }, cogs: [0.62, 0.60], var: [0.14, 0.14],
      fixed: 0.85, fixed_growth: 0.02, da: 0.03, equity: 8.0, liabilities: 5.0, liab_growth: 0.03, raise: [6, 6.0],
      shares: 18_000_000, basis: :revenue, multiple: 1.5, ops: [["Shipments", 3_200_000, 0, :flow], ["Hubs", 42, 0.04, :stock]],
      thesis: ["Asset-light network with contracted enterprise volumes", "Hub automation lowers cost per shipment each year",
               "Cross-sell of warehousing to existing shippers"],
      risks: [["Fuel price swings", "Fuel surcharge clauses in customer contracts"],
              ["Customer concentration", "Mid-market sales team and SME self-serve"]] },
    { name: { inr: "CareFirst Clinics Pvt Ltd", usd: "Northside Health Clinics Inc." }, sector: "Healthcare Clinics",
      cost: "Consumables & Doctor Fees", rev: 1.8, growth: 0.055, seasonality: {}, cogs: [0.36, 0.34], var: [0.22, 0.22],
      fixed: 0.45, fixed_growth: 0.03, da: 0.05, equity: 6.0, liabilities: 2.5, liab_growth: 0.02, raise: [5, 4.0],
      shares: 10_000_000, basis: :revenue, multiple: 3.0, ops: [["Clinics", 28, 0.045, :stock], ["Patient Visits", 95_000, 0, :flow]],
      thesis: ["Primary-care clinics with diagnostics and pharmacy attached", "Clinic breakeven within nine months of opening",
               "Corporate health contracts add predictable volume"],
      risks: [["Doctor retention", "Revenue-share model and academic tie-ups"],
              ["Regulatory changes on pricing", "Diversified service mix"]] },
    { name: { inr: "SkillSprout EdTech Pvt Ltd", usd: "BrightPath Learning Inc." }, sector: "EdTech",
      cost: "Content & Delivery Cost", rev: 1.6, growth: 0.03, seasonality: { 6 => 1.15, 3 => 1.05, 9 => 0.92, 12 => 0.88 },
      cogs: [0.28, 0.28], var: [0.45, 0.38], fixed: 0.40, fixed_growth: 0.01, da: 0.02, equity: 9.0, liabilities: 1.5,
      liab_growth: 0.0, raise: nil, shares: 14_000_000, basis: :revenue, multiple: 4.0, markdown: [2, 0.6],
      ops: [["Paid Learners", 46_000, 0, :flow], ["Employees", 310, -0.02, :stock]],
      thesis: ["Outcome-linked upskilling courses with employer placement tie-ups", "Hybrid delivery lowers content cost per learner",
               "B2B academies diversify away from consumer demand"],
      risks: [["Post-pandemic demand slowdown", "Shift to B2B and placement-linked pricing"],
              ["High marketing spend", "Performance-marketing caps and alumni referrals"]] }
  ].freeze

  BOARD_POOL = ["Ananya Rao", "Vikram Mehta", "Sarah Collins", "David Chen", "Priya Nair", "Michael Torres", "Rohan Kapoor",
                "Emily Watson", "Arjun Sethi", "Laura Bennett", "Karan Malhotra", "James Whitaker"].freeze

  # The last N completed calendar quarter-ends before today (oldest first)
  def self.quarter_ends(today, count = 12)
    last = (today.beginning_of_quarter - 1.day)
    (0...count).map { |n| (last - (n * 3).months).end_of_month }.reverse
  end

  # The last N half-year valuation dates on or before today (oldest first): the fiscal half-year ends,
  # 31 Mar / 30 Sep for INR and 30 Jun / 31 Dec for the calendar year
  def self.half_year_ends(today, units, count = 6)
    months = units.inr? ? [3, 9] : [6, 12]
    dates = []
    date = today.end_of_month
    while dates.size < count
      dates << date if months.include?(date.month) && date <= today
      date = (date - 1.month).end_of_month
    end
    dates.reverse
  end

  # Currency-aware formatting and labels. INR companies report in crores on an April–March fiscal year;
  # everything else in millions on the calendar year.
  class Units
    attr_reader :currency

    def initialize(currency)
      @currency = currency
    end

    def inr? = currency == "INR"
    # Rough scale from the profiles' USD millions into absolute units of this currency
    def scale = MILLION * (inr? ? INR_PER_USD : 1)
    def denomination = inr? ? "crores" : "millions"
    def divisor = inr? ? CRORE : MILLION

    # "Rs 25.42 Cr" / "USD 3.21M" — ASCII only, the PDFs use the built-in Helvetica (no rupee glyph)
    def money(value)
      amount = format("%.2f", value.to_f / divisor)
      inr? ? "Rs #{amount} Cr" : "#{currency} #{amount}M"
    end

    # Exact amount, for deal terms: "USD 625,000"
    def amount(value) = "#{inr? ? 'Rs' : currency} #{value.round.to_fs(:delimited)}"

    def per_share(value) = inr? ? "Rs #{format('%.2f', value)}" : "#{currency} #{format('%.2f', value)}"

    # Fiscal year a quarter-end belongs to: FY ending March for INR, the calendar year otherwise
    def fiscal_year(date) = inr? && date.month > 3 ? date.year + 1 : date.year
    def fy_label(date) = inr? ? "FY#{fiscal_year(date).to_s.last(2)}" : "FY#{fiscal_year(date)}"
    def fy_end(date) = inr? ? Date.new(fiscal_year(date), 3, 31) : Date.new(fiscal_year(date), 12, 31)

    # "Q1 FY27" (April-March) / "Q3 2026" (calendar)
    def quarter_label(date)
      return "Q#{(((date.month - 4) % 12) / 3) + 1} #{fy_label(date)}" if inr?

      "Q#{((date.month - 1) / 3) + 1} #{date.year}"
    end
  end

  # One company's generated history: quarters, valuations and the documents to write. Pure computation —
  # nothing here touches the database, so the dry run prints exactly what EXECUTE=1 would create.
  class Company
    attr_reader :name, :profile, :units, :quarters, :valuations, :investment_date, :today

    # profile_index: which PROFILES entry; round: 0 for the first pass, 1+ when N exceeds the profiles
    def initialize(profile_index:, round:, units:, today:, us_docs:)
      @profile = PROFILES[profile_index]
      @units = units
      @today = today
      base = @profile[:name][units.inr? ? :inr : :usd]
      @name = round.zero? ? base : "#{base.delete_suffix('.')} #{%w[II III IV V VI VII VIII IX X][round - 1] || (round + 1)}"
      # Aster Labs (first pass only) is the company the US stock purchase agreement is about
      @spa_company = us_docs && round.zero? && profile_index.zero?
      # Aster Labs' latest valuation is pinned to the SPA price, whatever the fund
      @calibrate_to_spa = round.zero? && profile_index.zero?
      @rng = Random.new(Zlib.crc32(@name))
      # The SPA purchase date for Aster Labs; otherwise a month after the first quarter in the history
      @investment_date = @spa_company ? SPA[:date] : quarter_ends.first + 1.month
      @quarters = build_quarters
      @valuations = build_valuations
    end

    def spa_company? = @spa_company
    def quarter_ends = PortcoDemo.quarter_ends(today)
    def sector = profile[:sector]

    # [standard name, reported name, category, data type] for the 10 KPIs, in display order
    def kpi_definitions
      money = ->(standard, reported = standard) { [standard, reported, "Income Statement", "money"] }
      [money.call("Revenue", profile[:cost] == "Interest Expense" ? "Interest Income" : "Revenue"), money.call("COGS", profile[:cost]),
       money.call("Contribution"), money.call("EBITDA"), money.call("PAT"),
       ["Total Equity", "Total Equity", "Balance Sheet", "money"], ["Total Assets", "Total Assets", "Balance Sheet", "money"],
       ["Total Liabilities", "Total Liabilities", "Balance Sheet", "money"],
       *profile[:ops].map { |label, *| [label, label, "Operational Metrics", "numeric"] }]
    end

    # Shares the fund buys and the cost, for a FUND_ID run: the SPA's economics for Aster Labs, otherwise
    # a 10% stake bought at a 15% discount to the first valuation
    def fund_purchase
      return { shares: SPA[:shares], per_share: SPA[:price] } if spa_company?

      { shares: (profile[:shares] * 0.1).round, per_share: (valuations.first[:per_share] * 0.85).round(2) }
    end

    # Documents on the portfolio company: [folder, name, date, kind, payload]. Period documents (board
    # notes, presentations, quarterly updates) live on the KPI reports instead — see #report_documents.
    def documents
      docs = []
      # IC note — just before the investment, citing the latest quarter reported by then
      ic_date = investment_date - 11.days
      docs << ["IC Notes", "IC Note - #{name}", ic_date, :ic_note, quarters.rfind { |q| q[:as_of] + 20.days <= ic_date } || quarters.first]
      # Annual summaries — every complete fiscal year in the history, 75 days after its year-end
      quarters.group_by { |q| units.fy_end(q[:as_of]) }.each do |fy_end, qs|
        next unless qs.size == 4 && fy_end + 75.days <= today

        docs << ["Financials", "Annual Financial Summary - #{units.fy_label(fy_end)}", fy_end + 75.days, :annual, qs]
      end
      docs
    end

    # Documents on one quarter's KPI report: [name, date, kind, payload]. The names carry the substrings the
    # presentation-analysis agent and KpiAnalystJob match on ("Quarterly Update", "Investor Presentation"),
    # and never the exact name "KPIs", which would start the KPI workbook import. A document whose natural
    # date (e.g. the board meeting 35 days after quarter-end) is still ahead is dated today.
    def report_documents(quarter)
      label = units.quarter_label(quarter[:as_of])
      dated = ->(date) { [date, today].min }
      # The latest valuation by the quarter-end, quoted in the deck
      slide = { quarter:, valuation: valuations.rfind { |v| v[:date] <= quarter[:as_of] } }
      [["Quarterly Update - #{label}", dated.call(quarter[:as_of] + 30.days), :quarterly_update, quarter],
       ["Board Meeting Notes - #{label}", dated.call(meeting_date(quarter[:as_of])), :board_minutes, quarter],
       ["Investor Presentation - #{label}", dated.call(quarter[:as_of] + 25.days), :presentation, slide]]
    end

    # One line for the business note: scale, trajectory and valuation story
    def summary
      first, last = quarters.values_at(0, -1)
      turn = first["EBITDA"].negative? && last["EBITDA"].positive? ? "turned EBITDA-positive" : "EBITDA #{units.money(first['EBITDA'])} -> #{units.money(last['EBITDA'])}"
      story = profile[:markdown] ? "marked down in #{valuations[profile[:markdown][0]][:date].year} and recovering" : "rising"
      "#{sector}. Quarterly revenue #{units.money(first['Revenue'])} -> #{units.money(last['Revenue'])}, #{turn}; " \
        "valuation #{story}, latest #{units.per_share(valuations.last[:per_share])} a share (#{valuations.last[:date]})."
    end

    # Board meets on the first weekday 35 days after the quarter-end
    def meeting_date(as_of)
      date = as_of + 35.days
      date += 1.day while date.saturday? || date.sunday?
      date
    end

    # Directors: two founders and an investor nominee, picked deterministically from the pool
    def board
      @board ||= BOARD_POOL.sample(3, random: Random.new(Zlib.crc32("#{name}-board")))
    end

    private

    # 12 quarters of internally consistent figures (absolute currency units)
    def build_quarters
      equity = profile[:equity] * units.scale
      quarter_ends.each_with_index.map do |as_of, i|
        progress = i / 11.0
        noise = 1 + @rng.rand(-0.03..0.03)
        # Revenue: compounding growth × seasonality × noise
        revenue = profile[:rev] * units.scale * ((1 + profile[:growth])**i) * profile[:seasonality].fetch(as_of.month, 1.0) * noise
        # Cost of sales and variable costs as a % of revenue that improves linearly over the 12 quarters
        cogs = revenue * lerp(profile[:cogs], progress)
        variable = revenue * lerp(profile[:var], progress)
        contribution = revenue - cogs - variable
        # Fixed opex grows more slowly than revenue, so EBITDA margin expands (some start loss-making)
        ebitda = contribution - (profile[:fixed] * units.scale * ((1 + profile[:fixed_growth])**i))
        # D&A and interest, then 25% tax on a profit (no tax credit on a loss)
        pbt = ebitda - (revenue * profile[:da])
        pat = pbt.positive? ? pbt * 0.75 : pbt
        # Equity rolls forward by PAT plus the one fundraise; assets = equity + liabilities
        equity += pat
        equity += profile[:raise][1] * units.scale if profile[:raise] && profile[:raise][0] == i
        liabilities = profile[:liabilities] * units.scale * ((1 + profile[:liab_growth])**i)
        ops = profile[:ops].to_h do |label, base, growth, kind|
          # A stock metric (stores, employees) compounds; a flow metric (orders, visits) tracks revenue
          value = kind == :stock ? base * ((1 + growth)**i) : base * (revenue / (profile[:rev] * units.scale)) * (1 + @rng.rand(-0.02..0.02))
          [label, value.round]
        end
        # Round each line, then derive assets from the rounded parts so the balance sheet ties exactly
        row = { "Revenue" => revenue, "COGS" => cogs, "Contribution" => contribution, "EBITDA" => ebitda, "PAT" => pat,
                "Total Equity" => equity, "Total Liabilities" => liabilities }.transform_values(&:round)
        row["Total Assets"] = row["Total Equity"] + row["Total Liabilities"]
        { as_of: }.merge(row, ops)
      end
    end

    # 6 half-yearly valuations: EV/TTM revenue (or P/B for a lender) × a small drift, ÷ shares outstanding
    def build_valuations
      raise_date = profile[:raise] && quarters[profile[:raise][0]][:as_of]
      raised = profile[:raise] ? profile[:raise][1] * units.scale : 0
      raw = PortcoDemo.half_year_ends(today, units).each_with_index.map do |date, idx|
        known = quarters.select { |q| q[:as_of] <= date }
        # TTM revenue; with fewer than 4 quarters, annualise what is known
        ttm = known.last(4).sum { |q| q["Revenue"] } * (4.0 / [known.last(4).size, 1].max)
        # Book value excludes the fundraise cash, which is added back at 1x below (post-money)
        book = known.last["Total Equity"] - (raise_date && date >= raise_date ? raised : 0)
        base = profile[:basis] == :book ? book : ttm
        multiple = profile[:multiple] * (1 + @rng.rand(-0.06..0.06))
        # A down-round from the markdown valuation onwards
        multiple *= profile[:markdown][1] if profile[:markdown] && idx >= profile[:markdown][0]
        [date, base * multiple]
      end
      # Aster Labs: scale so the latest price is the SPA's $2.50 a share (in INR at the rough rate)
      if @calibrate_to_spa
        target = SPA[:price] * profile[:shares] * (units.inr? ? INR_PER_USD : 1)
        factor = target / raw.last[1]
        raw = raw.map { |date, value| [date, value * factor] }
      end
      # A fundraise issues new shares at the pre-money price (post-money value less the cash, ÷ existing shares),
      # so the cash raised doesn't inflate the per-share value. The cash is added to the multiple-based
      # (pre-money) value to reach post-money.
      shares = profile[:shares]
      raw.map do |date, value|
        if raise_date && date >= raise_date
          value += raised
          shares += (raised / ((value - raised) / shares)).round if shares == profile[:shares]
        end
        { date:, equity_value: value.round, shares:, per_share: (value / shares).round(2) }
      end
    end

    def lerp((from, to), progress) = from + ((to - from) * progress)
  end

  # Renders a Company's documents as PDFs with HexaPDF's composer
  class Pdf
    def initialize(company)
      @c = company
      @u = company.units
    end

    # Writes the document to path and returns it
    def render(kind, payload, date, path)
      landscape = kind == :presentation
      HexaPDF::Composer.create(path, page_size: :A4, page_orientation: landscape ? :landscape : :portrait, margin: 48) do |pdf|
        @pdf = pdf
        pdf.style(:base, font: "Helvetica", font_size: 10, line_spacing: 1.35)
        pdf.style(:title, font: ["Helvetica", { variant: :bold }], font_size: landscape ? 26 : 18, margin: [0, 0, 6])
        pdf.style(:h2, font: ["Helvetica", { variant: :bold }], font_size: 12, margin: [12, 0, 4])
        pdf.style(:muted, font: "Helvetica", font_size: 9, fill_color: "666666", margin: [0, 0, 10])
        send(kind, payload, date)
      end
      path
    end

    private

    def text(str, style = :base) = @pdf.text(str, style:)
    def bullets(items) = @pdf.list(item_spacing: 2) { |list| items.each { |item| list.text(item, style: :base) } }

    # A table with a bold header row. widths are relative (HexaPDF negative column widths): absolute widths
    # summing to the frame width overflow it by the cell borders and the box never fits.
    def table(header, rows, widths)
      bold = ->(t) { @pdf.document.layout.text_box(t, style: { font: ["Helvetica", { variant: :bold }], font_size: 9 }) }
      plain = ->(t) { @pdf.document.layout.text_box(t.to_s, style: { font: "Helvetica", font_size: 9 }) }
      @pdf.table([header.map(&bold), *rows.map { |r| r.map(&plain) }], column_widths: widths.map(&:-@), margin: [4, 0, 8])
    end

    def fmt(key, value) = key.match?(/Revenue|COGS|Contribution|EBITDA|PAT|Equity|Assets|Liabilities/) ? @u.money(value) : value.to_fs(:delimited)
    def pct(part, whole) = whole.zero? ? "n/a" : "#{format('%.1f', part * 100.0 / whole)}%"

    # Percentage change; "n/m" (not meaningful) when the sign flips or the base is so small the % explodes
    def change(now, before)
      return "n/a" if before.to_f.zero?

      ratio = (now - before) / before.abs.to_f
      now.negative? != before.negative? || ratio.abs > 5 ? "n/m" : "#{format('%+.1f', ratio * 100)}%"
    end

    def label(key) = @c.kpi_definitions.find { |std, *| std == key }&.dig(1) || key

    # The 10 KPIs for a set of quarters, one column per quarter
    def kpi_table(quarters)
      keys = @c.kpi_definitions.map(&:first)
      # The label column twice as wide as each quarter's
      table(["KPI", *quarters.map { |q| @u.quarter_label(q[:as_of]) }],
            keys.map { |k| [label(k), *quarters.map { |q| fmt(k, q[k]) }] }, [2, *([1] * quarters.size)])
    end

    # The quarter `back` quarters before this one, nil when the history doesn't reach that far
    def prior(quarter, back)
      idx = @c.quarters.index(quarter)
      @c.quarters[idx - back] if idx >= back
    end

    def ic_note(quarter, date)
      purchase = @c.fund_purchase
      text("Investment Committee Note", :title)
      text("#{@c.name} | #{@c.sector} | #{date.strftime('%d %b %Y')}", :muted)
      text("1. Recommendation", :h2)
      deal = @c.spa_company? ? "a secondary purchase from an existing shareholder of" : "an investment in #{@c.name} of"
      text("We recommend #{deal} #{purchase[:shares].to_fs(:delimited)} equity shares#{" of #{@c.name}" if @c.spa_company?} at " \
           "#{@u.per_share(purchase[:per_share])} a share (#{@u.amount(purchase[:shares] * purchase[:per_share])}).")
      text("2. Company and latest performance (#{@u.quarter_label(quarter[:as_of])})", :h2)
      ops = @c.profile[:ops].map { |l, *| "#{l}: #{quarter[l].to_fs(:delimited)}" }.join("; ")
      text("Revenue of #{@u.money(quarter['Revenue'])} with a contribution margin of #{pct(quarter['Contribution'], quarter['Revenue'])} " \
           "and EBITDA of #{@u.money(quarter['EBITDA'])}. Net worth stands at #{@u.money(quarter['Total Equity'])}. #{ops}.")
      text("3. Investment thesis", :h2)
      bullets(@c.profile[:thesis])
      text("4. Key risks and mitigants", :h2)
      table(%w[Risk Mitigant], @c.profile[:risks], [1, 1])
      text("5. Valuation", :h2)
      text("Entry price implies #{@c.profile[:basis] == :book ? 'a price-to-book' : 'an EV/TTM revenue'} multiple broadly in line with listed " \
           "and private comparables in #{@c.sector}. Exit routes: strategic sale or IPO in 4-6 years.")
      text("6. Conditions", :h2)
      bullets(["Board seat for the fund's nominee", "Information rights: quarterly MIS within 45 days, audited accounts within 120 days",
               "Customary protective provisions and anti-dilution"])
    end

    def board_minutes(quarter, date)
      before = prior(quarter, 1)
      year_ago = prior(quarter, 4)
      chair, founder, nominee = @c.board
      text("Minutes of the Board Meeting", :title)
      text("#{@c.name} | held on #{date.strftime('%d %b %Y')} by video conference", :muted)
      text("Present: #{chair} (Chair), #{founder} (Founder & CEO), #{nominee} (Investor Nominee Director). " \
           "In attendance: CFO and Company Secretary.")
      text("1. Quorum", :h2)
      text("The Chair confirmed that a quorum was present and the meeting was duly convened.")
      text("2. Results for #{@u.quarter_label(quarter[:as_of])}", :h2)
      # Growth clauses only for the comparisons the history has
      growth = [before && "#{change(quarter['Revenue'], before['Revenue'])} quarter on quarter",
                year_ago && "#{change(quarter['Revenue'], year_ago['Revenue'])} year on year"].compact
      text("The CFO presented the quarter's results. Revenue was #{@u.money(quarter['Revenue'])}" +
           (growth.any? ? " (#{growth.join(', ')})" : "") +
           ". EBITDA was #{@u.money(quarter['EBITDA'])} and PAT #{@u.money(quarter['PAT'])}.")
      rows = %w[Revenue COGS Contribution EBITDA PAT].map do |k|
        [label(k), fmt(k, quarter[k]), before ? fmt(k, before[k]) : "-", before ? change(quarter[k], before[k]) : "-"]
      end
      table(["KPI", "This quarter", "Prior quarter", "Change"], rows, [34, 22, 22, 22])
      text("3. Operations", :h2)
      ops = @c.profile[:ops].map { |l, *| "#{l}: #{quarter[l].to_fs(:delimited)}#{" (prior #{before[l].to_fs(:delimited)})" if before}" }
      text("#{ops.join('; ')}.")
      text("4. Balance sheet", :h2)
      text("Total assets of #{@u.money(quarter['Total Assets'])}, funded by equity of #{@u.money(quarter['Total Equity'])} and " \
           "liabilities of #{@u.money(quarter['Total Liabilities'])}.")
      text("5. Resolutions", :h2)
      bullets(["RESOLVED that the unaudited financial results for #{@u.quarter_label(quarter[:as_of])} be and are hereby approved.",
               "RESOLVED that the updated operating budget and hiring plan presented by management be approved.",
               "RESOLVED that the CEO be authorised to execute documents necessary to give effect to the above."])
      text("6. Matters raised by the Investor Nominee", :h2)
      text("#{nominee} asked management to report progress against: #{@c.profile[:risks].map(&:first).join('; ').downcase}. " \
           "Management to present an update at the next meeting.")
      text("There being no other business, the meeting concluded with a vote of thanks to the Chair.")
    end

    # A quarter's deck: highlights, the last four quarters' KPIs and the outlook
    def presentation(slide, date)
      latest = slide[:quarter]
      valuation = slide[:valuation]
      quarters = @c.quarters.select { |q| q[:as_of] <= latest[:as_of] }.last(4)
      text(@c.name, :title)
      text("Investor Presentation | #{@u.quarter_label(latest[:as_of])} | #{date.strftime('%B %Y')}", :muted)
      text("Highlights", :h2)
      # The valuation line only once the company has a valuation by this quarter
      bullets(["TTM revenue of #{@u.money(quarters.sum { |q| q['Revenue'] })}",
               "Latest quarter EBITDA margin of #{pct(latest['EBITDA'], latest['Revenue'])}",
               *@c.profile[:ops].map { |l, *| "#{l} at #{latest[l].to_fs(:delimited)}" },
               *(valuation && ["Valuation of #{@u.per_share(valuation[:per_share])} a share (equity value #{@u.money(valuation[:equity_value])})"])])
      text("Strategy", :h2)
      bullets(@c.profile[:thesis])
      @pdf.new_page
      text("Financial and operating performance - last four quarters", :title)
      kpi_table(quarters)
      @pdf.new_page
      text("Outlook and priorities", :title)
      bullets(@c.profile[:risks].map { |risk, plan| "#{risk}: #{plan}" } +
              ["Continue margin expansion while compounding #{@c.profile[:ops].first.first.downcase}"])
      text("This presentation is confidential and intended solely for the company's shareholders.", :muted)
    end

    # A one-page letter to investors on the quarter: KPIs against the prior quarter and a year ago, then priorities
    def quarterly_update(quarter, date)
      before = prior(quarter, 1)
      year_ago = prior(quarter, 4)
      ceo = @c.board[1]
      text("Quarterly Update - #{@u.quarter_label(quarter[:as_of])}", :title)
      text("#{@c.name} | to our shareholders | #{date.strftime('%d %b %Y')}", :muted)
      text("Dear shareholders,")
      text("Revenue for the quarter was #{@u.money(quarter['Revenue'])} with a contribution margin of " \
           "#{pct(quarter['Contribution'], quarter['Revenue'])} and EBITDA of #{@u.money(quarter['EBITDA'])}. " \
           "We closed the quarter with net worth of #{@u.money(quarter['Total Equity'])}.")
      text("Key numbers", :h2)
      # This quarter against the prior quarter and the same quarter last year, where the history has them
      rows = @c.kpi_definitions.map(&:first).map do |k|
        [label(k), fmt(k, quarter[k]), before ? change(quarter[k], before[k]) : "-", year_ago ? change(quarter[k], year_ago[k]) : "-"]
      end
      table(["KPI", "This quarter", "vs prior quarter", "vs last year"], rows, [34, 22, 22, 22])
      text("What we are focused on next quarter", :h2)
      bullets(["Grow #{@c.profile[:ops].first.first.downcase} while holding contribution margin above " \
               "#{format('%.0f', quarter['Contribution'] * 100.0 / quarter['Revenue'])}%",
               *@c.profile[:risks].map { |risk, plan| "#{plan}, to address #{risk.downcase}" }])
      text("Thank you for your continued support.")
      text("#{ceo}, Founder & CEO", :muted)
    end

    def annual(quarters, date)
      fy = @u.fy_label(quarters.last[:as_of])
      totals = %w[Revenue COGS Contribution EBITDA PAT].index_with { |k| quarters.sum { |q| q[k] } }
      closing = quarters.last
      text("Annual Financial Summary - #{fy}", :title)
      text("#{@c.name} | year ended #{quarters.last[:as_of].strftime('%d %b %Y')} | issued #{date.strftime('%d %b %Y')}", :muted)
      text("Income statement", :h2)
      table(["Line item", fy, "% of revenue"], totals.map { |k, v| [label(k), @u.money(v), pct(v, totals['Revenue'])] },
            [2, 1, 1])
      text("Balance sheet at year end", :h2)
      table(["Line item", fy], ["Total Assets", "Total Liabilities", "Total Equity"].map { |k| [k, @u.money(closing[k])] }, [1, 1])
      text("Quarterly detail", :h2)
      kpi_table(quarters)
      text("Figures are management accounts reconciled to the statutory audit; the auditors issued an unqualified opinion.", :muted)
    end
  end

  # Writes companies (and, for a USD fund, the US sample-document records) into an entity. Idempotent:
  # every record is found before it is created.
  class Seeder
    def initialize(entity:, user:, fund:, execute:, out: $stdout)
      @entity = entity
      @user = user
      @fund = fund
      @execute = execute
      @out = out
      # Records for the closing business note, collected whether created now or found from an earlier run
      @note = { companies: [], commitments: [] }
    end

    def say(msg) = @out.puts(msg)

    def seed_company(company)
      say("\n#{company.name} (#{company.sector})")
      say("  KPIs: #{company.kpi_definitions.map { |std, reported, *| std == reported ? std : "#{reported} (#{std})" }.join(', ')}")
      first, last = company.quarters.values_at(0, -1)
      say("  Quarters: #{first[:as_of]} .. #{last[:as_of]} | revenue #{company.units.money(first['Revenue'])} -> " \
          "#{company.units.money(last['Revenue'])} | EBITDA #{company.units.money(first['EBITDA'])} -> #{company.units.money(last['EBITDA'])}")
      say("  Valuations: #{company.valuations.map { |v| "#{v[:date]} #{company.units.per_share(v[:per_share])}" }.join(', ')}")
      if @fund
        purchase = company.fund_purchase
        say("  Fund buy: #{purchase[:shares].to_fs(:delimited)} shares at #{company.units.per_share(purchase[:per_share])} on #{company.investment_date}" +
            (company.spa_company? ? " + Stock Purchase Agreement" : ""))
      end
      company.documents.each { |folder, name, date, *| say("  Document: #{folder}/#{name} (#{date})") }
      say("  KPI report documents: #{company.report_documents(last).map { |name, *| name.sub(/ - .*/, '') }.join(', ')} " \
          "on each of the #{company.quarters.size} quarterly reports")
      return unless @execute

      ActiveRecord::Base.transaction do
        pc, instrument = company_and_instrument(company)
        mappings = kpi_mappings(pc, company)
        reports = company.quarters.map do |q|
          report = kpi_report(pc, company, q, mappings)
          company.report_documents(q).each { |name, date, kind, payload| report_document(report, company, name, date, kind, payload) }
          report
        end
        company.valuations.each { |v| valuation(pc, instrument, v) }
        company.documents.each { |folder, name, date, kind, payload| document(pc, company, folder, name, date, kind, payload) }
        investment = @fund&.portfolio_investments&.where(portfolio_company_id: pc.id)&.order(:id)&.last
        @note[:companies] << { company:, pc:, latest_report: reports.last, investment: }
      end
    end

    # Points the CP/CS extraction agent at the SPA's tag, so it finds the Aster Labs agreement. Only a blank
    # setting is filled in; a tag the entity already configured is left alone.
    def configure_cp_cs_agent
      SupportAgent.where(entity_id: @entity.id, agent_type: "CpCsExtractionAgent").find_each do |agent|
        fields = agent.json_fields || {}
        next if fields["investment_doc_tag"].present?

        say("\nCP/CS extraction agent #{agent.id}: investment_doc_tag blank -> \"SPA\"")
        agent.update!(json_fields: fields.merge("investment_doc_tag" => "SPA")) if @execute
      end
    end

    # Plain-text note for the business: what was seeded, with a link to each record
    def print_note(units)
      urls = Rails.application.routes.url_helpers
      base = ENV.fetch("BASE_URL", "http://localhost:3000").chomp("/")
      link = ->(path) { "#{base}#{path}" }
      first_q, last_q = @note[:companies].first&.dig(:company)&.quarters&.values_at(0, -1)
      lines = ["", "=" * 100, "Demo portfolio data - #{@entity.name} (#{Time.zone.today.strftime('%d %b %Y')})", "=" * 100, ""]
      if @fund
        lines += ["Fund: #{@fund.name}", "  #{link.call(urls.fund_path(@fund))}",
                  "  Holds the #{@note[:companies].size} portfolio companies below and has #{@note[:commitments].size} LP commitments, each with a verified KYC.", ""]
      end
      if first_q
        lines += ["Portfolio companies - each has #{"quarterly KPI reports from #{units.quarter_label(first_q[:as_of])} to #{units.quarter_label(last_q[:as_of])} " unless first_q[:as_of] == last_q[:as_of]}" \
                  "(5 income statement, 3 balance sheet and 2 operating KPIs), 6 half-yearly valuations per share, an IC note and annual " \
                  "financial summaries. Every quarterly KPI report carries a Quarterly Update, Board Meeting Notes and an Investor Presentation.", ""]
      end
      @note[:companies].each_with_index do |entry, i|
        company = entry[:company]
        lines << "#{i + 1}. #{company.name}"
        lines << "   #{company.summary}"
        lines << "   Company:           #{link.call(urls.investor_path(entry[:pc]))}"
        lines << "   Latest KPI report: #{link.call(urls.kpi_report_path(entry[:latest_report]))}"
        if entry[:investment]
          purchase = company.fund_purchase
          what = company.spa_company? ? "Fund's purchase, Stock Purchase Agreement attached" : "Fund's purchase"
          lines << "   #{what} (#{purchase[:shares].to_fs(:delimited)} shares at #{units.per_share(purchase[:per_share])}): " \
                   "#{link.call(urls.portfolio_investment_path(entry[:investment]))}"
        end
        lines << ""
      end
      if @note[:commitments].any?
        lines << "LP commitments (#{@fund.name})"
        @note[:commitments].each do |entry|
          extra = entry[:side_letter] ? " - side letter attached" : ""
          lines << "  - #{entry[:name]}: #{units.amount(entry[:amount])}, verified KYC#{extra}"
          lines << "    #{link.call(urls.capital_commitment_path(entry[:commitment]))}"
        end
        lines << ""
      end
      if @note[:commitments].any? { |c| c[:side_letter] }
        lines << "Documents for the AI agents: the side letter is tagged \"Side Letter\" (Side Letter Obligation agent), the stock purchase " \
                 "agreement \"SPA\" (CP/CS Extraction agent), and each KPI report's Investor Presentation and Quarterly Update are named for the " \
                 "presentation analysis agent."
      end
      lines << "All figures are generated demo data."
      lines << ("=" * 100)
      say(lines.join("\n"))
    end

    # The fund's 4 demo LPs, each with a verified KYC linked to its commitment. Harborview (USD funds only)
    # keeps the side letter's date and carries the side letter.
    def seed_commitments(units:, start_date:)
      say("\nCommitments in #{@fund.name}:")
      LPS[units.inr? ? :inr : :usd].each do |name, folio_id, millions, city|
        side_letter = name == SIDE_LETTER[:investor]
        amount = (millions * units.scale).round
        date = side_letter ? SIDE_LETTER[:date] : start_date
        say("  #{folio_id}: #{name} (#{city}) #{units.amount(amount)} on #{date} + verified KYC" +
            (side_letter ? " + #{File.basename(SIDE_LETTER[:file])}" : ""))
        next unless @execute

        ActiveRecord::Base.transaction do
          investor = lp_investor(name, city)
          kyc = investor.investor_kycs.order(:id).first || lp_kyc(investor, city, units)
          commitment = @fund.capital_commitments.find_by(folio_id:) || create_commitment(investor, kyc, folio_id, amount, date)
          link_kyc(commitment, kyc)
          attach(commitment, "Side Letter - #{name}", SIDE_LETTER[:file], tags: "Side Letter") if side_letter
          @note[:commitments] << { name:, amount:, commitment:, side_letter: }
        end
      end
    end

    private

    # The portfolio company and its equity instrument. With a fund, the buy goes through
    # PortfolioInvestmentCreate (EvergreenDemoPortfolio.buy), which also creates both.
    def company_and_instrument(company)
      instrument_name = "#{company.name} Equity"
      pc = EvergreenDemoPortfolio.portfolio_company(@entity, company.name)
      if @fund && !@fund.portfolio_investments.exists?(portfolio_company_id: pc.id)
        purchase = company.fund_purchase
        EvergreenDemoPortfolio.buy(@fund, name: company.name, shares: purchase[:shares], bought_on: company.investment_date,
                                          cost_cents: (purchase[:shares] * purchase[:per_share] * 100).round,
                                          sector: company.sector, instrument_name:, notes: "Demo holding (portco_demo:seed)")
        say("  [created] buy of #{purchase[:shares]} shares")
      end
      # The Aster Labs buy carries the stock purchase agreement (tagged for the CP/CS extraction agent).
      # Outside the buy branch so a re-run still attaches it if an earlier run stopped after the buy.
      if @fund && company.spa_company?
        investment = @fund.portfolio_investments.where(portfolio_company_id: pc.id).order(:id).last
        attach(investment, "Stock Purchase Agreement - #{company.name}", SPA[:file], tags: "SPA")
      end
      instrument = InvestmentInstrument.find_or_create_by!(entity: @entity, portfolio_company: pc, name: instrument_name) do |i|
        i.category = "Unlisted"
        i.sub_category = "Equity"
        i.sector = company.sector
        i.currency = company.units.currency
      end
      [pc, instrument]
    end

    # One mapping per KPI: Kpi.name is the standard name, the mapping keeps the sector's reported label
    def kpi_mappings(pc, company)
      company.kpi_definitions.to_h do |standard, reported, category, data_type|
        mapping = InvestorKpiMapping.find_or_initialize_by(entity_id: @entity.id, investor_id: pc.id, reported_kpi_name: reported)
        if mapping.new_record?
          mapping.update!(standard_kpi_name: standard, category:, data_type:, show_in_report: true,
                          denomination: data_type == "money" ? company.units.denomination : nil)
        end
        [standard, mapping]
      end
    end

    # A reviewed "Actual" quarterly report with its 10 KPIs (absolute values; the mapping's denomination is
    # the unit the KPI is shown and uploaded in)
    def kpi_report(pc, company, quarter, mappings)
      report = KpiReport.find_or_create_by!(entity_id: @entity.id, portfolio_company: pc, period: "Quarter", as_of: quarter[:as_of],
                                            tag_list: "Actual") do |r|
        r.user = @user
        r.status = "reviewed"
      end
      company.kpi_definitions.map(&:first).each do |standard|
        next if Kpi.exists?(kpi_report: report, name: standard)

        Kpi.create!(kpi_report: report, entity_id: @entity.id, portfolio_company: pc, investor_kpi_mapping: mappings[standard],
                    name: standard, value: quarter[standard])
      end
      report
    end

    # A manual valuation of the company's equity on the date; an existing one for the date is kept
    def valuation(pc, instrument, val)
      Valuation.find_or_create_by!(entity: @entity, owner: pc, investment_instrument: instrument, valuation_date: val[:date], source: "manual") do |v|
        v.category = "Unlisted"
        v.sub_category = "Equity"
        v.per_share_value_cents = (val[:per_share] * 100).round
        v.valuation_cents = val[:equity_value] * 100
      end
    end

    # Renders the PDF into a sub-folder of the company's document folder
    def document(pc, company, folder_name, name, date, kind, payload)
      return if pc.documents.exists?(name:)

      folder = pc.document_folder.children.find_or_create_by!(name: folder_name, entity_id: @entity.id) { |f| f.owner = pc }
      Dir.mktmpdir do |dir|
        path = File.join(dir, "#{name.parameterize}.pdf")
        Pdf.new(company).render(kind, payload, date, path)
        Document.create!(entity: @entity, owner: pc, folder:, user: @user, name:, file: File.open(path), tag_list: folder_name)
      end
    end

    # Renders a period PDF onto a KPI report; the report files it in its own folder (WithFolder)
    def report_document(report, company, name, date, kind, payload)
      return if report.documents.exists?(name:)

      Dir.mktmpdir do |dir|
        path = File.join(dir, "#{name.parameterize}.pdf")
        Pdf.new(company).render(kind, payload, date, path)
        Document.create!(entity: @entity, owner: report, user: @user, name:, file: File.open(path), tag_list: name.sub(/ - .*/, ""))
      end
    end

    def attach(owner, name, file, tags:)
      return if owner.documents.exists?(name:)

      Document.create!(entity: @entity, owner:, user: @user, name:, file: Rails.root.join(file).open, tag_list: tags)
      say("  [created] #{name}")
    end

    # The LP, with its own investor entity on a stable demo email (the shape the portfolio-company helper uses)
    def lp_investor(name, city)
      investor = @entity.investors.find_by(investor_name: name)
      return investor if investor

      email = "demo+#{Digest::MD5.hexdigest(name).first(10)}@example.com"
      investor_entity = Entity.find_by(primary_email: email) || Entity.create!(name:, entity_type: "Investor", primary_email: email)
      @entity.investors.create!(investor_name: name, investor_entity:, category: "LP", primary_email: email, city:)
    end

    # A verified non-individual KYC (lib/tasks/support/ops_demo_entity.rb#approved_kyc pattern). The model
    # requires PAN and IFSC columns; a USD fund's LP carries its EIN and bank routing number in them.
    def lp_kyc(investor, city, units)
      digest = Digest::MD5.hexdigest(investor.investor_name)
      tax_id, routing = if units.inr?
                          # Demo PAN (AAAAA9999A) and IFSC
                          ["#{digest.tr('0-9', 'A-J').upcase.first(5)}#{digest.to_i(16).to_s.first(4)}#{digest.tr('0-9', 'K-T').upcase[5]}", "DEMO0000001"]
                        else
                          # Demo EIN (12-3456789) and ABA routing number
                          [digest.to_i(16).to_s.first(9).insert(2, "-"), "021000021"]
                        end
      kyc = InvestorKyc.new(entity: @entity, investor:, full_name: investor.investor_name, kyc_type: "non_individual", residency: "domestic",
                            PAN: tax_id, address: "1 Demo Plaza, #{city}", corr_address: "1 Demo Plaza, #{city}",
                            bank_name: "Demo Bank", bank_branch: city, bank_account_type: "Current",
                            bank_account_number: digest.to_i(16).to_s.last(12), ifsc_code: routing,
                            # Incorporation date: the model requires birth_date for every KYC type
                            birth_date: Date.new(2005, 1, 1), verified: true, submission_status: "verified")
      kyc.skip_cf_before_save = true if kyc.respond_to?(:skip_cf_before_save=)
      kyc.save!
      say("  [created] KYC for #{investor.investor_name}")
      kyc
    end

    def create_commitment(investor, kyc, folio_id, amount, date)
      cc = CapitalCommitment.new(entity: @entity, fund: @fund, investor:, investor_kyc: kyc, folio_id:, fund_close: "First Close",
                                 unit_type: @fund.unit_types.to_s.split(",").first&.strip, folio_currency: @fund.currency,
                                 commitment_date: date, orig_folio_committed_amount_cents: amount * 100,
                                 notes: "Demo commitment (portco_demo:seed)")
      result = CapitalCommitmentCreate.call(capital_commitment: cc)
      raise "Commitment #{folio_id}: #{cc.errors.full_messages.to_sentence.presence || result[:errors]}" unless result.success?

      say("  [created] commitment #{folio_id}")
      cc
    end

    # Links the KYC to a commitment that has none (e.g. Harborview's, created before KYCs were seeded),
    # through the app's update service
    def link_kyc(commitment, kyc)
      return if commitment.investor_kyc_id.present?

      commitment.investor_kyc = kyc
      result = CapitalCommitmentUpdate.call(capital_commitment: commitment)
      raise "Commitment #{commitment.folio_id}: #{commitment.errors.full_messages.to_sentence.presence || result[:errors]}" unless result.success?

      say("  [linked] KYC to commitment #{commitment.folio_id}")
    end
  end
end

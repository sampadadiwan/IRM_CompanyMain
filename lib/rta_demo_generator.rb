# frozen_string_literal: true

# Generates a fully-configured, fully-reconciled RTA demo for a given fund, plus a second
# statement that deliberately exercises every discrepancy type RtaReconciliationAgent can
# catch, then runs the agent against both so the Reconciliation History tab has real,
# representative data to show.
#
# Usage: rake "rta:demo[<fund_id>]"
#
# What it does, in order:
#   1. Ensures every unit type with live (non-zero) commitments has a FundUnitSetting + ISIN —
#      generating one if missing, so the fund is fully reconcilable.
#   2. Builds an RTA statement PDF from the fund's live data that matches exactly (PDF #1).
#   3. Builds a second PDF, same fund, with one of every discrepancy type the agent checks for,
#      isolated to different schemes/folios so each shows up distinctly (PDF #2).
#   4. Runs RtaReconciliationAgent against the fund with each PDF and prints a summary.
#
# Saved PDFs land in public/sample_uploads/rta_demo_fund_<id>_{success,issues}.pdf.
class RtaDemoGenerator
  ISIN_PREFIX = "INF900"

  def initialize(fund_id)
    @fund = Fund.find(fund_id)
    @entity = @fund.entity
  end

  def call
    puts "== RTA demo for Fund ##{@fund.id} (#{@fund.name}) =="

    ensure_isins!
    schemes = live_schemes

    if schemes.empty?
      puts "No unit types with live (non-zero) commitments found for this fund — nothing to generate."
      return
    end

    puts "Schemes with live data: #{schemes.map { |s| "#{s[:isin]} (#{s[:unit_type]}, #{s[:folios].size} folio(s))" }.join(', ')}"

    success_path = build_and_save(:success, schemes)
    issues_path  = build_and_save(:issues, schemes)

    sa = SupportAgent.find_by(entity_id: @entity.id, agent_type: "RtaReconciliationAgent")
    raise "No RtaReconciliationAgent configured for entity #{@entity.id} — run SupportAgentsSetupService first." unless sa

    Chewy.strategy(:bypass) do
      run_agent(sa, success_path, "All-success statement")
      run_agent(sa, issues_path, "All-issue-types statement")
    end
  end

  private

  # ── Step 1: configuration ────────────────────────────────────────────────────

  def ensure_isins!
    unit_types = @fund.capital_commitments
                       .where.not(unit_type: [nil, ""])
                       .where.not(total_fund_units_quantity: 0)
                       .distinct
                       .pluck(:unit_type)

    unit_types.each do |unit_type|
      fus = FundUnitSetting.find_or_initialize_by(fund: @fund, name: unit_type)
      fus.entity = @entity
      next if fus.isin.present?

      fus.isin = generate_isin
      fus.save!
      puts "Generated ISIN #{fus.isin} for unit type #{unit_type.inspect}"
    end
  end

  def generate_isin
    loop do
      candidate = "#{ISIN_PREFIX}#{SecureRandom.alphanumeric(5).upcase}"
      return candidate unless FundUnitSetting.exists?(isin: candidate)
    end
  end

  # ── Live data ─────────────────────────────────────────────────────────────────

  Scheme = Struct.new(:isin, :unit_type, :folios, keyword_init: true)
  Folio  = Struct.new(:folio_id, :investor_name, :units, keyword_init: true)

  def live_schemes
    @fund.fund_unit_settings.where.not(isin: [nil, ""]).order(:name).filter_map do |fus|
      commitments = @fund.capital_commitments
                          .where(unit_type: fus.name)
                          .where.not(total_fund_units_quantity: 0)
                          .includes(:investor)
      next if commitments.none?

      folios = commitments.map do |cc|
        Folio.new(folio_id: cc.folio_id, investor_name: cc.investor&.investor_name || "Investor #{cc.id}", units: cc.total_fund_units_quantity.to_f)
      end
      Scheme.new(isin: fus.isin, unit_type: fus.name, folios: folios)
    end
  end

  # ── PDF construction ────────────────────────────────────────────────────────

  def build_and_save(kind, schemes)
    html = kind == :success ? build_success_html(schemes) : build_issues_html(schemes)
    path = Rails.root.join("public", "sample_uploads", "rta_demo_fund_#{@fund.id}_#{kind}.pdf")
    render_pdf(html, path)
    puts "Wrote #{path} (#{File.size(path)} bytes)"
    path
  end

  def build_success_html(schemes)
    rows = schemes.map do |scheme|
      scheme_html(scheme.isin, "#{@fund.name} - #{scheme.unit_type}", scheme.folios.map { |f| [f.folio_id, f.investor_name, f.units, f.units, "None"] })
    end.join
    wrap_html(rows, statement_date: Date.current)
  end

  # Spreads one of every discrepancy type across the available schemes/folios:
  #   scheme 0        — left fully clean (a "Matched" baseline next to the breaks)
  #   scheme 1        — summary + folio break
  #   scheme 2        — investor name mismatch on one folio
  #   scheme with >1 folio — one folio omitted entirely (missing-from-RTA), one extra
  #                          unmatched folio added, one folio flagged pending
  #   last scheme (if >= 2 schemes) — omitted entirely from the statement (coverage gap)
  #   always          — one extra scheme with a never-configured ISIN (orphan/unrecognized)
  def build_issues_html(schemes)
    notes = []
    usable = schemes.dup
    omitted_scheme = usable.pop if usable.size >= 2
    notes << "#{omitted_scheme.isin} (#{omitted_scheme.unit_type}): omitted entirely — statement coverage gap" if omitted_scheme

    # The missing/unmatched/pending trio needs >= 2 folios to omit one and still have
    # something left, so it gets its own scheme — kept separate from the break/mismatch/
    # clean assignments below so one scheme is never given two contradictory treatments.
    multi_folio_scheme = usable.find { |s| s.folios.size > 1 }
    remaining = usable.reject { |s| s == multi_folio_scheme }

    assignments = {}
    assignments[remaining[0]] = :clean if remaining[0]
    assignments[remaining[1]] = :break if remaining[1]
    assignments[remaining[2]] = :name_mismatch if remaining[2]
    remaining[3..]&.each { |s| assignments[s] = :clean }

    rows = usable.map do |scheme|
      folio_rows = scheme.folios.map { |f| [f.folio_id, f.investor_name, f.units, f.units, "None"] }

      case assignments[scheme]
      when :break
        folio_rows[0][3] += folio_rows[0][2] * 0.1 + 10 # break the first folio's closing units
        notes << "#{scheme.isin}: folio #{scheme.folios[0].folio_id} broken (+#{(folio_rows[0][3] - folio_rows[0][2]).round(2)} units)"
      when :name_mismatch
        folio_rows[0][1] = "Totally Different Holdings LLP"
        notes << "#{scheme.isin}: folio #{scheme.folios[0].folio_id} investor name mismatch"
      when :clean
        notes << "#{scheme.isin}: left clean (baseline match)"
      end

      if scheme == multi_folio_scheme
        if folio_rows.size > 1
          omitted = folio_rows.delete_at(1)
          notes << "#{scheme.isin}: folio #{omitted[0]} omitted from statement — missing-from-RTA"
        end
        folio_rows << ["GHOST-001", "Ghost Capital LLP", nil, 25.0, "None"]
        notes << "#{scheme.isin}: folio GHOST-001 added — not in CapHive (unmatched)"
        folio_rows[0][4] = "Redemption in process"
        notes << "#{scheme.isin}: folio #{folio_rows[0][0]} flagged with a pending request"
      end

      scheme_html(scheme.isin, "#{@fund.name} - #{scheme.unit_type}", folio_rows)
    end.join

    orphan_isin = "INFORPHAN#{SecureRandom.alphanumeric(4).upcase}"
    rows << scheme_html(orphan_isin, "#{@fund.name} - Legacy Class", [["Z001", "Legacy Holder", nil, 200.0, "None"]])
    notes << "#{orphan_isin}: never configured in FundUnitSetting — unrecognized/orphan ISIN"

    puts "Issue statement contents:"
    notes.each { |n| puts "  - #{n}" }

    wrap_html(rows, statement_date: Date.current)
  end

  # folio_rows: array of [folio_id, investor_name, opening_units(nillable), closing_units, pending_requests]
  def scheme_html(isin, scheme_name, folio_rows)
    total = folio_rows.sum { |r| r[3].to_f }
    body = folio_rows.map do |folio_id, investor_name, opening, closing, pending|
      opening_val = opening.nil? ? closing : opening
      "<tr><td class=\"l\">#{folio_id}</td><td class=\"l\">#{investor_name}</td>" \
        "<td>#{format('%.4f', opening_val)}</td><td>0.0000</td><td>0.0000</td>" \
        "<td>#{format('%.4f', closing)}</td><td class=\"l\">#{pending}</td></tr>\n"
    end.join
    <<~HTML
      <h2>Scheme: #{scheme_name}   ISIN: #{isin}   NAV: 100.00</h2>
      <table>
        <tr><th class="l">Folio No</th><th class="l">Investor Name</th><th>Opening Units</th><th>Subscription Units</th><th>Redemption Units</th><th>Closing Units</th><th class="l">Pending Requests</th></tr>
        #{body}
        <tr class="summary"><td class="l" colspan="2">Scheme Total</td><td>#{format('%.4f', total)}</td><td>0.0000</td><td>0.0000</td><td>#{format('%.4f', total)}</td><td></td></tr>
      </table>
    HTML
  end

  def wrap_html(rows, statement_date:)
    <<~HTML
      <html>
      <head>
      <style>
        body { font-family: Arial, sans-serif; font-size: 10px; color: #222; }
        h1 { font-size: 16px; margin-bottom: 2px; }
        h2 { font-size: 12px; margin-top: 18px; margin-bottom: 4px; background: #eee; padding: 4px; }
        .meta { margin-bottom: 12px; }
        table { width: 100%; border-collapse: collapse; margin-bottom: 10px; }
        th, td { border: 1px solid #999; padding: 3px 5px; text-align: right; }
        th { background: #ddd; }
        td.l, th.l { text-align: left; }
        .summary td { font-weight: bold; }
      </style>
      </head>
      <body>
        <h1>Demo AMC Investment Managers Pvt Ltd</h1>
        <div class="meta">Unit Statement (RTA) | Statement Date: #{statement_date.strftime('%d-%m-%Y')} | Fund: #{@fund.name}</div>
        #{rows}
      </body>
      </html>
    HTML
  end

  # Prefers WickedPdf (wkhtmltopdf-binary) since it's already a bundled gem dependency —
  # config/initializers/wicked_pdf.rb — so it works in any deployed environment without
  # needing a browser installed. Falls back to a local Chrome/Chromium binary, useful in a
  # dev sandbox where wkhtmltopdf-binary's bundled binary doesn't support the host's OS version.
  def render_pdf(html, path)
    pdf = begin
      require "wicked_pdf"
      WickedPdf.new.pdf_from_string(html)
    rescue StandardError => e
      Rails.logger.warn("[RtaDemoGenerator] WickedPdf failed (#{e.message}), falling back to a local browser") if defined?(Rails.logger)
      render_pdf_via_browser(html)
    end
    File.binwrite(path, pdf)
  end

  CHROME_CANDIDATES = %w[google-chrome google-chrome-stable chromium chromium-browser].freeze

  def render_pdf_via_browser(html)
    chrome = CHROME_CANDIDATES.map { |name| `which #{name} 2>/dev/null`.strip }.find(&:present?)
    raise "Could not render PDF: WickedPdf/wkhtmltopdf failed and none of #{CHROME_CANDIDATES.join(', ')} were found on PATH." if chrome.blank?

    require "tempfile"
    out = Tempfile.new(["rta_demo", ".pdf"])
    Tempfile.create(["rta_demo", ".html"]) do |f|
      f.write(html)
      f.flush
      system(chrome, "--headless", "--disable-gpu", "--no-sandbox",
             "--print-to-pdf=#{out.path}", "--no-pdf-header-footer", f.path,
             out: File::NULL, err: File::NULL, exception: true)
    end
    out.binmode
    out.read
  ensure
    out&.close!
  end

  # ── Run the agent ────────────────────────────────────────────────────────────

  def run_agent(support_agent, pdf_path, label)
    folder = @fund.document_folder
    doc = Document.new(name: "RTA Statement (PDF) - #{label}", entity: @entity, owner: @fund, folder: folder,
                        user: @entity.employees.first, send_email: false, orignal: true)
    doc.file = File.open(pdf_path)
    doc.save!

    RtaReconciliationAgent.wtf?(support_agent_id: support_agent.id, target: @fund, rta_pdf_document_id: doc.id)

    rpt = SupportAgentReport.where(owner: @fund, support_agent: support_agent, latest: true).first
    data = rpt.json_fields

    puts "\n-- #{label} (Document ##{doc.id}, Report ##{rpt.id}) --"
    puts "Health: #{data['health_score']}%  Schemes: #{(data['scheme_results'] || []).size}"
    puts "Aggregate: #{data['aggregate']}"
    blocking = (data["issues"] || []).select { |i| i["severity"] == "blocking" }
    warning  = (data["issues"] || []).select { |i| i["severity"] == "warning" }
    puts "Blocking issues (#{blocking.size}):"
    blocking.each { |i| puts "  - #{i['message']}" }
    puts "Warnings (#{warning.size}):"
    warning.each { |i| puts "  - #{i['message']}" }
  end
end
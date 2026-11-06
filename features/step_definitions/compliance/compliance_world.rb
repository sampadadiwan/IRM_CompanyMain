# Shared setup for the fund-compliance-monitoring features — builds business-rules › Shared setup:
# Horizon Capital (Growth Fund I, GIFT Opportunities, Seed Fund), Delta Partners, Solo Capital, users,
# investors, commitments, payments, investments, IC notes, the SEBI pack and Horizon's fund-agreement pack.
# Bulk rows (investors, commitments, payments, investments) are inserted directly: the checks read
# these tables with SQL, so model callbacks add nothing but time.
# openspec/changes/archive/2026-11-06-fund-compliance-monitoring/business-rules.md
module ComplianceWorld
  CRORE = 10_000_000
  IST = "Asia/Kolkata".freeze

  def cmp
    @cmp ||= { users: {}, funds: {}, investors: {}, entities: {}, investments: {}, docs: {} }
  end

  def cr(value)
    (value.to_d * CRORE).to_i
  end

  def cmp_date(text)
    Date.parse(text.to_s)
  end

  # ── Entities, users, funds ────────────────────────────────────────────────────────────────
  def cmp_entity!(name, type: "Investment Fund")
    cmp[:entities][name] ||= begin
      e = FactoryBot.create(:entity, name:, entity_type: type, currency: "INR", units: "Crores")
      e.permissions.set(:enable_compliance)
      e.save!
      e
    end
  end

  def horizon
    cmp[:entities]["Horizon Capital"]
  end

  # admin: company admin (all compliance roles); edit/approve: extended permission flags
  def cmp_user!(entity, first_name, admin: false, edit: false, approve: false, viewer: true, funds: :all)
    user = FactoryBot.create(:user, entity:, first_name:, last_name: "Test", email: "#{first_name.downcase}@#{entity.name.parameterize}.example")
    user.add_role(:company_admin) if admin
    user.permissions.unset(:enable_compliance) unless viewer
    user.extended_permissions.set(:compliance_edit) if edit
    user.extended_permissions.set(:compliance_approve) if approve
    user.save!
    cmp[:users][first_name] = user
    cmp[:fund_access] ||= {}
    cmp[:fund_access][first_name] = funds
    user
  end

  def cmp_user(name)
    cmp[:users].fetch(name) { User.find_by!(first_name: name) }
  end

  # Non-admin employees see the funds they have an access right on (X20)
  def cmp_grant_fund_access!(user, fund)
    AccessRight.create!(entity_id: fund.entity_id, owner: fund, user_id: user.id, metadata: "Employee")
  end

  def cmp_fund!(entity, name, category: nil, start_date: nil, currency: "INR")
    fund = FactoryBot.create(:fund, entity:, name:, category:, start_date:, currency:)
    cmp[:funds][name] = fund
    cmp[:users].each do |first_name, user|
      next unless user.entity_id == entity.id && !user.has_cached_role?(:company_admin)

      access = cmp[:fund_access][first_name]
      cmp_grant_fund_access!(user, fund) if access == :all || Array(access).include?(name)
    end
    fund
  end

  def cmp_fund(name)
    cmp[:funds].fetch(name) { Fund.find_by!(name:) }
  end

  # ── Bulk rows ─────────────────────────────────────────────────────────────────────────────
  def cmp_next_id
    cmp[:seq] = (cmp[:seq] || 9_000_000) + 1
  end

  def cmp_investor!(entity, name, category: "LP")
    key = [entity.id, name]
    cmp[:investors][key] ||= begin
      now = Time.current
      Investor.insert!({ entity_id: entity.id, investor_entity_id: cmp_next_id, investor_name: name, category:,
                         will_receive_email: false, show_to_lps: false, created_at: now, updated_at: now })
      Investor.find_by!(entity_id: entity.id, investor_name: name)
    end
  end

  def cmp_investors_bulk!(entity, prefix, count, category: "LP")
    now = Time.current
    rows = (1..count).map do |i|
      { entity_id: entity.id, investor_entity_id: cmp_next_id, investor_name: "#{prefix} #{i}", category:,
        will_receive_email: false, show_to_lps: false, created_at: now, updated_at: now }
    end
    rows.each_slice(500) { |s| Investor.insert_all!(s) }
    Investor.where(entity_id: entity.id).where("investor_name LIKE ?", "#{prefix} %").to_a
  end

  def cmp_commit!(fund, investor, amount, date = Date.new(2025, 6, 1))
    cmp_commit_bulk!(fund, [[investor.id, amount, date]])
  end

  def cmp_commit_bulk!(fund, rows)
    now = Time.current
    data = rows.map do |investor_id, amount, date|
      { entity_id: fund.entity_id, fund_id: fund.id, investor_id:, committed_amount_cents: amount.to_d * 100,
        folio_committed_amount_cents: amount.to_d * 100, commitment_date: date, folio_id: "F#{cmp_next_id}",
        lock_version: 0, created_at: now, updated_at: now }
    end
    data.each_slice(500) { |s| CapitalCommitment.insert_all!(s) }
  end

  # A payment needs a remittance and a call; one call per fund is enough for the figures
  def cmp_pay!(fund, investor, amount, date = Date.new(2025, 9, 1))
    now = Time.current
    call_id = cmp[:"call_#{fund.id}"] ||= begin
      CapitalCall.insert!({ entity_id: fund.entity_id, fund_id: fund.id, name: "Call 1", due_date: date, created_at: now, updated_at: now })
      CapitalCall.where(fund_id: fund.id).last.id
    end
    commitment = CapitalCommitment.where(fund_id: fund.id, investor_id: investor.id).first
    CapitalRemittance.insert!({ entity_id: fund.entity_id, fund_id: fund.id, capital_call_id: call_id, investor_id: investor.id,
                                capital_commitment_id: commitment.id, created_at: now, updated_at: now })
    remittance_id = CapitalRemittance.where(fund_id: fund.id, investor_id: investor.id).last.id
    CapitalRemittancePayment.insert!({ entity_id: fund.entity_id, fund_id: fund.id, capital_remittance_id: remittance_id,
                                       investor_id: investor.id, amount_cents: amount.to_d * 100, payment_date: date,
                                       created_at: now, updated_at: now })
    CapitalRemittancePayment.where(capital_remittance_id: remittance_id).last
  end

  def cmp_invest!(fund, company, amount, date = Date.new(2025, 6, 1), quantity: 100, sector: "Fintech")
    investee = cmp_investor!(fund.entity, company, category: "Portfolio Company")
    now = Time.current
    PortfolioInvestment.insert!({ entity_id: fund.entity_id, fund_id: fund.id, portfolio_company_id: investee.id,
                                  portfolio_company_name: company, investment_date: date, amount_cents: amount.to_d * 100,
                                  quantity:, sector:, aggregate_portfolio_investment_id: 0, ref_id: 0, excused_folio_ids: [],
                                  proforma: false, unrealized_price_effect_cents: 0, realized_price_effect_cents: 0,
                                  created_at: now, updated_at: now })
    pi = PortfolioInvestment.where(fund_id: fund.id, portfolio_company_id: investee.id).order(:id).last
    cmp[:investments][company] = pi
    pi
  end

  # An uploaded document on a record — e-sign completed on a date, or a wet-ink scan (signed_on marks it)
  def cmp_doc!(owner, tag: "IC Note", esign_completed_on: nil, signed_on: nil, marked_by: nil, uploaded_on: Time.zone.today)
    folder = cmp[:"folder_#{owner.entity_id}"] ||= Folder.create!(entity_id: owner.entity_id, name: "Compliance test docs", folder_type: :regular)
    now = uploaded_on.to_time
    user = marked_by || cmp[:users].values.detect { |u| u.entity_id == owner.entity_id }
    Document.insert!({ entity_id: owner.entity_id, folder_id: folder.id, user_id: user.id, owner_type: owner.class.name, owner_id: owner.id,
                       name: "#{tag} #{owner.id}", tag_list: tag, esign_status: esign_completed_on ? "completed" : "", send_email: false,
                       last_status_updated_at: esign_completed_on&.to_time, created_at: now, updated_at: now })
    doc = Document.where(owner_type: owner.class.name, owner_id: owner.id).order(:id).last
    DocumentSignoff.create!(entity_id: owner.entity_id, document: doc, signed_on:, marked_by: user) if signed_on
    doc
  end

  # ── Packs ─────────────────────────────────────────────────────────────────────────────────
  def cmp_sebi_data
    JSON.parse(Rails.root.join("db/seeds/compliance/sebi_aif_v1.json").read)
  end

  def cmp_sebi_pack!(effective: "2026-12-01")
    cmp[:sebi] ||= begin
      data = cmp_sebi_data
      data["version"].merge!("effective_from" => effective, "counsel_reviewer" => "A. Kapoor", "counsel_reviewed_on" => "2026-11-20")
      travel_to(Time.zone.parse("2026-11-01 10:00")) { CompliancePackLoader.call(data, publish: true) }
    end
  end

  def cmp_sebi_definition
    cmp_sebi_data["definition"]
  end

  # R158 / E193: a version cannot be published while a check has no plain-words description, so test
  # fixtures give every check one (scenarios about a missing description remove it on purpose)
  def cmp_described(definition)
    Array(definition["checks"]).each { |c| c["description"] ||= "#{c['name'] || c['key']} — test description of what it checks and why." }
    definition
  end

  # Horizon's own fund-agreement pack (entity pack): single-sector ≤ 15%, concentration ≤ 20%, IC note per investment
  def cmp_fa_definition
    cmp_described(cmp_fa_definition_raw)
  end

  def cmp_fa_definition_raw
    sebi = cmp_sebi_definition
    measures = sebi["measures"].select { |m| %w[corpus est_expenses investable_funds cost_per_investee].include?(m["key"]) } +
               [{ "key" => "cost_per_sector", "label" => "Investment cost per sector", "op" => "sum", "source" => "portfolio_investments",
                  "field" => "cost", "group_by" => "sector", "filters" => [%w[transaction eq buy]] }]
    {
      "currency" => "INR", "period_basis" => "calendar", "classifications" => ["All funds"],
      "inputs" => [{ "key" => "est_expenses", "type" => "fund_figure", "label" => "estimated expenses" },
                   { "key" => "ic_note", "type" => "document", "label" => "IC note" }],
      "measures" => measures,
      "checks" => [
        { "key" => "fa_single_sector", "name" => "Single-sector limit", "kind" => "limit", "applies_to" => "all",
          "figure" => ["/", "cost_per_sector", "investable_funds"], "compare" => "lte", "limit" => { "value" => 15, "unit" => "pct" },
          "tested" => "continuous", "override" => "any", "time_to_fix_days" => 30, "severity" => "breach", "citation" => "LPA cl. 8.2" },
        { "key" => "fa_concentration", "name" => "Fund agreement concentration", "kind" => "limit", "applies_to" => "all",
          "figure" => ["/", "cost_per_investee", "investable_funds"], "compare" => "lte", "limit" => { "value" => 20, "unit" => "pct" },
          "tested" => "continuous", "override" => "any", "time_to_fix_days" => 30, "severity" => "breach" },
        { "key" => "fa_ic_note", "name" => "IC note for every investment", "kind" => "record_document", "applies_to" => "all",
          "source" => "portfolio_investments", "document_input" => "ic_note", "filters" => [%w[transaction eq buy]],
          "checks_from" => "2026-04-01", "on_or_before_record" => true, "time_to_fix_days" => 30, "citation" => "LPA cl. 6.3" }
      ],
      "duties" => [{ "key" => "fa_key_person", "name" => "Key-person event notified", "trigger" => { "on_demand" => true }, "evidence" => true }]
    }
  end

  def cmp_entity_pack!(entity, name, definition, effective: "2026-04-01")
    pack = CompliancePack.create!(entity_id: entity.id, name:, regime: "Fund agreement", locked: false)
    v = pack.versions.create!(version_no: 1, definition:)
    v.mark_tested!(nil)
    v.publish!(user: nil, attrs: { effective_from: cmp_date(effective), applicability: "all" }) || raise(v.errors.full_messages.to_sentence)
    pack
  end

  def cmp_attach!(fund, pack, classification)
    FundCompliancePack.create!(entity_id: fund.entity_id, fund:, compliance_pack: pack, classification:, attached_on: Date.new(2026, 4, 1))
  end

  def cmp_fund_pack(fund_name, pack_name = "SEBI — AIF")
    FundCompliancePack.joins(:compliance_pack).find_by!(fund_id: cmp_fund(fund_name).id, compliance_packs: { name: pack_name })
  end

  def cmp_setup(entity = horizon)
    ComplianceEntitySetup.for(entity)
  end

  # ── The shared setup (business-rules › Shared setup) ──────────────────────────────────────
  def cmp_build_horizon!
    travel_to(Time.zone.parse("2026-11-01 10:00"))
    entity = cmp_entity!("Horizon Capital")
    cmp_user!(entity, "Meera", admin: true)
    cmp_user!(entity, "Arjun", edit: true)
    cmp_user!(entity, "Rahul", approve: true)
    cmp_user!(entity, "Vikram", funds: ["Horizon Growth Fund I", "Horizon Seed Fund"])
    cmp_user!(entity, "Anil", admin: true)
    growth = cmp_fund!(entity, "Horizon Growth Fund I", category: "Category II", start_date: Date.new(2025, 3, 15))
    cmp_fund!(entity, "Horizon GIFT Opportunities", category: nil, start_date: Date.new(2025, 6, 1), currency: "USD")
    cmp_fund!(entity, "Horizon Seed Fund", category: nil, start_date: Date.new(2025, 1, 1))

    # Commitments: sponsor ₹6.00 cr; 211 others = ₹294.00 cr (210 × ₹1.39 cr + 1 × ₹2.10 cr); 212 investors
    sponsor = cmp_investor!(entity, "Horizon Sponsor LLP", category: "Sponsor")
    others = cmp_investors_bulk!(entity, "LP", 211)
    cmp_commit!(growth, sponsor, cr(6))
    cmp_commit_bulk!(growth, others.first(210).map { |inv| [inv.id, cr("1.39"), Date.new(2025, 6, 1)] })
    cmp_commit!(growth, others.last, cr("2.10"))
    # Paid in: sponsor ₹2.10 cr; others ₹132.30 cr (45%)
    cmp_pay!(growth, sponsor, cr("2.10"))
    cmp_pay!(growth, others.last, cr("132.30"))
    cmp[:sponsor] = sponsor

    # Investments: Acme ₹72.00 cr (largest), others smaller; Fintech sector total ₹34.00 cr
    # Acme's sector is left blank so the single-sector check reads Fintech ₹34.00 cr ÷ ₹270.00 cr = 12.59% (proposal mockup)
    cmp_invest!(growth, "Acme Foods", cr(72), Date.new(2025, 6, 1), sector: nil)
    cmp_invest!(growth, "Zen Labs", cr(20), Date.new(2025, 7, 1), sector: "Fintech")
    cmp_invest!(growth, "Kite Pay", cr(14), Date.new(2025, 8, 1), sector: "Fintech")

    cmp_sebi_pack!
    fa = cmp_entity_pack!(entity, "Horizon — fund agreement limits", cmp_fa_definition)
    cmp[:fa] = fa
    cmp_attach!(growth, cmp[:sebi].compliance_pack, "Category II")

    setup = cmp_setup(entity)
    setup.set_mapping("sponsor", { "categories" => ["Sponsor"] })
    setup.set_mapping("ic_note", { "tag" => "IC Note" })
    setup.set_fund_figure("est_expenses", growth, cr(30))
    setup.owner = cmp_user("Meera")
    setup.monitoring_enabled = true
    setup.save!
    travel_back
  end

  # ── Runs and results ──────────────────────────────────────────────────────────────────────
  def cmp_run!(fund_name, date, trigger: "nightly", time: "02:00", zone: IST)
    fund = cmp_fund(fund_name)
    at = ActiveSupport::TimeZone[zone].parse("#{date} #{time}")
    travel_to(at) do
      ComplianceRunOperation.call_safely(fund_id: fund.id, run_date: at.to_date, trigger:, run_at: at)
    end
  end

  def cmp_latest(fund_name, check_key, pack_name = nil)
    fps = FundCompliancePack.where(fund_id: cmp_fund(fund_name).id)
    fps = fps.joins(:compliance_pack).where(compliance_packs: { name: pack_name }) if pack_name
    ComplianceResult.where(fund_compliance_pack_id: fps.select(:id), check_key:).order(:id).last
  end

  def cmp_check_key(name_or_key, fund_name = "Horizon Growth Fund I")
    return name_or_key if name_or_key.match?(/\A[a-z0-9_]+\z/)

    FundCompliancePack.where(fund_id: cmp_fund(fund_name).id).includes(:compliance_pack_version).find_each do |fp|
      check = fp.compliance_pack_version.checks.detect do |c|
        c["name"] == name_or_key && (c["applies_to"].nil? || c["applies_to"] == "all" || Array(c["applies_to"]).include?(fp.classification))
      end
      return check["key"] if check
    end
    raise "No check named #{name_or_key}"
  end

  def cmp_text(result)
    w = result.working_hash
    ([w["message"]] + Array(w["lines"]) + [w["override"], w["pending_override"]]).compact.join("\n")
  end
end
World(ComplianceWorld)

After do
  travel_back
end

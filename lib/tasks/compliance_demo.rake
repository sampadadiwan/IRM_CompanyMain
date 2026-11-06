# frozen_string_literal: true

# Sets up a demo of fund compliance monitoring on an existing fund so every Compliance screen has data
# to review: the SEBI pack (v1, plus v1.1 as an upcoming version) and an entity "LPA rules" pack attached,
# inputs mapped, IC notes (e-signed, wet-ink, late, unsigned, missing), facts read from IC notes (one set
# confirmed and corrected, one waiting), an AI-drafted check, nightly run history, register items
# (open, assigned, overdue and escalated, pending approval) and duties (due and done).
#
#   bin/rails compliance:demo                                   # dry run: prints the plan, writes nothing
#   EXECUTE=1 bin/rails compliance:demo                         # applies it (idempotent — safe to re-run)
#   EXECUTE=1 ENTITY_ID=157 FUND_ID=11 OWNER_EMAIL=fm10@demofund.com bin/rails compliance:demo
#
# Never in production. No AI is called: the drafting reply and the facts read from IC notes are stubbed,
# exactly as the Cucumber features stub them. No files are uploaded (dev storage is S3), so the demo IC
# notes are document records without a file.
# Worked examples are named on each step — openspec/changes/fund-compliance-monitoring/business-rules.md
namespace :compliance do
  desc "Set up a compliance demo on an existing fund (dry-run unless EXECUTE=1)"
  task demo: :environment do
    abort("compliance:demo is for development and staging only") if Rails.env.production?

    ComplianceDemoSetup.new(
      entity_id: ENV.fetch("ENTITY_ID", "157").to_i,
      fund_id: ENV.fetch("FUND_ID", "11").to_i,
      # fm10 is a company admin without the investor role; users who also hold the investor role are
      # never Compliance viewers (X22), so fm1@demofund.com cannot be the demo owner.
      owner_email: ENV.fetch("OWNER_EMAIL", "fm10@demofund.com"),
      execute: ENV["EXECUTE"] == "1"
    ).call
  end
end

# The demo, step by step. Every step is find-or-create, so a second EXECUTE=1 run changes nothing.
class ComplianceDemoSetup
  CRORE = 10_000_000
  IST = "Asia/Kolkata"
  CUSTOM_PACK = "Demo Fund — LPA rules"
  FOLDER = "Compliance demo"
  DOC_PREFIX = "IC Note (demo)"
  SEBI_V1 = "db/seeds/compliance/sebi_aif_v1.json"
  SEBI_V1_1 = "db/seeds/compliance/sebi_aif_v1_1.json"
  # Attached from 1 Jul 2026, so a run in late September creates the July–September duties
  ATTACHED_ON = Date.new(2026, 7, 1)
  DRAFT_SENTENCE = "No more than 15% of investable funds in any one sector — LPA clause 8.2"

  # A stand-in for RubyLLM's chat: answers with a fixed reply, never calls a provider (as the features do)
  class StubChat
    def initialize(reply)
      @reply = reply
    end

    def with_instructions(*, **)
      self
    end

    def with_schema(*)
      self
    end

    def ask(*, **)
      Struct.new(:content).new(@reply)
    end
  end

  def initialize(entity_id:, fund_id:, owner_email:, execute:)
    @entity = Entity.find(entity_id)
    @fund = Fund.where(entity_id: @entity.id).find(fund_id)
    @owner = User.find_by!(entity_id: @entity.id, email: owner_email)
    @execute = execute
    @today = ActiveSupport::TimeZone[IST].today
    @counts = Hash.new(0)
  end

  def call
    preflight
    return dry_run unless @execute

    enable_compliance
    sebi = load_sebi_pack
    custom = load_custom_pack
    @sebi_fp = attach(sebi, @fund.category.presence || "Category I")
    @custom_fp = attach(custom, "All funds")
    configure_setup
    # The first nightly run happens before any IC note exists (history shows the change)
    run_on(run_dates.first)
    add_ic_notes
    add_readings
    run_dates.drop(1).each { |d| run_on(d) }
    work_the_register
    complete_a_duty
    draft_with_ai(custom)
    report
  end

  private

  # ── Plan ────────────────────────────────────────────────────────────────────────────────────
  def preflight
    abort("#{@owner.email} cannot view Compliance (investor or advisor role, or not an employee) — choose another OWNER_EMAIL") unless ComplianceAccess.employee?(@owner)
    errors = ComplianceDefinitionValidator.call(custom_definition)
    abort("Custom pack definition is invalid: #{errors.join('; ')}") if errors.any?
  end

  def dry_run
    puts "DRY RUN — nothing written. Set EXECUTE=1 to apply."
    puts "Entity:  #{@entity.name} (#{@entity.id})"
    puts "Fund:    #{@fund.name} (#{@fund.id}, #{@fund.category}, #{@fund.currency})"
    puts "Owner:   #{@owner.full_name} <#{@owner.email}>"
    puts "Would:"
    puts "  - switch on Compliance for the entity and the owner, tag the owner \"Compliance\""
    puts "  - load SEBI — AIF v1 (effective #{ATTACHED_ON}) and v1.1 (upcoming) unless already loaded: #{sebi_pack ? 'already loaded' : 'not loaded'}"
    puts "  - create entity pack \"#{CUSTOM_PACK}\": #{CompliancePack.exists?(entity_id: @entity.id, name: CUSTOM_PACK) ? 'exists' : 'new'}"
    puts "  - attach both packs to #{@fund.name} from #{ATTACHED_ON}; map sponsor → Advisor, IC note → tag \"IC Note\", estimated expenses ₹15.00 cr"
    puts "  - add #{ic_note_plan.size} demo IC notes, 2 readings of IC-note facts (1 confirmed with a correction, 1 waiting)"
    puts "  - run nightly on #{run_dates.map(&:iso8601).join(', ')}"
    puts "  - assign one register item, escalate overdue items, send one explanation for approval, complete one duty"
    puts "  - draft one check with AI (stubbed reply) into a draft v2 of the custom pack, test-run and save it"
  end

  # Three earlier nightly runs (the first in last quarter) and today's
  def run_dates
    [Date.new(2026, 9, 28), @today - 2, @today - 1, @today].uniq.sort
  end

  # ── 1. Switch Compliance on (R6, E15: viewer = entity flag + user flag; company admin = editor + approver) ──
  def enable_compliance
    unless @entity.permissions.enable_compliance?
      @entity.permissions.set(:enable_compliance)
      # Only the flag column changes; Entity's own save callbacks have nothing to do with a demo
      @entity.update_columns(permissions: @entity.permissions.raw)
      @counts[:flags] += 1
    end
    unless @owner.get_permissions.enable_compliance?
      @owner.permissions.set(:enable_compliance)
      @owner.update_columns(permissions: @owner.permissions.raw)
      @counts[:flags] += 1
    end
    # Owners also include users tagged "Compliance" (design › Notifications)
    tags = @owner.tag_list.to_s.split(",").map(&:strip)
    @owner.update_columns(tag_list: (tags + ["Compliance"]).uniq.join(", ")) unless tags.include?("Compliance")
    @owner.reload
  end

  # ── 2. The CapHive SEBI pack through the pack loader (H1, H5; v1.1 shows as the upcoming version — H49) ──
  def sebi_pack
    CompliancePack.caphive.find_by(name: "SEBI — AIF")
  end

  def load_sebi_pack
    pack = sebi_pack
    load_sebi_file(SEBI_V1, ATTACHED_ON) if pack.nil?
    pack = sebi_pack
    # v1.1 adds the investor-group content check (R83); loaded once
    load_sebi_file(SEBI_V1_1, nil) unless pack.versions.any? { |v| v.check("sebi_investor_groups") }
    sebi_pack
  end

  # The shipped files carry "TO BE RECORDED" counsel fields; publishing needs a reviewer and date (X9),
  # so the demo records itself as the reviewer — never use this outside a demo
  def load_sebi_file(path, effective_from)
    data = JSON.parse(Rails.root.join(path).read)
    data["version"]["effective_from"] = effective_from.iso8601 if effective_from
    data["version"].merge!("counsel_reviewer" => "DEMO ONLY — not counsel reviewed", "counsel_reviewed_on" => @today.iso8601)
    CompliancePackLoader.call(data, publish: true)
    @counts[:pack_versions] += 1
  end

  # ── 3. The entity's own pack: concentration, IC note signed, IC-note contents, duties (H22, H41, E78) ──
  def custom_definition
    sebi = JSON.parse(Rails.root.join(SEBI_V1).read)["definition"]
    keep = %w[corpus est_expenses investable_funds cost_per_investee]
    measures = sebi["measures"].select { |m| keep.include?(m["key"]) }
    ic = { "source" => "portfolio_investments", "document_input" => "ic_note", "filters" => [%w[transaction eq buy]], "checks_from" => "2022-01-01",
           "applies_to" => "all", "severity" => "breach", "tested" => "continuous", "override" => "any", "time_to_fix_days" => 30 }
    {
      "currency" => "INR", "period_basis" => "fy_apr", "classifications" => ["All funds"],
      "inputs" => [
        { "key" => "est_expenses", "type" => "fund_figure", "label" => "estimated expenses" },
        # Left blank on purpose: the expense-cap check shows "Could not check — missing" (X24)
        { "key" => "fund_expenses", "type" => "fund_figure", "label" => "fund expenses (year to date)" },
        { "key" => "ic_note", "type" => "document", "label" => "IC note", "facts" => [
          { "key" => "company", "label" => "Company", "type" => "text" },
          { "key" => "amount_approved", "label" => "Amount approved", "type" => "amount" },
          { "key" => "approval_date", "label" => "Approval date", "type" => "date" },
          { "key" => "business", "label" => "Business", "type" => "text" }
        ] }
      ],
      "reference_lists" => [{ "key" => "excluded_sectors" }],
      "measures" => measures + [{ "key" => "fund_expenses", "label" => "Fund expenses (year to date)", "op" => "input", "input" => "fund_expenses" }],
      "checks" => [
        # H20-style limit: largest investee ÷ investable funds ≤ 20%
        { "key" => "lpa_single_company", "name" => "Single-company limit", "kind" => "limit", "applies_to" => "all",
          "figure" => ["/", "cost_per_investee", "investable_funds"], "compare" => "lte", "limit" => { "value" => 20, "unit" => "pct" },
          "tested" => "continuous", "override" => "any", "time_to_fix_days" => 30, "severity" => "breach", "citation" => "LPA cl. 8.1" },
        # X24: a figure the firm has not entered yet → "Could not check — missing: fund expenses (year to date)"
        { "key" => "lpa_expense_cap", "name" => "Fund expenses within 2% of corpus", "kind" => "limit", "applies_to" => "all",
          "figure" => ["/", "fund_expenses", "corpus"], "compare" => "lte", "limit" => { "value" => 2, "unit" => "pct" },
          "tested" => "continuous", "override" => "any", "time_to_fix_days" => 30, "severity" => "breach", "citation" => "LPA cl. 9.2" },
        # H22/H23: every buy from 1 Jan 2022 has an IC note signed on or before the investment date;
        # 2 days to fix, so the item opened on 28 Sep is overdue (E35, E36)
        { "key" => "lpa_ic_note", "name" => "IC note for every investment", "kind" => "record_document", "applies_to" => "all",
          "source" => "portfolio_investments", "document_input" => "ic_note", "filters" => [%w[transaction eq buy]],
          "checks_from" => "2022-01-01", "on_or_before_record" => true, "time_to_fix_days" => 2, "citation" => "LPA cl. 6.3" },
        # H41: invested within the amount the IC approved — the confirmed note is within it, the rest wait, so the
        # check as a whole is "Needs review" (E66)
        ic.merge("key" => "lpa_ic_amount", "name" => "Invested within IC approval", "kind" => "content", "rule" => "record_within_fact",
                 "field" => "cost", "fact" => "amount_approved", "words" => { "record" => "invested", "fact" => "approved" },
                 "citation" => "LPA cl. 6.4"),
        # E78: the business the IC note describes is not on the excluded-sector list
        ic.merge("key" => "lpa_excluded_sector", "name" => "Not in an excluded sector", "kind" => "content", "rule" => "text_not_in_list",
                 "fact" => "business", "list" => "excluded_sectors", "words" => { "breach" => "Excluded sector" }, "citation" => "LPA sch. 2")
      ],
      "duties" => [
        # H27/E120: one per quarter, due 30 days after the quarter ends; no evidence needed
        { "key" => "lpa_quarterly_lp_report", "name" => "Quarterly LP report sent", "trigger" => { "schedule" => "quarterly" },
          "due" => { "days_after" => "period_end", "n" => 30 }, "evidence" => false, "applies_to" => "all" },
        { "key" => "lpa_key_person", "name" => "Key-person event notified to LPs", "trigger" => { "on_demand" => true },
          "evidence" => true, "applies_to" => "all" }
      ]
    }
  end

  def load_custom_pack
    pack = CompliancePack.find_or_create_by!(entity_id: @entity.id, name: CUSTOM_PACK) do |p|
      p.regime = "Fund agreement"
      p.locked = false
    end
    return pack if pack.latest_published_version

    # H5: tested, then published (entity packs apply to all funds — E98)
    v = pack.versions.create!(version_no: 1, definition: custom_definition)
    v.mark_tested!(@owner)
    v.publish!(user: @owner, attrs: { effective_from: ATTACHED_ON, applicability: "all" }) || raise(v.errors.full_messages.to_sentence)
    @counts[:pack_versions] += 1
    pack.reload
  end

  # ── 4. Attach with a classification (H11, E9) ────────────────────────────────────────────────
  def attach(pack, classification)
    existing = FundCompliancePack.find_by(fund_id: @fund.id, compliance_pack_id: pack.id)
    return existing if existing

    @counts[:attachments] += 1
    FundCompliancePack.create!(entity_id: @entity.id, fund: @fund, compliance_pack: pack, classification:, attached_on: ATTACHED_ON)
  end

  # ── 5. Inputs, lists, owner, AI switches (H17, X15, E14, R13) ────────────────────────────────
  def configure_setup
    setup = ComplianceEntitySetup.for(@entity)
    # Sponsor/manager → the "Advisor" investor category (₹2.00 cr committed): continuing interest breaches (H21)
    setup.set_mapping("sponsor", { "categories" => ["Advisor"] })
    # Employees/directors left unmapped on purpose: that check shows "Could not check — missing" (X29)
    setup.set_mapping("ic_note", { "tag" => "IC Note" })
    setup.set_fund_figure("est_expenses", @fund, 15 * CRORE)
    setup.set_reference_list("excluded_sectors", entries: %w[Tobacco Gambling Weapons].map { |n| { "name" => n } })
    setup.owner = @owner
    setup.monitoring_enabled = true
    # Describe in words on (H37); IC-note reading on (E74). The sweep mark is "now": documents without a
    # file are never queued, so no AI call can follow from this demo
    setup.ai_settings = setup.ai_settings_hash.merge("drafting" => true, "reading" => { "ic_note" => true },
                                                     "reading_swept_at" => Time.current.iso8601)
    setup.save!
    @setup = setup
  end

  # ── 6. Nightly runs through the run operation (H19, E17: one per fund per date) ──────────────
  def run_on(date)
    at = ActiveSupport::TimeZone[IST].local(date.year, date.month, date.day, 2, 0)
    before = ComplianceRun.exists?(fund_id: @fund.id, run_date: date, trigger: "nightly", status: "succeeded")
    ComplianceRunOperation.call_safely(fund_id: @fund.id, run_date: date, trigger: "nightly", run_at: at)
    run = ComplianceRun.where(fund_id: @fund.id, run_date: date, trigger: "nightly").order(:id).last
    raise "Run on #{date} did not finish: #{run&.status} #{run&.error_summary}" unless run&.status == "succeeded"

    @counts[:runs] += 1 unless before
  end

  # ── 7. IC notes on investments from 2022 (H22 signed, E27 wet ink, H23 signed late, E26 unsigned, rest missing) ──
  def ic_note_plan
    buys = PortfolioInvestment.where(fund_id: @fund.id).where("quantity > 0").where(investment_date: Date.new(2022, 1, 1)..)
                              .order(:investment_date, :id).to_a
    by_size = buys.sort_by { |pi| -pi.amount_cents.to_d }
    # The three largest (signed two ways), then the earliest and latest of the rest (signed late, unsigned)
    largest = by_size.first(3)
    rest = buys - largest
    picks = (largest + [rest.first, rest.last]).compact.uniq
    kinds = %i[esign esign wet_ink wet_ink_late unsigned]
    picks.zip(kinds)
  end

  def add_ic_notes
    folder = Folder.find_or_create_by!(entity_id: @entity.id, name: FOLDER) { |f| f.folder_type = :regular }
    @ic_docs = {}
    ic_note_plan.each do |pi, kind|
      name = "#{DOC_PREFIX} — #{pi.portfolio_company_name} #{pi.investment_date.iso8601}"
      doc = Document.find_by(entity_id: @entity.id, owner_type: "PortfolioInvestment", owner_id: pi.id, name:)
      doc ||= insert_doc(pi, folder, name, kind)
      @ic_docs[kind] ||= []
      @ic_docs[kind] << [pi, doc]
      # E27 wet ink: signed on paper and marked signed with the date; H23: one signed after the investment
      next unless %i[wet_ink wet_ink_late].include?(kind) && !DocumentSignoff.exists?(document_id: doc.id)

      signed_on = kind == :wet_ink ? pi.investment_date - 2.days : pi.investment_date + 10.days
      DocumentSignoff.create!(entity_id: @entity.id, document: doc, signed_on:, marked_by: @owner)
      @counts[:signoffs] += 1
    end
  end

  # A document record without a file (the demo uploads nothing); e-signed ones carry the completion date
  def insert_doc(pi, folder, name, kind)
    uploaded = pi.investment_date - 5.days
    esigned = kind == :esign ? (pi.investment_date - 3.days).to_time : nil
    Document.insert!({ entity_id: @entity.id, folder_id: folder.id, user_id: @owner.id, owner_type: "PortfolioInvestment",
                       owner_id: pi.id, name:, tag_list: "IC Note", esign_status: esigned ? "completed" : "", send_email: false,
                       last_status_updated_at: esigned, created_at: uploaded.to_time, updated_at: uploaded.to_time })
    @counts[:ic_notes] += 1
    Document.where(entity_id: @entity.id, owner_type: "PortfolioInvestment", owner_id: pi.id, name:).order(:id).last
  end

  # ── 8. Facts read from IC notes (stubbed AI): one set corrected and confirmed → excluded-sector breach (E67, E78);
  #       one set waiting → "Needs review — AI-read, unconfirmed" and the Facts-to-confirm list (H40, E66) ──
  def add_readings
    input = ComplianceDocumentInputs.find(@entity, "ic_note")
    largest_pi, largest_doc = @ic_docs[:esign].first
    second_pi, second_doc = @ic_docs[:esign].second || @ic_docs[:wet_ink].first
    invested = largest_pi.amount_cents.to_d / 100
    approved = (invested * BigDecimal("1.1")).round(-5).to_d # approved 10% more than invested → this row passes
    confirmed = read_facts(largest_doc, input, {
                             "company" => [largest_pi.portfolio_company_name, "Investee: #{largest_pi.portfolio_company_name}", 1],
                             # The AI misread the amount by a factor of 100; the owner corrects it on confirm (E67)
                             "amount_approved" => [(approved / 100).to_s("F"), "approves an investment of up to INR #{(approved / CRORE).round(2).to_s('F')} crore", 2],
                             "approval_date" => [(largest_pi.investment_date - 7.days).iso8601, "Approved on #{(largest_pi.investment_date - 7.days).strftime('%-d %B %Y')}", 2],
                             "business" => ["Tobacco products distribution", "Business: tobacco products distribution", 1]
                           })
    if confirmed.document_facts.none?(&:confirmed?)
      Audited.audit_class.as_user(@owner) do
        DocumentFactConfirm.call(reading: confirmed, user: @owner, values: { "amount_approved" => approved.to_s("F") })
      end
      @counts[:facts_confirmed] += confirmed.document_facts.size
    end
    read_facts(second_doc, input, {
                 "company" => [second_pi.portfolio_company_name, "Investee: #{second_pi.portfolio_company_name}", 1],
                 "amount_approved" => [(second_pi.amount_cents.to_d / 100).to_s("F"), "approves an investment of the full amount", 2],
                 "approval_date" => [(second_pi.investment_date - 5.days).iso8601, "Approved by the Committee", 2],
                 "business" => ["Specialty chemicals", "Business: specialty chemicals", 1]
               })
  end

  # One stored reading with AI-read facts, as DocumentFactReader would leave it (never sent: no file)
  def read_facts(doc, input, facts)
    attrs = { document_id: doc.id, input_key: "ic_note", file_checksum: DocumentReading.checksum_for(doc), facts_signature: input.signature }
    reading = DocumentReading.find_by(attrs)
    return reading if reading

    reading = DocumentReading.create!(attrs.merge(entity_id: @entity.id, status: "read", sent_at: Time.current, llm_model: "demo stub — no AI call"))
    input.facts.each do |f|
      value, quote, page = facts.fetch(f["key"])
      reading.document_facts.create!(entity_id: @entity.id, fact_key: f["key"], value_type: f["type"],
                                     value: DocumentFact.normalize(f["type"], value), quote:, page:, source: "ai", status: "ai_read")
    end
    @counts[:readings] += 1
    reading.reload
  end

  # ── 9. Register: assign one item (H26), escalate overdue ones (E36), one explanation pending (E32, E46) ──
  def work_the_register
    items = ComplianceRegisterItem.open_items.where(fund_id: @fund.id)
    # Assign the newest open item (fix-by still ahead) to the owner, as the Assign button does
    fresh = items.where(assignee_id: nil).order(opened_on: :desc, id: :desc).first
    if fresh && items.where.not(assignee_id: nil).none?
      fresh.update!(assignee: @owner, status: "in_progress")
      ComplianceNotices.assignment(fresh, @owner)
      @counts[:assigned] += 1
    end
    # The morning housekeeping: past fix-by → owner and approvers told once
    overdue = items.where(escalated_on: nil).where(fix_by: ...@today).count
    @counts[:escalated] += overdue if overdue.positive?
    ComplianceMaintenance.escalate_overdue(@entity, @today)
    explain_one(items)
  end

  def explain_one(items)
    return if ComplianceRequest.exists?(entity_id: @entity.id, kind: "explanation", target_type: "ComplianceRegisterItem",
                                        target_id: items.select(:id))

    item = items.where(status: "open").detect { |i| i.check_key == "lpa_single_company" } || items.where(status: "open").first
    return if item.nil?

    result = ComplianceRequestSubmit.call(user: @owner, kind: "explanation", target: item, check_key: item.check_key,
                                          reason: "Legacy holding from before the LPA amendment; sell-down planned for Q4",
                                          payload: { "text" => "Legacy holding — sell-down planned" })
    raise "Explanation refused: #{result.error}" unless result.success?

    @counts[:requests] += 1
  end

  # ── 10. Duties: last quarter's LP report marked done (late); this quarter's stays due (H27, E44, E120) ──
  def complete_a_duty
    duty = ComplianceDuty.where(fund_compliance_pack_id: @custom_fp.id, duty_key: "lpa_quarterly_lp_report").not_done
                         .where(due_on: ...@today).order(:due_on).first
    return if duty.nil?

    result = ComplianceDutyComplete.call(duty:, user: @owner, note: "Sent to all LPs with the Q2 report pack")
    raise "Duty not completed: #{result.error}" if result.respond_to?(:error) && result.error

    @counts[:duties_done] += 1
  end

  # ── 11. Describe in words (stubbed AI) into a draft v2, test-run on the fund, save with provenance (H37, H38) ──
  def draft_with_ai(pack)
    draft_version = pack.draft_version || pack.versions.create!(version_no: pack.versions.maximum(:version_no) + 1,
                                                                definition: pack.latest_published_version.definition_hash)
    return if ComplianceCheckDraft.exists?(compliance_pack_version_id: draft_version.id, status: "saved")

    draft = ComplianceCheckDraft.create!(entity_id: @entity.id, compliance_pack_version: draft_version, user: @owner, sentence: DRAFT_SENTENCE)
    reply = { "kind" => "limit", "name" => "Single-sector limit (AI)", "citation" => "LPA cl. 8.2",
              "figure" => { "op" => "sum", "source" => "portfolio_investments", "field" => "cost", "group_by" => "sector",
                            "filters" => [{ "field" => "transaction", "op" => "eq", "value" => "buy" }] },
              "divided_by" => { "measure" => "investable_funds" }, "compare" => "lte", "limit_value" => 15, "limit_unit" => "pct",
              "assumptions" => [{ "part" => "figure", "text" => "Assumed: investment cost of buys, grouped by the sector on each investment" }] }
    with_stub_llm(reply.to_json) { ComplianceCheckDrafter.call(draft:) }
    raise "Drafting failed: #{draft.reload.failure_reason}" unless draft.reload.ready?

    # E63: the test run is inside CapHive, no AI
    draft.update!(test_result: ComplianceCheckDraftTest.call(draft:, fund: @fund), test_fund_id: @fund.id)
    errors = draft.save_into_version!(@owner)
    raise "Draft not saved: #{errors.join('; ')}" if errors.any?

    draft_version.mark_tested!(@owner)
    @counts[:ai_drafts] += 1
  end

  # Swap LlmService.ruby_llm_chat for the stub only for the block, then restore it
  def with_stub_llm(reply)
    original = LlmService.method(:ruby_llm_chat)
    LlmService.define_singleton_method(:ruby_llm_chat) { |**| StubChat.new(reply) }
    yield
  ensure
    LlmService.define_singleton_method(:ruby_llm_chat, original)
  end

  # ── Summary ─────────────────────────────────────────────────────────────────────────────────
  def report
    fp_ids = [@sebi_fp.id, @custom_fp.id]
    latest_run = ComplianceRun.where(fund_id: @fund.id, status: "succeeded").order(:run_date, :id).last
    outcomes = ComplianceResult.where(compliance_run_id: latest_run.id).group(:outcome).count
    puts "Created this run: #{@counts.to_h.presence || 'nothing (already set up)'}"
    puts "Fund packs: SEBI #{@sebi_fp.id}, LPA rules #{@custom_fp.id}"
    puts "Runs: #{ComplianceRun.where(fund_id: @fund.id).count}; latest #{latest_run.run_date} results #{outcomes}"
    puts "Register: #{ComplianceRegisterItem.where(fund_compliance_pack_id: fp_ids).group(:status).count}"
    puts "Duties: #{ComplianceDuty.where(fund_compliance_pack_id: fp_ids).count} (done #{ComplianceDuty.where(fund_compliance_pack_id: fp_ids).where.not(done_on: nil).count})"
    puts "Requests pending: #{ComplianceRequest.pending.where(entity_id: @entity.id).count}"
    puts "Readings: #{DocumentReading.where(entity_id: @entity.id).count}; facts waiting: #{DocumentFact.where(entity_id: @entity.id).where.not(status: 'confirmed').count}"
    puts "Sign in as #{@owner.email} and open /compliance"
  end
end

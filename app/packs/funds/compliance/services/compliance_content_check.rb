# ⑤ Shape 3 — document contents. Plain rules compare a document's confirmed facts with CapHive's
# records and reference lists; AI never decides pass or fail (it only read the facts, once, earlier).
#
# Rules (check["rule"]) — fixed in code, chosen and parameterised by the pack:
#   record_within_fact          record field ≤ amount fact             "₹3.00 cr over approved"      (H41, E70)
#   fact_date_not_after_record  date fact ≤ the record's date                                         (E71)
#   quorum                      signatories on the dated list ≥ quorum, on the signed date            (H42, E72, E73, H54, E103, E104)
#   names_disjoint              no name in both facts                  "Conflicted member approved"  (X47)
#   matches_record              company named = the record's company; another investee → Needs review (E76, E77)
#   text_not_in_list            text fact names no list entry          "Excluded sector: Tobacco"     (E78)
#   names_not_in_list           no name on the list                    associates, land-border        (E79, E136)
#   common_owner_share          investors sharing a confirmed beneficial owner < limit % of commitments (E55, E56)
# Lists come from the pack (shipped, e.g. land-border countries) or the entity's setup, as they stood on
# the document's signed date (R1). The record a document is attached to decides what it is compared
# with, so facts follow a moved document (E129).
# Worked examples H41, H42, H54, E55, E56, E66, E69, E70–E79, E103, E104, E129, E136, X47 —
# openspec/changes/fund-compliance-monitoring/business-rules.md
class ComplianceContentCheck
  RULES = %w[record_within_fact fact_date_not_after_record quorum names_disjoint matches_record text_not_in_list
             names_not_in_list common_owner_share].freeze
  # Facts each rule reads: check keys holding fact keys
  RULE_FACTS = {
    "record_within_fact" => %w[fact], "fact_date_not_after_record" => %w[fact], "quorum" => %w[fact],
    "names_disjoint" => %w[fact other_fact], "matches_record" => %w[fact], "text_not_in_list" => %w[fact],
    "names_not_in_list" => %w[fact], "common_owner_share" => %w[fact]
  }.freeze
  # Rules that compare with a reference list
  LIST_RULES = %w[quorum text_not_in_list names_not_in_list].freeze
  COMPANY_SUFFIXES = /\b(private|pvt|limited|ltd|llp|inc|incorporated|corp|corporation|co|company|plc|gmbh|pte)\b/

  Result = Struct.new(:outcome, :figure, :lines, :failing, :extra, keyword_init: true)
  Doc = Struct.new(:id, :owner_id, :signed_on, keyword_init: true)

  def self.call(check, context)
    new(check, context).call
  end

  def self.norm_name(name)
    name.to_s.downcase.gsub(/[^a-z0-9 ]/, " ").squish
  end

  def self.norm_company(name)
    norm_name(name).gsub(COMPANY_SUFFIXES, " ").squish
  end

  def initialize(check, context)
    @check = check
    @ctx = context
    @rule = check["rule"].to_s
    # The facts the rule reads, plus the quorum's date fact (the list is taken as on that date — R87)
    @needed = (RULE_FACTS.fetch(@rule, []) + %w[date_fact]).filter_map { |k| check[k].presence }.uniq
  end

  def call
    return owner_share if @rule == "common_owner_share"

    records = record_rows
    from = @check["checks_from"].present? ? Date.parse(@check["checks_from"].to_s) : nil
    earlier, checked = records.partition { |r| from && (r[:date].nil? || r[:date] < from) }
    docs = latest_documents(checked.pluck(:id))
    source = fact_source(docs.values.map(&:id))
    failing = checked.filter_map do |rec|
      doc = docs[rec[:id]]
      next if doc.nil? # no document at all is the record-document check's job (shape 2)

      problem_for(rec, doc, source)
    end
    summarise(checked.size, failing, earlier.size, without: checked.count { |r| docs[r[:id]].nil? })
  end

  private

  def mapping
    @mapping ||= @ctx.setup&.document_mapping(@check["document_input"]) ||
                 raise(ComplianceMeasureQuery::MissingInput, @ctx.input(@check["document_input"])["label"].presence || @check["document_input"].to_s.humanize)
  end

  def currency
    @ctx.version.currency
  end

  def fact_source(document_ids)
    ComplianceFactSource.new(entity: @ctx.fund.entity, input_key: @check["document_input"], document_ids:, version: @ctx.version, setup: @ctx.setup)
  end

  # Records of the fund (filters as in the pack, e.g. buys only), with label, date and the compared field
  def record_rows
    src = ComplianceDataCatalog.source(@check["source"])
    model = ComplianceDataCatalog.model(@check["source"])
    scope = fund_records(model)
    scope = ComplianceMeasureQuery.new(@ctx).send(:apply_filters, scope, @check["source"], @check["filters"])
    cols = [:id, src.record_date.to_sym]
    cols << :portfolio_company_name if model.column_names.include?("portfolio_company_name")
    return kyc_rows(scope) if model == InvestorKyc

    field_sql = @check["field"].present? ? Arel.sql(ComplianceDataCatalog.field_sql(@check["source"], @check["field"])) : nil
    rows = field_sql ? scope.unscope(:order).pluck(*cols, field_sql) : scope.unscope(:order).pluck(*cols)
    rows.map do |row|
      id, date, *rest = row
      label = cols.include?(:portfolio_company_name) ? rest.shift : nil
      { id:, date: date&.to_date, label: label.presence || "##{id}", value: rest.first }
    end
  end

  # Records of this fund; KYCs carry no fund, so they are the KYCs of the fund's committed investors (E136)
  def fund_records(model)
    base = model.where(entity_id: @ctx.fund.entity_id)
    return base.where(fund_id: @ctx.fund.id) if model.column_names.include?("fund_id")

    base.where(investor_id: CapitalCommitment.where(entity_id: @ctx.fund.entity_id, fund_id: @ctx.fund.id).select(:investor_id))
  end

  def kyc_rows(scope)
    rows = scope.unscope(:order).pluck(:id, :investor_id, :created_at)
    names = Investor.where(id: rows.map(&:second)).pluck(:id, :investor_name).to_h
    rows.map { |id, investor_id, at| { id:, date: at&.to_date, label: names[investor_id] || "##{id}", value: nil } }
  end

  # Newest mapped document of each record, with its signed date (wet ink or e-sign completed)
  def latest_documents(record_ids)
    return {} if record_ids.empty?

    model = ComplianceDataCatalog.model(@check["source"])
    scope = Document.where(entity_id: @ctx.fund.entity_id, owner_type: model.name, owner_id: record_ids)
    scope = if mapping["tag"].present?
              scope.where("documents.tag_list LIKE ?", "%#{Document.sanitize_sql_like(mapping['tag'])}%")
            else
              scope.where(name: mapping["name"])
            end
    rows = scope.order(:id).pluck(:id, :owner_id, :esign_status, :last_status_updated_at)
    wet = DocumentSignoff.where(document_id: rows.map(&:first)).pluck(:document_id, :signed_on).to_h
    rows.each_with_object({}) do |(id, owner_id, status, at), out|
      signed = wet[id] || (status.to_s.casecmp?("completed") ? at&.to_date : nil)
      out[owner_id] = Doc.new(id:, owner_id:, signed_on: signed) # later ids overwrite: newest wins
    end
  end

  def problem_for(rec, doc, source)
    state = source.state(doc.id, @needed)
    return failing_row(rec, doc, "needs_review", state.problem) unless state.usable

    outcome, text = evaluate_rule(rec, doc, state.facts)
    outcome == "pass" ? nil : failing_row(rec, doc, outcome, text)
  end

  # document_id lets the result page link to the document's facts (confirm or enter by hand)
  def failing_row(rec, doc, outcome, problem)
    { "id" => rec[:id], "label" => rec[:label], "date" => rec[:date]&.iso8601, "outcome" => outcome, "problem" => problem,
      "document_id" => doc.id }
  end

  def severity
    @check["severity"].presence || "breach"
  end

  def words
    @check["words"].is_a?(Hash) ? @check["words"] : {}
  end

  def fmt(value)
    ComplianceFormat.amount(value, currency)
  end

  def evaluate_rule(rec, doc, values)
    fact = values[@check["fact"]]
    case @rule
    when "record_within_fact" then within_fact(rec, fact)
    when "fact_date_not_after_record" then date_not_after(rec, fact)
    when "quorum" then quorum(rec, doc, values, fact)
    when "names_disjoint" then disjoint(fact, values[@check["other_fact"]])
    when "matches_record" then matches_record(rec, fact)
    when "text_not_in_list" then text_not_in_list(doc, fact)
    when "names_not_in_list" then names_not_in_list(doc, fact)
    else [severity, "Unknown rule"]
    end
  end

  # H41, E70: ₹18.00 cr invested > ₹15.00 cr approved — ₹3.00 cr over approved
  def within_fact(rec, approved)
    invested = rec[:value].to_d
    return ["pass", nil] if approved && invested <= approved.to_d.round(2)

    rec_word = words["record"].presence || "invested"
    fact_word = words["fact"].presence || "approved"
    [severity, "#{fmt(invested)} #{rec_word} > #{fmt(approved)} #{fact_word} — #{fmt(invested - approved.to_d)} over #{fact_word}"]
  end

  # E71: approval dated on or before the record's date
  def date_not_after(rec, date)
    return ["pass", nil] if date && rec[:date] && date <= rec[:date]

    [severity, "#{fact_label} #{date ? I18n.l(date) : '—'} is after the record date #{rec[:date] ? I18n.l(rec[:date]) : '—'}"]
  end

  def fact_label
    ComplianceDocumentInputs.version_facts(@ctx.version, @check["document_input"]).detect { |f| f["key"] == @check["fact"] }&.dig("label") ||
      @check["fact"].to_s.humanize
  end

  # H42, E72, E73, H54, E103, E104: listed members (as on the signed date) among the signatories ≥ quorum
  def quorum(rec, doc, values, signatories)
    on = doc.signed_on || (@check["date_fact"].present? && values[@check["date_fact"]]) || rec[:date] || @ctx.as_of
    on = on.to_date if on.respond_to?(:to_date)
    members_on = list_entries(on)
    members_ever = list_entries(nil)
    quorum = @ctx.setup&.quorum(@check["list"]).to_i
    counted, others = Array(signatories).partition { |n| members_on.include?(self.class.norm_name(n)) }
    return ["pass", nil] if counted.size >= quorum && quorum.positive?

    notes = others.map do |n|
      members_ever.include?(self.class.norm_name(n)) ? "#{n} — not an IC member on #{I18n.l(on)}" : "#{n} — not an IC member"
    end
    [severity, (["#{counted.size} IC member#{'s' if counted.size != 1} signed, quorum #{quorum}"] + notes).join(" · ")]
  end

  # X47: a member who declared a conflict is among the signatories
  def disjoint(names, other)
    clash = Array(names).select { |n| Array(other).map { |o| self.class.norm_name(o) }.include?(self.class.norm_name(n)) }
    return ["pass", nil] if clash.empty?

    [severity, "#{words['breach'].presence || 'In both lists'}: #{clash.join(', ')}"]
  end

  # E76 (another name → Breach naming both) and E77 (another investee's document → Needs review)
  def matches_record(rec, company)
    named = self.class.norm_company(company)
    return ["pass", nil] if named.present? && named == self.class.norm_company(rec[:label])

    other = other_investees.detect { |n| self.class.norm_company(n) == named && named.present? }
    return ["needs_review", "Document appears to concern #{other}"] if other

    [severity, "Document names #{company.presence || '—'}; record is #{rec[:label]}"]
  end

  def other_investees
    @other_investees ||= PortfolioInvestment.where(entity_id: @ctx.fund.entity_id).unscope(:order)
                                            .distinct.pluck(:portfolio_company_name).compact
  end

  # E78: "tobacco products" names the excluded sector Tobacco
  def text_not_in_list(doc, text)
    hay = self.class.norm_name(text)
    hit = list_raw(doc.signed_on).detect { |entry| (e = self.class.norm_name(entry)).present? && hay.match?(/\b#{Regexp.escape(e)}\b/) }
    return ["pass", nil] if hit.nil?

    [severity, "#{words['breach'].presence || 'On the list'}: #{hit}"]
  end

  # E79, E136: a director on the sponsor's associates list; an owner's country on the land-border list
  def names_not_in_list(doc, names)
    listed = list_entries(doc.signed_on)
    hits = Array(names).select { |n| listed.include?(self.class.norm_name(n)) }
    return ["pass", nil] if hits.empty?

    [severity, "#{words['breach'].presence || 'On the list'}: #{hits.join(', ')}"]
  end

  # Entries of the check's list as on a date: shipped with the pack, or entered in the entity's setup
  def list_raw(on)
    pack_list = Array(@ctx.version.definition_hash["reference_lists"]).detect { |l| l["key"] == @check["list"] }
    return Array(pack_list["entries"]).map(&:to_s) if pack_list && pack_list["entries"].present?

    @ctx.setup ? @ctx.setup.reference_list(@check["list"], on:) : []
  end

  def list_entries(on)
    list_raw(on).map { |n| self.class.norm_name(n) }
  end

  # E55, E56 — SEBI check 7: investors grouped by a common beneficial owner in confirmed KYC facts;
  # a group holding ≥ the limit share of commitments needs enhanced due diligence (Needs review + duty)
  def owner_share
    commitments = CapitalCommitment.where(entity_id: @ctx.fund.entity_id, fund_id: @ctx.fund.id).where("committed_amount_cents > 0")
                                   .group(:investor_id).sum(:committed_amount_cents)
    total = commitments.values.sum.to_d
    kycs = InvestorKyc.where(entity_id: @ctx.fund.entity_id, investor_id: commitments.keys).pluck(:id, :investor_id)
    docs = owner_documents(kycs.map(&:first))
    source = fact_source(docs.values.map(&:id))
    names = Investor.where(id: commitments.keys).pluck(:id, :investor_name).to_h
    owners = Hash.new { |h, k| h[k] = [] }
    failing = []
    kycs.each do |kyc_id, investor_id|
      doc = docs[kyc_id]
      next if doc.nil?

      state = source.state(doc.id, @needed)
      if state.usable
        owners[investor_id] |= Array(state.facts[@check["fact"]]).map { |n| self.class.norm_name(n) }.compact_blank
      else
        failing << { "id" => investor_id, "label" => names[investor_id], "outcome" => "needs_review", "problem" => state.problem,
                     "document_id" => doc.id }
      end
    end
    groups = group_by_common_owner(owners)
    limit = @check.dig("limit", "value").to_d
    subjects = []
    lines = []
    groups.each do |members|
      share = total.zero? ? 0.to_d : members.sum { |i| commitments[i].to_d } / total
      pct = ComplianceFormat.pct_value(share)
      next if pct < limit

      subjects << members.min
      failing << { "id" => members.min, "label" => members.map { |i| names[i] }.sort.join(", "), "outcome" => severity,
                   "problem" => "Investor group #{ComplianceFormat.pct(share)} of commitments (≥ #{ComplianceFormat.limit(limit, 'pct')}) — enhanced due diligence" }
    end
    lines << "#{groups.size} investor group#{'s' if groups.size != 1} with a common beneficial owner"
    Result.new(outcome: worst(failing), figure: failing.size, lines: lines + failing.map { |f| "#{f['label']}: #{f['problem']}" },
               failing:, extra: { "duty_subjects" => subjects, "checked" => kycs.size, "document_input" => @check["document_input"] })
  end

  def owner_documents(kyc_ids)
    return {} if kyc_ids.empty?

    scope = Document.where(entity_id: @ctx.fund.entity_id, owner_type: "InvestorKyc", owner_id: kyc_ids)
    scope = mapping["tag"].present? ? scope.where("documents.tag_list LIKE ?", "%#{Document.sanitize_sql_like(mapping['tag'])}%") : scope.where(name: mapping["name"])
    scope.order(:id).pluck(:id, :owner_id).each_with_object({}) { |(id, owner_id), out| out[owner_id] = Doc.new(id:, owner_id:) }
  end

  # Investors linked when they share any owner name (transitively); only groups of two or more
  def group_by_common_owner(owners)
    parent = owners.keys.index_with { |k| k }
    find = ->(x) { parent[x] == x ? x : (parent[x] = find.call(parent[x])) }
    by_owner = Hash.new { |h, k| h[k] = [] }
    owners.each { |inv, names| names.each { |n| by_owner[n] << inv } }
    by_owner.each_value { |invs| invs.each_cons(2) { |a, b| parent[find.call(a)] = find.call(b) } }
    owners.keys.group_by { |k| find.call(k) }.values.select { |m| m.size > 1 }
  end

  def worst(failing)
    outcomes = failing.pluck("outcome")
    return "breach" if outcomes.include?("breach")
    return "warning" if outcomes.include?("warning")
    return "needs_review" if outcomes.include?("needs_review")

    "pass"
  end

  def summarise(checked, failing, earlier, without:)
    ok = checked - failing.size - without
    lines = ["#{ok} of #{checked} OK · #{failing.size} to look at · #{without} without a document · #{earlier} earlier not checked"]
    failing.first(ComplianceDocumentCheckQuery::MAX_LISTED).each { |f| lines << "#{f['label']} (#{f['date']}): #{f['problem']}" }
    Result.new(outcome: worst(failing), figure: failing.size, lines:, failing: failing.first(ComplianceDocumentCheckQuery::MAX_LISTED),
               extra: { "checked" => checked, "ok" => ok, "earlier" => earlier, "failing_count" => failing.size,
                        "document_input" => @check["document_input"] })
  end
end

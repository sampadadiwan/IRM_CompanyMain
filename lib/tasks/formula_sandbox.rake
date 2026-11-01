# C2 — audit every stored formula against the FormulaSandbox profiles (config/formula_sandbox.yml).
# docs/security/security_review_2026_10.md#c2--formula-engine-allowlist-checked-evaluation
#
#   bin/rails formula_sandbox:audit                 # dry run: report only, nothing is written
#   bin/rails formula_sandbox:audit EXECUTE=1       # also apply the one mechanical rewrite (below)
#   ENTITY_ID=451 bin/rails formula_sandbox:audit   # one firm only
#
# Parse only: no stored text is ever evaluated. The report lists every formula the profiles would
# reject, grouped entity -> site -> rule, plus what EXECUTE=1 would change.
#
# EXECUTE=1 applies only FormulaSandbox.rewrite_pins to fund formulas, the rewrite the design names for
# query roots filtered through the engine's own commitment (result-preserving, see rewrite_pins):
#   PortfolioInvestment.where(fund_id: capital_commitment.fund_id) -> where(fund_id: @fund.id)
# Before anything is written, every row it will change is copied to a JSONL backup
# (tmp/formula_sandbox_backup_<time>.jsonl: id, entity_id, fund_id, formula before and after).
namespace :formula_sandbox do
  desc "Report stored formulas the FormulaSandbox profiles would reject (EXECUTE=1 applies the mechanical pin rewrite)"
  task audit: :environment do
    execute = ENV["EXECUTE"] == "1"
    entity_id = ENV["ENTITY_ID"].presence&.to_i
    scoped = ->(relation) { entity_id ? relation.where(entity_id:) : relation }

    # offenders[entity_id][site][rule] = ["FundFormula#12", ...]
    offenders = Hash.new { |by_entity, entity| by_entity[entity] = Hash.new { |by_site, site| by_site[site] = Hash.new { |by_rule, rule| by_rule[rule] = [] } } }
    checked = Hash.new(0)
    rewrites = []

    record_offence = lambda do |entity, site, label, errors|
      errors.each { |rule| offenders[entity][site][rule] << label }
    end

    # 1. Fund formulas: each rule type's own profile and binding locals; never-evaluated types skipped
    scoped.call(FundFormula.all).select(:id, :entity_id, :fund_id, :rule_type, :formula).find_each do |fund_formula|
      next if fund_formula.formula.blank? || !FormulaSandbox.fund_formula_evaluated?(fund_formula.rule_type)

      profile = FormulaSandbox.fund_formula_profile(fund_formula.rule_type)
      locals = FormulaSandbox.fund_formula_locals(fund_formula.rule_type)
      checked["fund_formula"] += 1
      errors = FormulaSandbox.violations(fund_formula.formula, profile:, locals:)
      next if errors.empty?

      record_offence.call(fund_formula.entity_id, "fund_formula/#{profile}", "FundFormula##{fund_formula.id} (#{fund_formula.rule_type})", errors)

      # The mechanical rewrite, kept only when it changes the text and still parses
      rewritten = FormulaSandbox.rewrite_pins(fund_formula.formula, profile:)
      next if rewritten == fund_formula.formula || Prism.parse(rewritten).errors.any?

      remaining = FormulaSandbox.violations(rewritten, profile:, locals:)
      rewrites << { "id" => fund_formula.id, "entity_id" => fund_formula.entity_id, "fund_id" => fund_formula.fund_id,
                    "formula_before" => fund_formula.formula, "formula_after" => rewritten, "remaining" => remaining }
    end

    # 2. Call-fee formulas (notes of formula fees), with calculate_formula's locals
    scoped.call(CallFee.formulas).where.not(notes: [nil, ""]).select(:id, :entity_id, :notes).find_each do |call_fee|
      checked["call_fee"] += 1
      errors = FormulaSandbox.violations(call_fee.notes, profile: "call_fee", locals: CallFee::FORMULA_LOCALS)
      record_offence.call(call_fee.entity_id, "call_fee", "CallFee##{call_fee.id}", errors) if errors.any?
    end

    # 3. Calculation custom fields, with perform_custom_calculation's locals. A field has no entity_id
    #    of its own: the firm is its form type's
    fields = FormCustomField.joins(:form_type).where(field_type: "Calculation").where.not(meta_data: [nil, ""])
    fields = fields.where(form_types: { entity_id: }) if entity_id
    fields.select("form_custom_fields.id", "form_custom_fields.meta_data", "form_types.entity_id AS firm_id").find_each do |field|
      checked["form_custom_field"] += 1
      errors = FormulaSandbox.violations(field.meta_data, profile: "form_custom_field", locals: FormCustomField::CALCULATION_LOCALS)
      record_offence.call(field[:firm_id], "form_custom_field", "FormCustomField##{field.id}", errors) if errors.any?
    end

    # 4. The entity expense filter (none stored in production as of 2026-10-31)
    scoped.call(EntitySetting.where.not(portflio_expense_account_entry_filter: [nil, ""])).select(:id, :entity_id, :portflio_expense_account_entry_filter).find_each do |setting|
      checked["expense_filter"] += 1
      errors = FormulaSandbox.violations(setting.portflio_expense_account_entry_filter, profile: "expense_filter", locals: %i[expense_fields total])
      record_offence.call(setting.entity_id, "expense_filter", "EntitySetting##{setting.id}", errors) if errors.any?
    end

    # Report: entity -> site -> rule -> offenders
    puts "formula_sandbox:audit #{execute ? 'EXECUTE' : 'DRY RUN'}#{" entity #{entity_id}" if entity_id} — mode is #{FormulaSandbox.mode}"
    puts "checked: #{checked.map { |site, count| "#{site}=#{count}" }.join(' ')}"
    offenders.sort_by { |entity, _| entity.to_i }.each do |entity, sites|
      puts "\nentity #{entity}"
      sites.each do |site, rules|
        puts "  #{site}"
        rules.sort_by { |_, labels| -labels.size }.each do |rule, labels|
          puts "    #{rule} (#{labels.size}): #{labels.first(20).join(', ')}#{', …' if labels.size > 20}"
        end
      end
    end
    total = offenders.values.sum { |sites| sites.values.sum { |rules| rules.values.flatten.uniq.size } }
    puts "\nrejected formulas: #{total}"

    # What the mechanical rewrite would change
    fixed = rewrites.count { |rewrite| rewrite["remaining"].empty? }
    puts "mechanical pin rewrite: #{rewrites.size} fund formula(s) change, #{fixed} pass afterwards"
    rewrites.each do |rewrite|
      status = rewrite["remaining"].empty? ? "passes" : "still: #{rewrite['remaining'].join('; ')}"
      puts "  FundFormula##{rewrite['id']} (entity #{rewrite['entity_id']}): #{status}"
    end
    next puts("\nDry run — nothing written. Re-run with EXECUTE=1 to apply the rewrite.") unless execute
    next puts("\nNothing to rewrite.") if rewrites.empty?

    # EXECUTE=1: back up every row first, then write. update_columns on purpose: only the formula text
    # changes; validations, callbacks and the search index hook are not re-run for unrelated attributes.
    backup = Rails.root.join("tmp", "formula_sandbox_backup_#{Time.current.strftime('%Y%m%d%H%M%S')}.jsonl")
    File.open(backup, "w") { |file| rewrites.each { |rewrite| file.puts(rewrite.except("remaining").to_json) } }
    puts "\nbackup written: #{backup} (#{rewrites.size} rows)"

    written = 0
    FundFormula.transaction do
      rewrites.each do |rewrite|
        # Only a row still holding the text that was audited (an edit since then is left alone)
        written += FundFormula.where(id: rewrite["id"], formula: rewrite["formula_before"])
                              .update_all(formula: rewrite["formula_after"], updated_at: Time.current)
      end
    end
    puts "rewrote #{written} of #{rewrites.size} fund formula(s) (a row edited since the audit is skipped)"
  end
end

# ⑨ The daily digest for one entity: only when something changed or a duty is due/overdue (E45).
# Lines: new breaches, needs review, cleared items, attachments without classification, duties due within
# the reminder window and overdue, bulk duty lines (E108), one-off notes (versions, dropped overrides,
# reassignments — E2, E112, E113). Summary line as H29: "3 new breaches, 1 needs review, 1 duty due in 7 days".
class ComplianceDigest
  Digest = Struct.new(:summary, :lines, keyword_init: true) do
    delegate :empty?, to: :lines
  end

  def initialize(entity, as_of)
    @entity = entity
    @date = as_of
    @setup = ComplianceEntitySetup.for(entity)
    @since = @setup.last_digest_on || (@date - 1.day)
  end

  def call
    parts = []
    fund_pack_ids = FundCompliancePack.where(entity_id: @entity.id).pluck(:id)

    new_items = ComplianceRegisterItem.where(fund_compliance_pack_id: fund_pack_ids).where("opened_on > ? AND opened_on <= ?", @since, @date)
    parts << pluralize(new_items.count, "new breach", "new breaches") if new_items.exists?
    lines = new_items.includes(:fund).map { |i| "New breach: #{i.check_name} — #{i.fund.name}" }

    needs_review = latest_results(fund_pack_ids).select { |r| r.outcome == "needs_review" && r.compliance_run.run_date > @since }
    parts << "#{needs_review.size} needs review" if needs_review.any?

    cleared = ComplianceRegisterItem.where(fund_compliance_pack_id: fund_pack_ids).where("closed_on > ? AND closed_on <= ?", @since, @date)
    cleared.includes(:fund).find_each { |i| lines << "#{i.closed_label}: #{i.check_name} — #{i.fund.name}" }

    FundCompliancePack.active.where(entity_id: @entity.id, classification: [nil, ""]).includes(:fund, :compliance_pack).find_each do |fp|
      lines << "#{fp.pack_name}: no classification — no checks run (#{fp.fund.name})"
    end

    duty_lines(fund_pack_ids, parts, lines)
    Array(@setup.digest_notes).each { |n| lines << n }

    Digest.new(summary: if parts.any?
                          parts.join(", ")
                        else
                          (lines.any? ? "#{lines.size} update#{'s' if lines.size != 1}" : nil)
                        end, lines:)
  end

  private

  def duty_lines(fund_pack_ids, parts, lines)
    open_duties = ComplianceDuty.where(fund_compliance_pack_id: fund_pack_ids, done_on: nil)
    due_soon = open_duties.where(due_on: @date..(@date + ComplianceDuty::REMINDER_DAYS.days))
    if due_soon.exists?
      days = (due_soon.minimum(:due_on) - @date).to_i
      parts << "#{pluralize(due_soon.count, 'duty', 'duties')} due in #{days} day#{'s' if days != 1}"
    end
    overdue = open_duties.where(due_on: ...@date)
    lines << "#{pluralize(overdue.count, 'duty', 'duties')} overdue" if overdue.exists?

    # E108: bulk event duties in one line
    new_event = ComplianceDuty.where(fund_compliance_pack_id: fund_pack_ids, subject_type: "Investor")
                              .where("created_at > ?", @since.end_of_day)
    if new_event.exists?
      n = new_event.count
      lines << "#{n} new investor#{'s' if n != 1} — #{n} due-diligence dut#{n == 1 ? 'y' : 'ies'}"
    end
  end

  def latest_results(fund_pack_ids)
    ids = ComplianceResult.where(fund_compliance_pack_id: fund_pack_ids).group(:fund_compliance_pack_id, :check_key).maximum(:id).values
    ComplianceResult.where(id: ids).includes(:compliance_run).to_a
  end

  def pluralize(n, one, many)
    "#{n} #{n == 1 ? one : many}"
  end
end

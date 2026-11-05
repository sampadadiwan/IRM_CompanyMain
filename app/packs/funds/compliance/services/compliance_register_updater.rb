# ⑥ Turns one stored result into register changes:
#   breach → open an item (one per check per fund pack, R4/E31) or keep the open one current;
#            an Explained item reopens when the figure worsens beyond the approved one (E33, E34)
#   pass   → close the open item: "Cleared by data", "Pack corrected" (first result superseded, H57) or
#            "Record deleted" (the failing records/groups no longer exist, E125, E126)
#   warning / needs review / could not check → no change (E82: transition warnings open nothing)
# Worked examples H25, E31, E33, E34, E37, E40, E82, E83, H57, E126 — openspec/changes/fund-compliance-monitoring/business-rules.md
class ComplianceRegisterUpdater
  DEFAULT_TIME_TO_FIX = 30

  def self.call(result, check:, run_date:)
    new(result, check, run_date).call
  end

  def initialize(result, check, run_date)
    @result = result
    @check = check
    @date = run_date
  end

  def call
    item = ComplianceRegisterItem.open_items.find_by(fund_compliance_pack_id: @result.fund_compliance_pack_id, check_key: @result.check_key)
    case @result.outcome
    when "breach" then breach(item)
    when "pass" then close(item) if item
    end
  end

  private

  def breach(item)
    return open_item if item.nil?

    attrs = { last_result: @result }
    # E33: reopen an explained item when worse than when it was approved
    if item.status == "explained" && ComplianceCheckEvaluator.worse?(@result.figure, item.approved_figure, ComplianceCheckEvaluator.compare_direction(@check))
      attrs[:status] = "open"
      attrs[:reopened_worse] = true
    end
    item.update!(attrs)
    item
  end

  def open_item
    ttf = @check["time_to_fix_days"].nil? ? DEFAULT_TIME_TO_FIX : @check["time_to_fix_days"].to_i
    fp = @result.fund_compliance_pack
    ComplianceRegisterItem.create!(
      entity_id: @result.entity_id, fund_id: fp.fund_id, fund_compliance_pack: fp, check_key: @result.check_key,
      status: "open", opened_on: @date, fix_by: @date + ttf.days, first_result: @result, last_result: @result, open_key: "1"
    )
  rescue ActiveRecord::RecordNotUnique
    # A concurrent run opened it first — use that one
    ComplianceRegisterItem.open_items.find_by!(fund_compliance_pack_id: @result.fund_compliance_pack_id, check_key: @result.check_key)
  end

  def close(item)
    reason = if item.first_result&.superseded?
               "pack_corrected"
             elsif failing_rows_deleted?(item)
               "record_deleted"
             else
               "cleared"
             end
    item.close!(reason, on: @date, result: @result)
  end

  # E125/E126: the item cleared only because its failing records were soft-deleted
  def failing_rows_deleted?(item)
    w = item.last_result&.working_hash || {}
    fp = item.fund_compliance_pack
    if w["failing_records"].present?
      ids = w["failing_records"].pluck("id")
      model = ComplianceDataCatalog.model(@check["source"].presence || "portfolio_investments")
      return model.where(id: ids).none?
    end
    if w["failing_groups"].present?
      ids = w["failing_groups"].pluck("id")
      return CapitalCommitment.where(fund_id: fp.fund_id, investor_id: ids).none?
    end
    false
  end
end

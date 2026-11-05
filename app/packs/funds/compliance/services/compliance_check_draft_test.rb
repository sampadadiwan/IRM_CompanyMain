# ⑧ Test run of a drafted check on one fund, inside CapHive (no AI — E63): evaluates only the drafted
# check against today's data with the pack's merged definition and returns the working to show.
# Nothing is stored except the result on the draft itself (a preview — R37).
# Worked examples H38, E58, E59 — openspec/changes/fund-compliance-monitoring/business-rules.md
class ComplianceCheckDraftTest
  def self.call(draft:, fund:)
    new(draft, fund).call
  end

  def initialize(draft, fund)
    @draft = draft
    @fund = fund
  end

  def call
    base = { "fund_id" => @fund.id, "fund_name" => @fund.name, "tested_on" => Time.zone.today.iso8601 }
    # A duty has no figure: the test run only confirms how it will be listed (H39)
    return base.merge("outcome" => "duty", "lines" => ["Manual duty — listed under Duties; nothing to compute"]) if @draft.duty?

    version = @draft.preview_version
    check = version.check(@draft.drafted_key)
    setup = ComplianceEntitySetup.find_by(entity_id: @fund.entity_id) || ComplianceEntitySetup.new(entity_id: @fund.entity_id)
    context = ComplianceMeasureQuery.context(fund: @fund, as_of: Time.zone.today, setup:, version:)
    out = ComplianceCheckEvaluator.call(check, context:)
    base.merge("outcome" => out.outcome, "lines" => Array(out.working["lines"]).compact, "message" => out.working["message"])
  end
end

# ⑥ What the fund's Compliance tab shows: latest result per check grouped by pack, run health,
# attachments without classification, version banners and open duties.
class ComplianceDashboard
  attr_reader :fund, :fund_packs

  def initialize(fund, user)
    @fund = fund
    @user = user
    @fund_packs = FundCompliancePack.active.where(fund_id: fund.id).includes(:compliance_pack, :compliance_pack_version).order(:id).to_a
  end

  # {fund_pack => [results]} — the latest result per check (highest id, R42)
  def latest_results
    @latest_results ||= begin
      ids = ComplianceResult.where(fund_compliance_pack_id: @fund_packs.map(&:id), superseded_reason: nil)
                            .group(:fund_compliance_pack_id, :check_key).maximum(:id).values
      ComplianceResult.where(id: ids).includes(:compliance_run).order(:id).to_a.group_by(&:fund_compliance_pack_id)
    end
  end

  def counts
    all = latest_results.values.flatten
    %w[breach needs_review warning could_not_check pass].index_with { |o| all.count { |r| r.outcome == o } }
  end

  def last_success
    ComplianceRun.last_success_for(@fund)
  end

  def stale?
    ComplianceRun.stale?(@fund)
  end

  # E9: attached packs with no classification
  def unclassified
    @fund_packs.select { |fp| fp.classification.blank? }
  end

  # H48 / E88: published versions not yet in effect for this fund
  def upcoming_versions
    @fund_packs.flat_map do |fp|
      cur = fp.compliance_pack_version&.version_no || 0
      fp.compliance_pack.published_versions.select { |v| v.version_no > cur && v.effective_from && v.effective_from > fp.compliance_pack.regime_date }
        .map { |v| [fp, v] }
    end
  end

  # R22 / E132: days without a nightly run between the first and last run shown as gaps; never backfilled
  def run_gaps
    dates = ComplianceRun.where(fund_id: @fund.id, trigger: "nightly").distinct.pluck(:run_date).sort
    return [] if dates.size < 2

    (dates.first..dates.last).to_a - dates
  end

  def duties
    ComplianceDuty.not_done.where(fund_compliance_pack_id: @fund_packs.map(&:id)).order(:due_on).limit(20)
  end
end

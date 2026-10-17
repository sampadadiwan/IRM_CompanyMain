class FundRatioPolicy < FundBasePolicy
  class Scope < FundBasePolicy::Scope
    def resolve
      if user.curr_role == "investor"
        rel = super.joins(:fund).where("funds.features & ? > 0", Fund.features.maps[:show_fund_ratios])
        # B4-1: fund-level rows (no folio), plus the rows of folios this user can see. The fund's
        # access right alone used to return every investor's per-folio ratios (IRR, MOIC).
        # Worked example B4-1 — openspec/changes/fix-tenant-isolation-batch2/report.md#verification
        rel.where(capital_commitment_id: nil)
           .or(rel.where(capital_commitment_id: Pundit.policy_scope!(user, CapitalCommitment).select(:id)))
      else
        super
      end
    end
  end

  def index?
    user.enable_funds
  end

  def bulk_actions?
    index?
  end

  def show?
    permissioned_employee? ||
      # fund_id is nil for cross-fund/cross-portfolio rows — skip investor check.
      (record.fund.present? && record.fund.features.show_fund_ratios? && FundPolicy.new(user, record.fund).permissioned_investor? &&
       # B4-1: a folio's ratio also needs that folio (commitment) to be visible to this user.
       (record.capital_commitment_id.nil? || CapitalCommitmentPolicy.new(user, record.capital_commitment).show?))
  end

  def create?
    false
  end

  def new?
    create?
  end

  def update?
    (record.fund.present? && FundPolicy.new(user, record.fund).create? && record.import_upload_id.present?) || support?
  end

  def edit?
    update?
  end

  def destroy?
    record.fund.present? && FundPolicy.new(user, record.fund).create?
  end
end

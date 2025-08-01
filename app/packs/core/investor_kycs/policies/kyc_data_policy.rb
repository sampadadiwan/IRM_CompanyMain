class KycDataPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      # Get all InvestorKycs the user is allowed to access
      allowed_investor_kyc_ids = InvestorKycPolicy::Scope.new(user, InvestorKyc).resolve.select(:id)
      scope.where(investor_kyc_id: allowed_investor_kyc_ids)
    end
  end

  def index?
    user.enable_kycs
  end

  def show?
    Pundit.policy(user, record.investor_kyc).show?
  end

  def create?
    Pundit.policy(user, record.investor_kyc).create?
  end

  def refresh?
    index?
  end

  def compare_ckyc_kra?
    index?
  end

  def fetch_ckyc_data?
    index?
  end

  def send_ckyc_otp?
    index?
  end

  def download_ckyc_with_otp?
    index?
  end

  def new?
    create?
  end

  def update?
    create?
  end

  def edit?
    create?
  end

  def destroy?
    index? && record.status&.downcase != "success"
  end
end

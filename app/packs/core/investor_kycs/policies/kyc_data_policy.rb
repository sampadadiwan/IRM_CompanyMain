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

  # The side-by-side CKYC/KRA screen shows the PAN and addresses of the KYC it is built on, so it
  # opens for exactly the users who can open that KYC (parent-policy delegation). The controller
  # authorizes a KycData built on the KYC, since the screen is reached by investor_kyc_id.
  # Worked examples C7-1, C7-5, C7-H — features/security/kyc_data_access.feature
  def compare_ckyc_kra?
    Pundit.policy(user, record.investor_kyc).show?
  end

  # Re-fetching, sending an OTP and downloading with it each make a paid CKYC/KRA call that writes
  # this record, so they need the same right as editing it: create rights on its KYC (the KYC's own
  # firm staff with investor_kyc_create, or the investor on their own KYC). These were index?, i.e.
  # "KYCs are switched on for me", so any firm's user could act on any firm's data by id.
  # Worked examples C7-2, C7-3, C7-H, C7-H2 — features/security/kyc_data_access.feature
  def refresh?
    update?
  end

  def send_ckyc_otp?
    update?
  end

  def download_ckyc_with_otp?
    update?
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

  # Deleting needs the edit right on the record's KYC, and a successful fetch is kept as the record
  # of what CKYC/KRA returned.
  # Worked examples C7-4, C7-X — features/security/kyc_data_access.feature
  def destroy?
    update? && record.status&.downcase != "success"
  end
end

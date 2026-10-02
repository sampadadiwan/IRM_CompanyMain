# Readiness warnings for the investor KYC journey panel: things that won't stop a task from passing
# but are worth fixing before the KYC is verified. Shown until it is verified.
# Worked examples E22 — openspec/changes/investor-kyc-journey/design.md#worked-examples
module WorkflowChecks
  class InvestorKycWarnings
    def initialize(kyc)
      @kyc = kyc
    end

    # Array of warning strings (possibly empty)
    def to_a
      return [] if @kyc.submission_status == "verified"

      [pan_warning, bank_warning, users_warning, expiry_warning].compact
    end

    private

    # VerifyPanJob / VerifyBankJob leave a status message when verification did not succeed
    def pan_warning
      "PAN verification failed" if @kyc.pan_verification_status.present? && !@kyc.pan_verified
    end

    def bank_warning
      "Bank account verification failed" if @kyc.bank_verification_status.present? && !@kyc.bank_verified
    end

    def users_warning
      "The investor has no users to email" unless @kyc.investor&.approved_users&.exists?
    end

    def expiry_warning
      "The KYC expired on #{I18n.l(@kyc.expiry_date)}" if @kyc.expired?
    end
  end
end

class IndividualKyc < InvestorKyc
  def self.policy_class
    InvestorKycPolicy
  end
end

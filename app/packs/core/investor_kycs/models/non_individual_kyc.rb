class NonIndividualKyc < InvestorKyc
  def self.policy_class
    InvestorKycPolicy
  end
end

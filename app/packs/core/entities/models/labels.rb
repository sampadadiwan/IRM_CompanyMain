class Labels
  LABEL_MAP = {
    SEBI: {
      'Tax ID': "PAN / Tax ID",
      'Bank Routing Number': "IFSC Code",
      'Address Proof Documents': "Any one of: Aadhar Card, Voter ID, Passport, Driving License, Other Govt ID"
    },
    DEFAULT: {
      'Address Proof Documents': "Please attach a valid government issued address proof."
    }
  }.freeze

  def self.get(reg_env, key)
    map = LABEL_MAP[reg_env.to_sym] || LABEL_MAP[:DEFAULT]
    map[key.to_sym] || key
  end
end

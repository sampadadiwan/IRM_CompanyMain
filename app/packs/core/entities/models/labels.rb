class Labels
  LABEL_MAP = {
    SEBI: {
      'Tax ID': "PAN",
      'Bank Routing Number': "IFSC Code",
      'Address Proof Documents': "PAN, Adhaar Card, Voter ID, Passport, Driving License"
    },
    DEFAULT: {
      'Address Proof Documents': "Any valid address proof"
    }
  }.freeze

  def self.get(reg_env, key)
    map = LABEL_MAP[reg_env.to_sym] || LABEL_MAP[:DEFAULT]
    map[key.to_sym] || key
  end
end

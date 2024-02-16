class Report < ApplicationRecord
  belongs_to :entity, optional: true
  belongs_to :user

  validates :name, :curr_role, presence: true

  def self.reports_for
    { 'Account Entries': "/account_entries?filter=true",
      Commitments: "/capital_commitments?filter=true",
      Remittances: "/capital_remittances?filter=true",
      Kpis: "/kpis?filter=true",
      'Fund Units': "/fund_units?filter=true",
      KYCs: "/investor_kycs?filter=true" }
  end

  def to_s
    name
  end
end

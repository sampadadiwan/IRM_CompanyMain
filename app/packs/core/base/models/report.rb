class Report < ApplicationRecord
  belongs_to :entity, optional: true
  belongs_to :user

  validates :name, presence: true

  def self.reports_for
    { 'Account Entries': "/account_entries?filter=true",
      'Capital Commitments': "/capital_commitments?filter=true",
      'Capital Remittances': "/capital_remittances?filter=true",
      'Fund Units': "/fund_units?filter=true",
      KYCs: "/investor_kycs?filter=true" }
  end
end

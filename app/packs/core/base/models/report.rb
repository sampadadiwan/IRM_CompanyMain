class Report < ApplicationRecord
  belongs_to :entity, optional: true
  belongs_to :user

  def self.reports_for
    { 'Capital Commitments': "/capital_commitments?filter=true",
      'Capital Remittances': "/capital_remittances?filter=true",
      'Account Entries': "/account_entries?filter=true" }
  end
end

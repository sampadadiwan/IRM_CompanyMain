class InvestorNotice < ApplicationRecord
  belongs_to :entity
  belongs_to :owner, optional: true, polymorphic: true
  has_many :investor_notice_entries, dependent: :destroy

  has_rich_text :details
end

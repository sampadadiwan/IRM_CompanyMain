class InvestorNotice < ApplicationRecord
  belongs_to :entity
  belongs_to :owner, optional: true, polymorphic: true

  has_rich_text :details
end

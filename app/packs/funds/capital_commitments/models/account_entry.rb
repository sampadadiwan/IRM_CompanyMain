class AccountEntry < ApplicationRecord
  belongs_to :capital_commitment, optional: true
  belongs_to :entity
  belongs_to :fund
  belongs_to :investor, optional: true

  belongs_to :form_type, optional: true
  serialize :properties, Hash

  monetize :amount_cents, with_currency: ->(i) { i.fund.currency }

  validates :name, :reporting_date, :entry_type, presence: true
end

class Fee < ApplicationRecord
  belongs_to :owner, polymorphic: true, touch: true
  belongs_to :entity

  validates :amount, :amount_label, :bank_account_number, :ifsc_code, presence: true

  monetize :amount_cents,
           with_currency: ->(f) { f.owner.respond_to?(:currency) ? f.owner.currency : f.entity.currency }
end

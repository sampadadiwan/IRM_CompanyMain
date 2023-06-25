class Fee < ApplicationRecord
  belongs_to :owner, polymorphic: true, touch: true
  belongs_to :entity

  validates :amount, :amount_label, :advisor_name, presence: true
  validates :advisor_name, length: { maximum: 30 }
  validates :amount_label, length: { maximum: 10 }
  validates :bank_account_number, length: { maximum: 40 }
  validates :ifsc_code, length: { maximum: 20 }

  monetize :amount_cents,
           with_currency: ->(f) { f.owner.respond_to?(:currency) ? f.owner.currency : f.entity.currency }
end

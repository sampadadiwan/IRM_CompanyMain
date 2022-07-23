class ExpressionOfInterest < ApplicationRecord
  belongs_to :entity
  belongs_to :user
  belongs_to :eoi_entity, class_name: "Entity"
  belongs_to :investment_opportunity

  has_many :documents, as: :owner, dependent: :destroy
  accepts_nested_attributes_for :documents, allow_destroy: true

  monetize :amount_cents, :allocation_amount_cents,
           with_currency: ->(s) { s.investment_opportunity.currency }
end

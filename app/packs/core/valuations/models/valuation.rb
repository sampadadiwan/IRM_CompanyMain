class Valuation < ApplicationRecord
  include Trackable
  include WithCustomField

  belongs_to :entity
  belongs_to :owner, polymorphic: true, optional: true, touch: true
  validates :category, length: { maximum: 10 }
  validates :sub_category, length: { maximum: 100 }

  include FileUploader::Attachment(:report)

  monetize :valuation_cents, :per_share_value_cents,
           with_currency: lambda { |s|
                            if s.owner && s.owner.respond_to?(:currency) && s.owner.currency.present?
                              s.owner.currency
                            else
                              s.entity.currency
                            end
                          }

  after_save :update_entity
  def update_entity
    if owner_type.blank?
      entity.per_share_value_cents = per_share_value_cents
      entity.save
    end
  end

  # Ensure callback to the owner
  after_commit :update_owner
  def update_owner
    owner.valuation_updated(self) if owner.respond_to?(:valuation_updated)
  end

  def instrument_type
    "#{category} : #{sub_category}"
  end
end

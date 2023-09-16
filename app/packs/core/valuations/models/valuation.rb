class Valuation < ApplicationRecord
  include Trackable
  include WithCustomField

  belongs_to :entity
  belongs_to :owner, polymorphic: true, optional: true, touch: true
  validates :category, length: { maximum: 10 }
  validates :sub_category, length: { maximum: 100 }
  validates :category, :sub_category, presence: true, if: proc { |v| v.owner_type == "Investor" }
  validates :valuation_cents, :per_share_value_cents, numericality: { greater_than: 0 }

  # Ensure callback to the owner
  after_save :update_owner
  after_save :update_entity

  include FileUploader::Attachment(:report)

  monetize :valuation_cents, :per_share_value_cents,
           with_currency: lambda { |s|
                            if s.owner && s.owner.respond_to?(:currency) && s.owner.currency.present?
                              s.owner.currency
                            else
                              s.entity.currency
                            end
                          }

  def update_entity
    if owner_type.blank?
      entity.per_share_value_cents = per_share_value_cents
      entity.save
    end
  end

  def update_owner
    if (saved_change_to_valuation_cents? ||
       saved_change_to_per_share_value_cents? ||
       saved_change_to_valuation_date?) && owner.respond_to?(:valuation_updated)
      owner.valuation_updated(self)
    end
  end

  def instrument_type
    "#{category} : #{sub_category}"
  end
end

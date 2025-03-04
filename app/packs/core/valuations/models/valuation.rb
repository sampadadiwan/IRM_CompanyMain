class Valuation < ApplicationRecord
  include Trackable.new
  include WithCustomField
  include WithExchangeRate

  belongs_to :entity
  belongs_to :owner, polymorphic: true, optional: true, touch: true
  belongs_to :investment_instrument # , optional: true

  validates :per_share_value, numericality: { greater_than_or_equal_to: 0 }
  validates :valuation_date, presence: true
  validates_uniqueness_of :valuation_date, scope: %i[investment_instrument_id entity_id owner_id owner_type]

  # Ensure callback to the owner
  after_save :update_owner
  after_save :update_entity

  include FileUploader::Attachment(:report)

  monetize :valuation_cents, :per_share_value_cents,
           with_currency: ->(s) { s.currency }

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

  def to_s
    "#{entity} - #{valuation_date}"
  end

  def to_extended_s
    "#{owner} - #{investment_instrument} - #{valuation_date}"
  end

  def currency
    if investment_instrument
      investment_instrument.currency
    elsif owner.respond_to?(:currency) && owner.currency.present?
      owner.currency
    else
      entity.currency
    end
  end

  def per_share_value_in(to_currency, as_of)
    convert_currency(currency, to_currency, per_share_value_cents, as_of)
  end
end

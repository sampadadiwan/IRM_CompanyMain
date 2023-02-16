class Valuation < ApplicationRecord
  include Trackable
  include WithCustomField

  belongs_to :entity
  belongs_to :owner, polymorphic: true, optional: true, touch: true
  include FileUploader::Attachment(:report)

  monetize :valuation_cents, :per_share_value_cents, :portfolio_inv_cost_cents, :portfolio_fmv_valuation_cents, :management_opex_cost_cents, :collection_last_quarter_cents,
           with_currency: lambda { |s|
                            if s.owner && s.owner.respond_to?(:currency) && s.owner.currency.present?
                              s.owner.currency
                            else
                              s.entity.currency
                            end
                          }

  before_save :update_valuation
  def update_valuation
    custom_fields_total_cents = 0
    if entity.entity_setting.valuation_math.present?
      entity.entity_setting.valuation_math.split(",").each do |cf|
        custom_fields_total_cents += properties[cf].to_d * 100 if properties[cf].present?
      end
    end
    self.valuation_cents = portfolio_fmv_valuation_cents + custom_fields_total_cents
  end

  after_save :update_entity
  def update_entity
    entity.per_share_value_cents = per_share_value_cents
    entity.save
  end

  # Ensure callback to the owner
  after_commit :update_owner
  def update_owner
    owner.valuation_updated(self) if owner.respond_to?(:valuation_updated)
  end
end

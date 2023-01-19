class Valuation < ApplicationRecord
  include Trackable

  belongs_to :entity
  belongs_to :owner, polymorphic: true, optional: true, touch: true
  include FileUploader::Attachment(:report)

  # Customize form
  belongs_to :form_type, optional: true
  serialize :properties, Hash

  monetize :valuation_cents, :per_share_value_cents, :portfolio_inv_cost_cents, :portfolio_fmv_valuation_cents, :management_opex_cost_cents,
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
    if entity.valuation_math.present?
      entity.valuation_math.split(",").each do |cf|
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
end

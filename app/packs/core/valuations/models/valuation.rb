# == Schema Information
#
# Table name: valuations
#
#  id                        :integer          not null, primary key
#  entity_id                 :integer          not null
#  valuation_date            :date
#  pre_money_valuation_cents :decimal(20, 2)   default("0.00")
#  per_share_value_cents     :decimal(15, 2)   default("0.00")
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  form_type_id              :integer
#

class Valuation < ApplicationRecord
  belongs_to :entity
  belongs_to :owner, polymorphic: true, optional: true, touch: true

  include FileUploader::Attachment(:report)

  # Customize form
  belongs_to :form_type, optional: true
  serialize :properties, Hash

  monetize :pre_money_valuation_cents, :per_share_value_cents,
           with_currency: lambda { |s|
                            if s.owner && s.owner.respond_to?(:currency) && s.owner.currency.present?
                              s.owner.currency
                            else
                              s.entity.currency
                            end
                          }

  after_save :update_entity
  def update_entity
    entity.per_share_value_cents = per_share_value_cents
    entity.save
  end
end

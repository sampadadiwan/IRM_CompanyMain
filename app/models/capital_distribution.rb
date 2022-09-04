class CapitalDistribution < ApplicationRecord
  include ActivityTrackable
  tracked owner: proc { |_controller, model| model.fund }, entity_id: proc { |_controller, model| model.entity_id }

  belongs_to :fund
  belongs_to :entity
  belongs_to :form_type, optional: true

  monetize :carry_cents, :gross_amount_cents, with_currency: ->(i) { i.entity.currency }

  def self.for_investor(user)
    CapitalDistribution
      # Ensure the access rghts for Document
      .joins(fund: :access_rights)
      .merge(AccessRight.access_filter)
      .joins(entity: :investors)
      # Ensure that the user is an investor and tis investor has been given access rights
      # .where("entities.id=?", entity.id)
      .where("investors.investor_entity_id=?", user.entity_id)
      # Ensure this user has investor access
      .joins(entity: :investor_accesses)
      .merge(InvestorAccess.approved_for_user(user))
  end
end

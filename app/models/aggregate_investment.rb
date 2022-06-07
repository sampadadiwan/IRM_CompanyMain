# == Schema Information
#
# Table name: aggregate_investments
#
#  id                      :integer          not null, primary key
#  entity_id               :integer          not null
#  shareholder             :string(255)
#  investor_id             :integer          not null
#  equity                  :integer          default("0")
#  preferred               :integer          default("0")
#  options                 :integer          default("0")
#  percentage              :decimal(5, 2)    default("0.00")
#  full_diluted_percentage :decimal(5, 2)    default("0.00")
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  scenario_id             :integer          not null
#

class AggregateInvestment < ApplicationRecord
  audited

  belongs_to :entity

  has_many :investments, dependent: :destroy

  belongs_to :investor
  delegate :investor_name, to: :investor

  def self.for_investor(current_user, entity)
    investments = entity.aggregate_investments
                        # Ensure the access rights for Investment
                        .joins(entity: %i[investors access_rights])
                        .merge(AccessRight.access_filter)
                        # Ensure that the user is an investor and tis investor has been given access rights
                        .where("entities.id=?", entity.id)
                        .where("investors.investor_entity_id=?", current_user.entity_id)
                        # Ensure this user has investor access
                        .joins(entity: :investor_accesses)
                        .merge(InvestorAccess.approved_for_user(current_user))

    # return investments if investments.blank?

    # Is this user from an investor
    investor = Investor.for(current_user, entity).first

    # Get the investor access for this user and this entity
    access_right = AccessRight.investments.investor_access(investor).last
    return Investment.none if access_right.nil?

    Rails.logger.debug access_right.to_json

    case access_right.metadata
    when AccessRight::ALL
      # Do nothing - we got all the investments
      logger.debug "Access to investor #{current_user.email} to ALL Entity #{entity.id} investments"
    when AccessRight::SELF
      # Got all the investments for this investor
      logger.debug "Access to investor #{current_user.email} to SELF Entity #{entity.id} investments"
      investments = investments.where(investor_id: investor.id)
    end

    investments
  end

  def total_equity
    equity + preferred
  end

  def fully_diluted
    equity + preferred + options
  end
end

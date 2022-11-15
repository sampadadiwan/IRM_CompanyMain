module FundScopes
  extend ActiveSupport::Concern

  included do
    scope :for_employee, lambda { |user|
      joins(fund: :access_rights)
        .where("funds.entity_id=? and access_rights.user_id=?", user.entity_id, user.id)
        .includes(fund: :access_rights)
    }

    scope :for_investor, lambda { |user|
      if %w[CapitalCall CapitalDistribution].include?(name)
        # These dont have a direct investor reln, so go through entity
        joins(fund: :access_rights)
          .merge(AccessRight.access_filter)
          .joins(entity: :investors)
          # Ensure that the user is an investor and this investor
          .where("investors.investor_entity_id=?", user.entity_id)
          # Ensure this user has investor access
          .joins(entity: :investor_accesses)
          .merge(InvestorAccess.approved_for_user(user))
      elsif %w[CapitalCommitment CapitalDistributionPayment CapitalRemittance].include?(name)
        # These have a direct investor reln
        joins(:investor, fund: :access_rights)
          .merge(AccessRight.access_filter)
          # Ensure that the user is an investor and this investor
          .where("investors.investor_entity_id=?", user.entity_id)
          # Ensure this user has investor access
          .joins(entity: :investor_accesses)
          .merge(InvestorAccess.approved_for_user(user))
      end
    }

    scope :for_advisor, lambda { |user|
      # Ensure the access rghts for Document
      joins(fund: :access_rights).merge(AccessRight.access_filter)
                                 .where("access_rights.metadata=?", "Advisor").joins(entity: :investors)
                                 .where("investors.investor_entity_id=?", user.entity_id)
                                 .includes(fund: :access_rights)
    }
  end
end

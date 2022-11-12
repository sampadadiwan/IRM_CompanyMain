module FundScopes
  extend ActiveSupport::Concern

  included do
    scope :for_employee, lambda { |user|
      joins(fund: :access_rights).where("funds.entity_id=? and access_rights.user_id=?", user.entity_id, user.id)
    }

    scope :for_investor, lambda { |user|
      joins(fund: :access_rights)
        .merge(AccessRight.access_filter)
        .joins(entity: :investors)
        # Ensure that the user is an investor and tis investor has been given access rights
        # .where("entities.id=?", entity.id)
        .where("investors.investor_entity_id=?", user.entity_id)
        # Ensure this user has investor access
        .joins(entity: :investor_accesses)
        .merge(InvestorAccess.approved_for_user(user))
    }

    scope :for_advisor, lambda { |user|
      # Ensure the access rghts for Document
      joins(fund: :access_rights).merge(AccessRight.access_filter)
                                 .where("access_rights.metadata=?", "Advisor").joins(entity: :investors)
                                 .where("investors.investor_entity_id=?", user.entity_id)
    }
  end
end

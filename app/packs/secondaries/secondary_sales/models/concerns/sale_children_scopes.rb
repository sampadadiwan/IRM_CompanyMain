module SaleChildrenScopes
  extend ActiveSupport::Concern

  included do
    scope :for_employee, lambda { |user|
      joins(secondary_sale: :access_rights)
        .where("secondary_sales.entity_id=? and access_rights.user_id=?", user.entity_id, user.id)
    }

    scope :for_advisor, lambda { |user|
      joins(secondary_sale: :access_rights).merge(AccessRight.access_filter)
                                           .where("access_rights.metadata=?", "Advisor").joins(entity: :investors)
                                           .where("investors.investor_entity_id=?", user.entity_id)
    }

    scope :for_investor, lambda { |user|
      joins(secondary_sale: :access_rights)
        .merge(AccessRight.access_filter)
        .joins(entity: :investors)
        # Ensure that the user is an investor and tis investor has been given access rights
        .where("investors.investor_entity_id=?", user.entity_id)
        # Ensure this user has investor access
        .joins(entity: :investor_accesses)
        .merge(InvestorAccess.approved_for_user(user))
        .distinct
    }
  end
end

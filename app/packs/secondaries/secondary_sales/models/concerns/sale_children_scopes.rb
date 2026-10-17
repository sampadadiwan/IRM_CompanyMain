module SaleChildrenScopes
  extend ActiveSupport::Concern

  included do
    scope :for_employee, lambda { |user|
      joins(secondary_sale: :access_rights)
        .where("secondary_sales.entity_id=? and access_rights.user_id=?", user.entity_id, user.id)
    }

    scope :for_investor, lambda { |user|
      joins(secondary_sale: :access_rights)
        .merge(AccessRight.investor_list_filter(user)) # B3-3: personal grants only for a switched advisor
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

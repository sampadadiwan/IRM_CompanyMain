module DocumentScope
  extend ActiveSupport::Concern

  included do
    scope :for_investor, lambda { |user, entity_id|
      joins(:access_rights)
        .merge(AccessRight.access_filter(user))
        .joins(entity: :investors)
        # Ensure that the user is an investor and tis investor has been given access rights
        .where("entities.id=?", entity_id)
        .where("investors.investor_entity_id=?", user.entity_id)
        # Ensure this user has investor access
        .joins(entity: :investor_accesses)
        .merge(InvestorAccess.approved_for_user(user))
    }

    scope :entity_documents, lambda { |user, entity_id|
      if user.entity_id == entity_id
        where(entity_id:)
      else
        for_investor(user, entity_id)
      end
    }

    scope :owner_documents, lambda { |owner|
      where(owner_id: owner.id, owner_type: owner.class.name)
    }

    scope :templates, -> { where(template: true) }
    scope :not_templates, -> { where(template: false) }
  end
end

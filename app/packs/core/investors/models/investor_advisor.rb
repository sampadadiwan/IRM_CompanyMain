# This is a very important model and indicates that an entity is willing to allow the user
# (who is from another advisory company), advisor access to this company. This essentially allows the user to switch
# his entity id to this entity_id and thus gain access to funds, deals, etc which are permissioned

# Workflow
# 1. Entity makes a user an investor advisor in ones own firm
# 2. Entity can grant access to specific funds, deals etc to this investor advisor
# 3. The advisor can login and choose to switch to become an advisor for this entity (This essentially involves switching his entity_id to this entity_id)
# 4. Then he becomes like an employee whose access is controlled via access rights

class InvestorAdvisor < ApplicationRecord
  include UserEnabled

  belongs_to :entity
  belongs_to :user

  before_validation :ensure_user
  validates_uniqueness_of :email, scope: :entity_id

  def ensure_user
    self.user = User.find_by(email:)

    errors.add(:email, "No existing user found in the system. Advisor has not been setup.") unless user

    errors.add(:email, "User has not been setup as an investor advisor.") if user && !user.has_cached_role?(:investor_advisor)
  end

  def switch(user)
    user.entity_id = entity_id
    user.investor_advisor_id = id
    user.entity_type = user.entity.entity_type
    case user.entity_type
    when "Investor", "Investor Advisor"
      user.curr_role = :investor
    when "Company"
      user.curr_role = :employee
    end
    user.save
  end

  def self.revert(user)
    user.entity_id = user.advisor_entity_id
    user.investor_advisor_id = nil
    user.save
  end

  after_destroy :remove_access_rights
  def remove_access_rights
    AccessRight.where(entity_id:, user_id:).each(&:destroy)
    InvestorAccess.where(investor_entity_id: entity_id, email:).delete_all
  end
end

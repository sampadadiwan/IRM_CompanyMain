class FolderPolicy < ApplicationPolicy
  include WorkflowablePolicyMethods # journey?, assign_workflow?

  def index?
    true
  end

  def data_rooms?
    true
  end

  def show?
    if user.investor_advisor?
      belongs_to_entity?(user, record) && record.owner && Pundit.policy(user, record.owner).show?
    else
      belongs_to_entity?(user, record)
    end
  end

  def download?
    create? && user.has_cached_role?(:company_admin)
  end

  def create?
    # D: the parent is in one of the user's firms (funds_api_security_policy_plan.md)
    belongs_to_entity?(user, record) && parent_in_users_firms?(record.parent)
  end

  def new?
    create?
  end

  def update?
    (create? || support?) && !record.system?
  end

  def generate_report?
    update? && user.enable_user_llm_chat
  end

  def edit?
    update?
  end

  def destroy?
    false
  end

  def send_for_esign?
    user.entity_id == record.entity_id
  end
end

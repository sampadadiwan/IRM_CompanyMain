class PermissionPolicy < ApplicationPolicy
  def index?
    true
  end

  # M17 — a grant is visible to the user who made it, or to anyone who may change the record it is on
  # (M17-2, M17-H). Worked examples M17-1, M17-2, M17-H — docs/security/security_review_2026_10.md#core--misc--medium-and-low
  def show?
    belongs_to_entity?(user, record) && (record.granted_by_id == user.id || owner_updatable?)
  end

  # M17 — a Permission hands out read / write on its owner (DocumentPolicy#update? honours
  # allow_external?(:write)), so only someone who may already change the owner may grant on it;
  # otherwise any employee could grant themselves write on a document they can only read (M17-1).
  def create?
    # 1. The grant and its owner are in the user's firms (D, funds_api_security_policy_plan.md)
    return false unless belongs_to_entity?(user, record) && parent_in_users_firms?(record.owner)

    # 2. And the user may change the owner (M17-1, M17-H)
    owner_updatable?
  end

  # The blank form from the Permissions list has no owner yet: it still opens for the user's firm, and
  # the owner is checked when it is created (unchanged for the blank form)
  def new?
    record.owner.nil? ? belongs_to_entity?(user, record) : create?
  end

  def update?
    create?
  end

  def edit?
    create?
  end

  def destroy?
    create?
  end

  private

  # The grant's owner exists and its own policy lets the user update it
  def owner_updatable?
    record.owner.present? && (owner_policy&.update? || false)
  end
end

class IncomingEmailPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  def index?
    user.has_cached_role?(:company_admin) || super_user?
  end

  def show?
    belongs_to_entity?(user, record)
  end

  # M22 — a filed email is attached to its owner's record, so it must be in the user's firms, its owner
  # too, and the user must be allowed to update that owner (filing against a record changes it). An
  # email without an owner needs only the firm check. SendGrid and the mail add-ins don't come here.
  # Worked examples M22-1, M22-2, M22-H — docs/security/security_review_2026_10.md#core--misc--medium-and-low
  def create?
    # 1. The email and its owner are the user's firms' (M22-1)
    return false unless belongs_to_entity?(user, record) && parent_in_users_firms?(record.owner)
    # 2. No owner: nothing more to check
    return true if record.owner.nil?

    # 3. The user may update the owner (M22-H)
    owner_policy&.update? || false
  end

  def new?
    create?
  end

  def update?
    belongs_to_entity?(user, record)
  end

  def edit?
    update?
  end

  def destroy?
    update? || support?
  end
end

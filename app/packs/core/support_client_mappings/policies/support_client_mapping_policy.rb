class SupportClientMappingPolicy < ApplicationPolicy
  # Security fix (Finding 4): switch? intentionally does NOT delegate to show? (which passes
  # for super_user?). Allowing super users to call switch would let them silently change any
  # support user's entity_id and grant them :company_admin without that user initiating or
  # consenting — effectively unauthorized account manipulation. The controller's switch action
  # calls SupportClientMapping#switch which operates on mapping.user (not current_user), so a
  # super user triggering switch would modify a third party's account, not their own.
  # Only the mapped user themselves may initiate a context switch.
  def switch?
    record.user_id == user.id && record.enabled? && record.status != 'Switched' && record.entity.enable_support
  end

  # Security fix (Finding 4): Same rationale as switch? — only the mapped user may revert
  # their own context. Super users retain full CRUD access (create?, update?, destroy?) to
  # manage mappings but cannot impersonate the switch/revert lifecycle on someone else's behalf.
  def revert?
    record.user_id == user.id && record.enabled? && record.status == 'Switched'
  end

  class Scope < Scope
    def resolve
      if user.super?
        scope.all
      else
        # Security fix (Finding 6): Restrict non-super users to enabled (active) mappings only.
        # The original scope returned all mappings for the current user_id including disabled and
        # expired ones, leaking historical entity-access metadata (entity names, end dates) that
        # the user has no current legitimate need to see.
        scope.where(user_id: user.id, enabled: true)
      end
    end
  end

  def index?
    true
  end

  def show?
    super_user? || (record.user_id == user.id && record.enabled?)
  end

  def create?
    super_user?
  end

  def new?
    create?
  end

  def update?
    create?
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end
end

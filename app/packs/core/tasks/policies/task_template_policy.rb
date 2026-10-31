# M18 — task templates are copied into every generated next-step task, and their help / action links
# render on the task timeline. A global template (no entity) reaches every firm, so only support writes
# those; a firm's own templates are written by that firm's company admins (or support).
# Worked examples M18-1, M18-2, M18-3, M18-4, M18-H — docs/security/security_review_2026_10.md#core--misc--medium-and-low
class TaskTemplatePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      # Support sees every template; everyone else the global ones and their own firm's (M18-H)
      return scope.all if user.support?

      scope.where(entity_id: [nil, user.entity_id])
    end
  end

  def index?
    true
  end

  def generate?
    true
  end

  # Global templates, the user's own firm's, or any for support (M18-3)
  def show?
    record.entity_id.nil? || support? || belongs_to_entity?(user, record)
  end

  # M18 — writes: a global template by support only (M18-1); a firm template by support, or a company
  # admin of that firm (M18-2, M18-H)
  def create?
    # 1. Support writes any template
    return true if support?
    # 2. Nobody else writes a global one
    return false if record.entity_id.nil?

    # 3. A firm's template: that firm's company admin
    belongs_to_entity?(user, record) && user.has_cached_role?(:company_admin)
  end

  # The blank form: support, or a company admin (whose form defaults to their own firm). What is
  # saved is checked by create? (M18-1, M18-H)
  def new?
    support? || user.has_cached_role?(:company_admin)
  end

  def update?
    create?
  end

  def completed?
    update?
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end
end

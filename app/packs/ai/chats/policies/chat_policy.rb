class ChatPolicy < ApplicationPolicy
  class Scope < BaseScope
    def resolve
      if user.has_cached_role?(:company_admin)
        scope.where(entity_id: user.entity_id)
      else
        scope.where(user_id: user.id)
      end
    end
  end

  def index?
    true
  end

  # M7 — a chat holds the question history and tool results of whoever asked, so a colleague may not
  # open it by id. Own firm, and either the chat's own user or a company admin (the Decision kept
  # admins able to read their employees' transcripts). Same rows as Scope#resolve.
  # Worked examples M7-1, M7-H — docs/security/security_review_2026_10.md#core--misc--medium-and-low
  def show?
    # 1. Never another firm's chat
    return false unless belongs_to_entity?(user, record)

    # 2. The asker themselves, or a company admin of the firm
    record.user_id == user.id || user.has_cached_role?(:company_admin)
  end

  # M7 — the efficiency report lists every tool call and its result, so it is exactly as private as
  # the chat itself (M7-1, M7-H)
  def efficiency_report?
    show?
  end

  def create?
    # D: the parent is in one of the user's firms (funds_api_security_policy_plan.md)
    belongs_to_entity?(user, record) && parent_in_users_firms?(record.owner) && user.has_cached_role?(:company_admin)
  end

  def new?
    create?
  end

  def send_message?
    update?
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

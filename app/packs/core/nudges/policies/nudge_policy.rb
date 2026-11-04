class NudgePolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    belongs_to_entity?(user, record)
  end

  # M14 — a nudge is about an item (a deal investor, a deal task, …) whose LP emails the form prefills,
  # so the item must be in the user's firms and one they may open. A nudge without an item needs only
  # the firm check. Worked examples M14-1, M14-H — docs/security/security_review_2026_10.md#core--misc--medium-and-low
  def create?
    # 1. The nudge itself is the user's firm's
    return false unless belongs_to_entity?(user, record)

    # 2. No item: nothing more to check
    item = record.item
    return true if item.nil?

    # 3. The item is in one of the user's firms, and its own policy lets the user see it
    return false unless parent_in_users_firms?(item)

    Pundit.policy(user, item)&.show? || false
  end

  def new?
    create?
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
end

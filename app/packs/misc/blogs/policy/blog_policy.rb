class BlogPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.all
    end
  end

  def index?
    true
  end

  def show?
    true # support?
  end

  # L11 — blogs are CapHive content: anyone signed in reads them, only support writes them
  # (create / update / destroy all come here). Tests L11-1, L11-H —
  # features/security/security_review_2026_10_low.feature
  def create?
    support?
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

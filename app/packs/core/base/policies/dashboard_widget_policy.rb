class DashboardWidgetPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  def index?
    true
  end

  def dashboard?
    true
  end

  def metadata_help?
    true
  end

  def show?
    belongs_to_entity?(user, record)
  end

  def create?
    belongs_to_entity?(user, record)
  end

  # Setting up LP layouts: only for fund managers with the fund-portfolios module (E96 —
  # openspec/changes/lp-folio-portfolio-dashboard/business-rules.md)
  def manage_lp_layouts?
    create? && user.entity.permissions.enable_fund_portfolios?
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

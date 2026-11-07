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

  # The settings icon and popup on a dashboard (openspec/changes/dashboard-widget-inline-settings — D6):
  # whoever may edit the widget, except a user acting as an investor (X1). For a default widget the record is
  # an unsaved DashboardWidget of the user's own firm, so the same firm check applies (X2).
  def inline_settings?
    update? && !user.curr_role_investor?
  end

  def destroy?
    update?
  end
end

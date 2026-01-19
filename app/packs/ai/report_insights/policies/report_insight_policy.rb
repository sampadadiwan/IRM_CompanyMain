class ReportInsightPolicy < ApplicationPolicy
  class Scope < BaseScope
    def resolve
      if user.curr_role_employee? || support?
        scope.where(report: Pundit.policy_scope!(user, Report))
      else
        scope.none
      end
    end
  end

  def index?
    user.entity.support_agents.report_analysis_agent? || support?
  end

  def show?
    user.entity.support_agents.report_analysis_agent? && record.report.present? && Pundit.policy(user, record.report).show?
  end

  def generate?
    show?
  end
end

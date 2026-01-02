class AiReportSectionPolicy < ApplicationPolicy
  # Delegate authorization to the parent AiPortfolioReport
  # User can modify a section if they can update the parent report

  delegate :show?, to: :report_policy

  delegate :update?, to: :report_policy

  def toggle_web_search?
    report_policy.update?
  end

  def add_content?
    report_policy.update?
  end

  def toggle_reviewed?
    report_policy.update?
  end

  def regenerate?
    report_policy.update?
  end

  def generate_chart_preview?
    report_policy.update?
  end

  def insert_chart?
    report_policy.update?
  end

  def remove_chart?
    report_policy.update?
  end

  private

  def report_policy
    @report_policy ||= Pundit.policy(user, record.ai_portfolio_report)
  end
end

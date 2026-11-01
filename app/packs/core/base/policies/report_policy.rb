class ReportPolicy < ApplicationPolicy
  # An AI report draft ("Describe it") is private to its maker until saved
  # (report-builder-assistant E9, X7)
  AI_DRAFT = "AI draft".freeze

  class Scope < Scope
    def resolve
      scope.where(entity_id: [user.entity_id, nil], curr_role: user.curr_role)
           .where("reports.category IS NULL OR reports.category <> ? OR reports.user_id = ?", AI_DRAFT, user.id)
    end
  end

  def index?
    true
  end

  def prompt?
    true
  end

  def show?
    (belongs_to_entity?(user, record) || record.entity.nil?) && own_draft_or_not_a_draft?
  end

  def dynamic?
    show?
  end

  def create?
    belongs_to_entity?(user, record)
  end

  def new?
    create?
  end

  def update?
    create? && own_draft_or_not_a_draft?
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end

  def configure_grids?
    update?
  end

  def own_draft_or_not_a_draft?
    record.category != AI_DRAFT || record.user_id == user.id
  end

  def generate_report_insight?
    update? && user.entity.support_agents.report_analysis_agent?
  end
end

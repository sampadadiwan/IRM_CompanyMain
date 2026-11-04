# A report belongs to a firm only through its portfolio company (an Investor whose entity_id is the
# GP firm), so every rule here hangs off record.portfolio_company - the parent-record pattern of
# ApplicationPolicy#parent_in_users_firms?. A Group Company user also reaches its child firms' reports.
#
# @see docs/security/security_review_2026_10.md (C3 - AI Portfolio Reports, Option A: no entity_id column)
class AiPortfolioReportPolicy < ApplicationPolicy
  # The firms whose portfolio companies a user works on: their own, plus the child firms of a
  # Group Company (the same firms ApplicationPolicy#users_firm? accepts).
  #
  # @param user [User]
  # @return [Array<Integer>] entity ids
  def self.firm_entity_ids(user)
    # Own firm first, then any group children
    ids = [user.entity_id]
    ids += user.entity.child_ids if user.entity_type == "Group Company"
    ids
  end

  # C3-2 - lists only reports whose portfolio company is in one of the user's firms. A report whose
  # company was deleted has no row to join, so it is not listed (Option A).
  class Scope < BaseScope
    def resolve
      # Tenancy comes from the portfolio company, not from the report or its analyst
      scope.joins(:portfolio_company)
           .where(investors: { entity_id: AiPortfolioReportPolicy.firm_entity_ids(user) })
    end
  end

  # C3-X - the portfolio companies the new-report form may offer: those of the user's firms.
  class CompanyScope < BaseScope
    def resolve
      # Same firms as the report scope above
      scope.where(entity_id: AiPortfolioReportPolicy.firm_entity_ids(user))
    end
  end

  def index?
    true
  end

  # C3-1 - only users of the firm that owns the portfolio company (or its group parent).
  def show?
    company_in_users_firms?
  end

  # C3-4, C3-5, C3-9 - the portfolio company, the folder the report reads and the investment criteria
  # template must all be in the user's firms. Unset parents (the blank new-report form) pass.
  def create?
    parent_in_users_firms?(record.portfolio_company) &&
      parent_in_users_firms?(record.folder) &&
      parent_in_users_firms?(record.investment_criteria_template)
  end

  def new?
    create?
  end

  # C3-3, C3-6 - same firm rule as show?; AiReportSectionPolicy delegates here.
  def update?
    company_in_users_firms?
  end

  def edit?
    update?
  end

  # C3-3 - same firm rule as show?.
  def destroy?
    company_in_users_firms?
  end

  def add_content?
    update?
  end

  def collated_report?
    show? # Same permission as viewing the report
  end

  def save_collated_report?
    update? # Same permission as updating the report
  end

  def export_docx?
    show? # Same permission as viewing the report
  end

  def toggle_master_web_search?
    update?
  end

  def export_pdf?
    show? # Same permission as viewing the report
  end

  private

  # An existing report needs its portfolio company: without one there is no firm to check against,
  # so it is refused (parent_in_users_firms? alone would let a nil parent through).
  def company_in_users_firms?
    record.portfolio_company.present? && parent_in_users_firms?(record.portfolio_company)
  end
end

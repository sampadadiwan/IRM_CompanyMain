# Who may open the LP Company Dashboard (design card ⑥, access flowchart):
#
#   show?    — an investor user whose visible set includes the company through this fund: the fund is one they
#              can see (X10, X11), its LP portfolio view is not Hidden (X12), and the company has a holding visible
#              to them in it (X9). The company's Show to LPs switch is checked by the controller, so a switched-off
#              company says "not shared yet" (E53).
#   preview? — a fund-team member of the company's fund manager who may view the company (X15 refuses LPs);
#              the previewed investor must belong to the same fund manager.
# Both need the fund manager's fund-portfolios module (X21).
# Worked examples H10, H13, X9–X12, X15, X21, E65 — openspec/changes/lp-folio-portfolio-dashboard/business-rules.md
class LpCompanyDashboardPolicy < ApplicationPolicy
  def show?
    return false unless portfolios_module? && user.curr_role_investor? && record.fund && !record.preview?

    record.visibility.openable?(record.company, record.fund)
  end

  def preview?
    return false if !portfolios_module? || user.curr_role_investor? || !record.preview?
    return false unless user.entity_id == record.company.entity_id && record.preview_investor.entity_id == record.company.entity_id

    InvestorPolicy.new(user, record.company).show?
  end

  # X21 — the company's fund manager has the fund-portfolios module
  def portfolios_module?
    record.company.entity.permissions.enable_fund_portfolios?
  end

  # The previewed LP's own access, so a preview shows exactly what that LP would get (E65)
  def preview_openable?
    record.fund.present? && record.visibility.openable?(record.company, record.fund)
  end
end

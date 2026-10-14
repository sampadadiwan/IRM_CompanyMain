# The LP Company Dashboard (design card ⑥): one page per portfolio company, seen through one fund — the holdings
# card, then the widgets of the LP layout chosen for the company. Replaces the per-holding preview page.
#
#   show    — an LP opens a company from their portfolio (H10)
#   preview — the fund team sees exactly what a chosen LP would see (H13)
#
# Worked examples H10–H14, E44–E68, E78, E80–E87, E90, E93, X9–X16 —
# openspec/changes/lp-folio-portfolio-dashboard/business-rules.md
class LpCompanyDashboardsController < ApplicationController
  NO_ACCESS = "You do not have access to this company.".freeze
  NOT_SHARED = "No company information has been shared yet.".freeze

  # X9–X12, X15 — refusals say so plainly on this page, never show company data
  rescue_from Pundit::NotAuthorizedError, with: :refuse

  # GET /lp/portfolio_companies/:id?fund_id=
  def show
    @company = Investor.find(params[:id])
    visibility = LpPortfolioVisibility.for_user(current_user)
    @page = LpCompanyPage.new(company: @company, fund: chosen_fund(visibility), visibility:)
    authorize @page, :show?
    render_page
  end

  # GET /lp/portfolio_companies/:id/preview?investor_id=&fund_id=
  def preview
    @company = Investor.find(params[:id])
    investor = Investor.find_by(id: params[:investor_id], entity_id: @company.entity_id)
    raise Pundit::NotAuthorizedError if investor.nil?

    visibility = LpPortfolioVisibility.for_investor(investor)
    @page = LpCompanyPage.new(company: @company, fund: chosen_fund(visibility), visibility:, preview_investor: investor)
    authorize @page, :preview?
    # E65 — previewing an LP who could not open this company shows that LP's refusal
    return refuse unless policy(@page).preview_openable?

    render_page
  end

  private

  # The fund asked for, or the first qualifying fund by name (H14). An unknown or inaccessible fund is refused by
  # the policy (X11).
  def chosen_fund(visibility)
    @funds = visibility.qualifying_funds_for(@company)
    params[:fund_id].present? ? Fund.find_by(id: params[:fund_id]) : @funds.first
  end

  def render_page
    # E53, X16 — a company the fund team has not shared says so, with no company data
    return render(:not_shared) unless @company.show_to_lps

    @fund = @page.fund
    # The widget partials read @investor (the portfolio company), as on the internal dashboard
    @investor = @company
    @layout = LpLayoutResolver.for(@company)
    @holdings = @page.visibility.visible_holdings(@company, @fund).to_a
    # H10 — the LP's own share on the holdings card, under an own-share view
    @own_share = LpOwnShareSummary.from(@page.visibility, @fund)
    @own_share&.annotate(@holdings)
    render :show
  end

  def refuse(_exception = nil)
    @message = NO_ACCESS
    render :refusal, status: :forbidden
  end
end

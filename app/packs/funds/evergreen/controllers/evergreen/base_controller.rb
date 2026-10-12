# Every evergreen screen hangs off a fund the user can see (policy_scope) on an entity with evergreen
# funds switched on. Records are always loaded through @fund, so ids from another fund or entity 404.
# Worked examples E47, X19 — openspec/changes/open-ended-funds/design.md#worked-examples
module Evergreen
  class BaseController < ApplicationController
    before_action :set_fund
    before_action :set_bread_crumbs, unless: :turbo_frame_request?
    # Loaded into a fund-page tab: render inside the requesting frame; otherwise the normal app layout
    layout -> { "evergreen_frame" if turbo_frame_request? }

    # Section label and list page for each evergreen controller (breadcrumbs, like other fund pages)
    SECTIONS = {
      "settings" => ["Evergreen Settings", nil], "dealing_dates" => ["Dealing Dates", :evergreen_dealing_dates_path],
      "orders" => ["Subscriptions and redemptions", :evergreen_orders_path], "navs" => ["NAV", :evergreen_navs_path],
      "investors" => ["Investors", :evergreen_investors_path], "fees" => ["Fees", :evergreen_fees_path],
      "folios" => ["Investors", :evergreen_investors_path], "settlements" => ["Dealing Dates", :evergreen_dealing_dates_path],
      "dealing_fills" => ["Dealing Dates", :evergreen_dealing_dates_path]
    }.freeze

    private

    def set_fund
      @fund = policy_scope(Fund).find(params[:fund_id])
    end

    # Funds › fund › section (linked on detail pages) — the layout's _breadcrumbs partial renders @bread_crumbs
    def set_bread_crumbs
      label, list_path = SECTIONS.fetch(controller_name, [controller_name.humanize, nil])
      # Review fix 9: the dealing-date crumb follows the fund's wording (US: "Transaction Dates"), like the
      # Actions menu and the tab — it was hard-coded "Dealing Dates"
      label = EvergreenLabels.t(:transaction_date, fund: @fund).titleize.pluralize if label == "Dealing Dates"
      @bread_crumbs = { Funds: funds_path, @fund.name => fund_path(@fund) }
      detail = action_name != "index" && list_path
      # Orders are listed as Subscriptions or Redemptions: the crumb names the order's own kind
      kind = order_kind_for_crumb if controller_name == "orders"
      label = kind.pluralize.capitalize if kind
      list_args = kind ? [@fund, { kind: }] : [@fund]
      @bread_crumbs[label] = detail ? send(list_path, *list_args) : nil
      @bread_crumbs[action_name == "new" ? "New" : "Details"] = nil if detail
    end

    # subscription / redemption for the orders pages: the order's kind on a detail page, else ?kind=
    def order_kind_for_crumb
      kind = params[:id] ? DealingOrder.where(fund_id: @fund.id).where(id: params[:id]).pick(:kind) : params[:kind]
      kind if DealingOrder::KINDS.include?(kind)
    end

    def evergreen_setting
      @evergreen_setting ||= @fund.evergreen_fund_setting
    end

    # Screens other than Settings need an evergreen fund
    def require_evergreen!
      return if @fund.evergreen?

      redirect_to fund_path(@fund), alert: "This fund is not evergreen"
    end

    def gp_user?
      current_user.curr_role != "investor"
    end
    helper_method :gp_user?
  end
end

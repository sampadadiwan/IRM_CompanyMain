# NAV list, drafting, line overrides, approve / reopen / recalculate / delete draft.
# Worked examples H3–H6, E9–E12, E35, X5–X9 — openspec/changes/open-ended-funds/design.md#worked-examples
module Evergreen
  class NavsController < BaseController
    before_action :require_evergreen!
    before_action :set_fund_nav, only: %i[show destroy override approve reopen recalculate decide_late_fee]

    # The list's filter: everything (default), drafts waiting for an approver, or approved only
    FILTERS = { "all" => "All", "awaiting" => "Awaiting approval", "approved" => "Approved" }.freeze

    def index
      authorize FundNav.new(fund: @fund, entity_id: @fund.entity_id), :show?
      @filter = FILTERS.key?(params[:filter]) ? params[:filter] : "all"
      # A fund has a few NAVs a month per class, so the whole history is loaded (newest first)
      navs = policy_scope(FundNav).where(fund_id: @fund.id).order(nav_date: :desc, unit_type: :asc).to_a
      # Change column: each NAV against the class's previous APPROVED NAV by date (a reopened or new draft is
      # never the baseline). One pass oldest-first, keeping the last approved NAV per class; taken before
      # filtering so an approved NAV still compares with the one before it when drafts are hidden
      last_approved = {}
      @previous = navs.reverse.to_h do |n|
        prev = last_approved[n.unit_type]
        last_approved[n.unit_type] = n if n.approved?
        [n.id, prev]
      end
      navs = navs.select(&:draft?) if @filter == "awaiting"
      navs = navs.select(&:approved?) if @filter == "approved"
      # Drafts first (they need someone), then newest first
      @fund_navs = navs.each_with_index.sort_by { |n, i| [n.draft? ? 0 : 1, i] }.map(&:first)
    end

    def show
      authorize @fund_nav
    end

    # Draft every class for a date (X5 shows the builder's error)
    def create
      authorize FundNav.new(fund: @fund, entity_id: @fund.entity_id), :create?
      nav_date = parse_nav_date
      return redirect_to(evergreen_navs_path(@fund), alert: "Choose a valid NAV date") unless nav_date

      result = FundNavBuilder.call(fund: @fund, nav_date:, current_user:)
      if result.success?
        redirect_to evergreen_nav_path(@fund, result[:fund_navs].first), notice: "NAV drafted for #{I18n.l(nav_date)}"
      else
        redirect_to evergreen_navs_path(@fund), alert: result[:errors]
      end
    end

    def override
      authorize @fund_nav, :update?
      result = FundNavOverride.call(fund_nav: @fund_nav, line: params[:line], value: params[:value], reason: params[:reason], current_user:)
      if result.success?
        redirect_to evergreen_nav_path(@fund, @fund_nav), notice: "Line overridden"
      else
        redirect_to evergreen_nav_path(@fund, @fund_nav), alert: result[:errors]
      end
    end

    def approve
      authorize @fund_nav, :approve?
      result = FundNavApprove.call(fund_nav: @fund_nav, current_user:)
      redirect_to evergreen_nav_path(@fund, @fund_nav), result.success? ? { notice: "NAV approved" } : { alert: result[:errors] }
    end

    # Include or exclude the draft's late management fee, or clear the decisions (R9.13; H106, H107, X204, X205)
    def decide_late_fee
      authorize @fund_nav, :decide_late_fee?
      decision = params.expect(late_fee: %i[choice reason])
      result = FundNavLateFeeDecision.call(fund_nav: @fund_nav, choice: decision[:choice], reason: decision[:reason], current_user:)
      notice = { "include" => "Late fee included", "exclude" => "Late fee excluded" }.fetch(decision[:choice], "Late fee decision cleared")
      redirect_to evergreen_nav_path(@fund, @fund_nav), result.success? ? { notice: } : { alert: result[:errors] }
    end

    def reopen
      authorize @fund_nav, :reopen?
      result = FundNavReopen.call(fund_nav: @fund_nav, current_user:)
      redirect_to evergreen_nav_path(@fund, @fund_nav), result.success? ? { notice: "NAV reopened" } : { alert: result[:errors] }
    end

    def recalculate
      authorize @fund_nav, :update?
      result = FundNavBuilder.call(fund: @fund, nav_date: @fund_nav.nav_date, current_user:)
      redirect_to evergreen_nav_path(@fund, @fund_nav), result.success? ? { notice: "NAV recalculated" } : { alert: result[:errors] }
    end

    def destroy
      authorize @fund_nav
      @fund_nav.destroy!
      redirect_to evergreen_navs_path(@fund), notice: "Draft deleted"
    end

    private

    def parse_nav_date
      Date.iso8601(params.require(:nav_date).to_s)
    rescue Date::Error
      nil
    end

    def set_fund_nav
      @fund_nav = @fund.fund_navs.find(params[:id])
    end
  end
end

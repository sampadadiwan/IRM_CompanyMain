# ⑥ The register: open items by default, the standard grid filter (ransack, allow-listed attributes),
# search, detail with the working, assign (H26). The Open / Closed / All tabs are preset filters on
# status: a status condition in the filter replaces them with one "Filter results" tab, so the two
# never disagree (E139).
class ComplianceRegisterItemsController < ApplicationController
  include ComplianceCrumbs

  # Tab → the ransack condition it stands for
  STATUS_PRESETS = { "open" => { "status_not_eq" => "closed" }, "closed" => { "status_eq" => "closed" } }.freeze

  before_action :set_item, only: %i[show assign]

  # The page holds the filter, header and the Open / Closed / All pills; each pill's pane loads its grid
  # lazily into its own turbo frame (funds/_owner_fund_details pattern). A frame request renders only
  # that grid — its search, sort and pages stay inside the frame.
  def index
    authorize ComplianceRegisterItem
    @user_q = params[:q].respond_to?(:to_unsafe_h) ? params[:q].to_unsafe_h : {}
    # A status condition in the filter replaces the tabs with one "Filter results" pane (E139)
    @filter_sets_status = status_condition?(@user_q)
    compliance_crumbs(["Register", nil])
    # The inner Open / Closed / All tab frames; the hub's Register pane (R170) is answered below
    return render_grid_frame if turbo_frame_request? && !hub_frame_request?(:register)

    # The filter panel shows only the user's own conditions, never a tab's preset. The rows load in the
    # tab frames; the page itself still goes through the policy scope (verify_policy_scoped)
    @q = ComplianceRegisterItem.ransack(@user_q)
    policy_scope(ComplianceRegisterItem)
    render_hub_pane(:register, "compliance_register_items/index") if hub_frame_request?(:register)
  end

  def show
    authorize @item
    compliance_crumbs(["Register", compliance_register_items_path], [@item.check_name, nil])
  end

  # H26: assigning emails the assignee; the item moves to In progress
  def assign
    authorize @item
    assignee = User.where(entity_id: current_user.entity_id, active: true).find_by(id: params[:assignee_id])
    return respond_with_item(alert: "Choose a user of your firm") if assignee.nil?

    @item.update!(assignee:, status: @item.status == "open" ? "in_progress" : @item.status)
    ComplianceNotices.assignment(@item, assignee)
    respond_with_item(notice: "Assigned to #{assignee.full_name}")
  end

  private

  # One tab's grid (or the filter-results grid) inside its own frame
  def render_grid_frame
    @tab = if @filter_sets_status
             "filtered"
           else
             (STATUS_PRESETS.key?(params[:status]) ? params[:status] : "all")
           end
    scope = filtered_scope(@tab)
    @stats_scope = ComplianceRegisterItem.where(id: scope.select(:id))
    scope = scope.order(opened_on: :desc, id: :desc) if @q.sorts.empty?
    @pagy, @items = pagy(scope, limit: params[:per_page] || 10)
    render partial: "compliance_register_items/grid_frame", locals: { tab: @tab, items: @items }
  end

  # The user's filter plus the tab's preset status condition, policy-scoped, with the search box
  def filtered_scope(tab)
    query = STATUS_PRESETS.key?(tab) ? @user_q.merge(STATUS_PRESETS[tab]) : @user_q
    @q = ComplianceRegisterItem.ransack(query)
    scope = policy_scope(@q.result).includes(:fund, :assignee, :last_result, fund_compliance_pack: %i[compliance_pack compliance_pack_version])
    scope = scope.where(fund_id: params[:fund_id]) if params[:fund_id].present?
    search(scope, params.dig(:search, :value))
  end

  def status_condition?(query)
    ComplianceRegisterItem.ransack(query).conditions.any? { |c| c.attributes.any? { |a| a.name == "status" } }
  end

  def set_item
    @item = policy_scope(ComplianceRegisterItem).find_by(id: params[:id]) || raise(Pundit::NotAuthorizedError)
  end

  # Turbo stream: replace the item's summary and show the flash; HTML: back to the item
  def respond_with_item(notice: nil, alert: nil)
    respond_to do |format|
      format.turbo_stream do
        @notice = notice
        @alert = alert
        render "compliance_register_items/updated"
      end
      format.html { redirect_to compliance_register_item_path(@item), notice:, alert: }
    end
  end

  # Search box: fund name or check
  def search(scope, value)
    return scope if value.blank?

    like = "%#{ActiveRecord::Base.sanitize_sql_like(value.to_s.strip)}%"
    scope.joins(:fund).where("funds.name LIKE :like OR compliance_register_items.check_key LIKE :like", like:)
  end
end

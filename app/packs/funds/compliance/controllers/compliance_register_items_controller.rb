# ⑥ The register: open items by default (Status filter), detail with the working, assign (H26).
class ComplianceRegisterItemsController < ApplicationController
  before_action :set_item, only: %i[show assign]

  def index
    authorize ComplianceRegisterItem
    scope = policy_scope(ComplianceRegisterItem).includes(:fund, :assignee, :last_result, fund_compliance_pack: :compliance_pack)
    @status = params[:status].presence || "open"
    scope = if @status == "closed"
              scope.closed_items
            else
              (@status == "all" ? scope : scope.open_items)
            end
    scope = scope.where(fund_id: params[:fund_id]) if params[:fund_id].present?
    @pagy, @items = pagy(scope.order(opened_on: :desc, id: :desc))
  end

  def show
    authorize @item
  end

  def assign
    authorize @item
    assignee = User.where(entity_id: current_user.entity_id, active: true).find_by(id: params[:assignee_id])
    return redirect_to(compliance_register_item_path(@item), alert: "Choose a user of your firm") if assignee.nil?

    @item.update!(assignee:, status: @item.status == "open" ? "in_progress" : @item.status)
    ComplianceNotices.assignment(@item, assignee)
    redirect_to compliance_register_item_path(@item), notice: "Assigned to #{assignee.full_name}"
  end

  private

  def set_item
    @item = policy_scope(ComplianceRegisterItem).find_by(id: params[:id]) || raise(Pundit::NotAuthorizedError)
  end
end

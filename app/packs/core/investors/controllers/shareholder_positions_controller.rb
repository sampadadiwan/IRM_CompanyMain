class ShareholderPositionsController < ApplicationController
  before_action :set_shareholder_position, only: %i[approve reject]

  # GET /shareholder_positions
  # Complete list of ShareholderPosition rows as uploaded for a portfolio company - mirrors
  # InvestmentsController#index so the "Shareholding upload case" gets the same "View"/"Download"
  # experience as the Investments case.
  def index
    @bread_crumbs = { "Shareholder Positions" => shareholder_positions_path }
    @q = ShareholderPosition.ransack(params[:q])
    @shareholder_positions = policy_scope(@q.result).includes(:investor, :portfolio_company, :fund)
    @shareholder_positions = filter_params(
      @shareholder_positions,
      :portfolio_company_id,
      :category,
      :status
    )

    if params[:portfolio_company_id].present?
      @portfolio_company_id = params[:portfolio_company_id]
      @portfolio_company = Investor.find(@portfolio_company_id)
      @bread_crumbs[@portfolio_company.investor_name.to_s] = investor_path(@portfolio_company)
      authorize @portfolio_company, :show?
    end

    # Same rationale as InvestmentsController#index: a portfolio company's full holdings list
    # should not be paginated away, since it's meant to be a complete record of what was uploaded.
    @use_pagy = params[:portfolio_company_id].blank?

    @pagy, @shareholder_positions = pagy(@shareholder_positions) if @use_pagy

    respond_to do |format|
      format.html
      format.xlsx
    end
  end

  # PATCH /shareholder_positions/1/approve
  # Accepts a staged Fully Diluted Quantity/% update: overwrites the matching approved position
  # with the new value and discards this staging row (see ShareholderPositionApprover). A pure
  # %-only update can't be approved one-off this way - see ShareholderPositionPolicy#individually_approvable?
  # - it must go through approve_all ("Accept All") instead.
  def approve
    authorize @shareholder_position, :individually_approvable?
    ShareholderPositionApprover.call(@shareholder_position.id, current_user.id)
    redirect_back_or_to(investors_path, notice: "Update approved and applied.")
  end

  # DELETE /shareholder_positions/1/reject
  # Denies a staged update: deletes the staging row, leaving the existing approved position
  # untouched. A pure %-only update can't be rejected one-off this way - see
  # ShareholderPositionPolicy#individually_rejectable? - it must go through approve_all
  # ("Reject All") instead.
  def reject
    authorize @shareholder_position, :individually_rejectable?
    @shareholder_position.destroy
    redirect_back_or_to(investors_path, notice: "Update rejected.")
  end

  # PATCH /shareholder_positions/approve_all?ids[]=1&ids[]=2
  # Mirrors KpisController#approve_all: bulk-accepts (or, with reject=true, bulk-denies) a
  # specific set of staged Fully Diluted Quantity/% updates in one go, instead of one row at a
  # time. Scoped to the exact ids the view has just rendered (e.g. all pending rows for a single
  # funding round) rather than every pending row for the company, so it can't silently sweep up
  # unrelated staged updates. Each row is still individually authorized, so a caller can never
  # approve/reject a row outside their entity by tampering with the id list.
  def approve_all
    shareholder_positions = ShareholderPosition.where(id: Array(params[:ids]))

    if params[:reject] == "true"
      shareholder_positions.find_each do |shareholder_position|
        authorize shareholder_position, :reject?
        shareholder_position.destroy
      end
      notice = "All pending updates were successfully rejected."
    else
      # Each row is approved independently, exactly like Quantity Fully Dilluted/Quantity Actual
      # updates - no aggregate Fully Dilluted % total check blocks any row here.
      shareholder_positions.find_each do |shareholder_position|
        authorize shareholder_position, :approve?
        ShareholderPositionApprover.call(shareholder_position.id, current_user.id)
      end

      notice = "All pending updates were successfully approved."
    end

    redirect_back_or_to(investors_path, notice: notice)
  end

  private

  def set_shareholder_position
    @shareholder_position = ShareholderPosition.find(params[:id])
  end
end

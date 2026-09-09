# The LP Obligation Matrix and the counsel review gate. Index is the per-fund
# matrix; the member actions drive the obligation lifecycle:
#   approve/reject — review gate (ObligationApprove / ObligationReject)
#   waive          — end an approved obligation, tearing down its projections
#   fire           — create a dated task from an armed (event-triggered) obligation
#   fulfill        — record an out-of-band fulfillment
class SideLetterObligationsController < ApplicationController
  before_action :set_obligation, only: %i[show edit update destroy approve reject waive revert fire fulfill]

  def index
    authorize SideLetterObligation
    @bread_crumbs = { 'Side Letters': side_letters_path, 'Obligation Matrix': side_letter_obligations_path }
    # Eager-load tasks alongside obligations to avoid N+1 when rendering the
    # fired-task due date and count in the matrix's "Next Due" column.
    # Eager-load side_letter chain for commitment obligations; portfolio
    # obligations have no side_letter — they use sourceable instead.
    scope = policy_scope(SideLetterObligation)
            .includes(:owner_user, :tasks, :sourceable,
                      side_letter: { capital_commitment: %i[investor fund] })
    if params[:fund_id].present?
      # Fund filter: commitment obligations join through side_letter;
      # portfolio obligations join through sourceable (PortfolioInvestment).
      scope = scope.left_joins(side_letter: :capital_commitment)
                   .left_joins(:sourceable)
                   .where("capital_commitments.fund_id = :fid OR portfolio_investments.fund_id = :fid", fid: params[:fund_id])
    end
    @q = scope.ransack(params[:q])
    @side_letter_obligations = @q.result.order(Arel.sql("next_due_date IS NULL, next_due_date ASC"))
    @funds = Fund.where(entity_id: current_user.entity_id).order(:name)
  end

  # Displays the obligation detail page. Turbo Stream requests (e.g. the
  # Cancel button on the inline edit form) receive just the display row
  # partial so the matrix row snaps back without a full page load.
  def show
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          @obligation,
          partial: "side_letter_obligations/side_letter_obligation",
          locals: { obligation: @obligation }
        )
      end
      format.html do
        # Layout breadcrumb card: Home • Side Letters • Investor • Obligation
        @bread_crumbs = {
          'Side Letters': side_letters_path,
          "#{@obligation.investor.investor_name}": side_letter_path(@obligation.side_letter),
          "#{@obligation.title}": side_letter_obligation_path(@obligation)
        }
        @fulfillments = @obligation.obligation_fulfillments.includes(:fulfilled_by, :document).order(fulfilled_at: :desc)
        @tasks = @obligation.tasks.includes(:assigned_to)
                            .order(Arel.sql("completed ASC, due_date IS NULL, due_date ASC"))
        @reminders = @obligation.obligation_reminders.order(sent_at: :desc)
      end
    end
  end

  def new
    # side_letter_id is optional: from a side letter page it pre-scopes the form;
    # from the entity-wide matrix the form asks which side letter instead.
    side_letter = SideLetter.find_by(id: params[:side_letter_id])
    @obligation = SideLetterObligation.new(side_letter: side_letter,
                                           entity_id: current_user.entity_id,
                                           extracted_by: "manual")
    authorize @obligation
  end

  def create
    side_letter = SideLetter.find(params[:side_letter_obligation][:side_letter_id])
    @obligation = side_letter.side_letter_obligations.new(obligation_params)
    @obligation.entity_id = side_letter.entity_id
    # Manual entry goes through the same review gate as AI extraction
    @obligation.extracted_by = "manual"
    @obligation.review_status = "pending_review"
    authorize @obligation

    if @obligation.save
      redirect_to side_letter_path(side_letter), notice: "Obligation added — pending review."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # Renders the edit form. Turbo Frame requests from the obligation matrix
  # receive the inline edit row partial (swapped in-place); standard requests
  # fall back to the full-page edit layout.
  # @note Only pending_review obligations may be edited (approved ones have live projections)
  def edit
    unless @obligation.pending_review?
      return redirect_to side_letter_obligation_path(@obligation), alert: "Only pending obligations can be edited."
    end

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          @obligation,
          partial: "side_letter_obligations/inline_edit_row",
          locals: { obligation: @obligation }
        )
      end
      format.html { render :edit }
    end
  end

  # Persists counsel edits. Turbo Frame requests receive the display row
  # partial so the matrix row snaps back to read mode after save; validation
  # failures re-render the inline form. Standard requests redirect as before.
  # @note Only pending_review obligations may be edited
  def update
    return redirect_to side_letter_obligation_path(@obligation), alert: "Only pending obligations can be edited." unless @obligation.pending_review?

    if @obligation.update(obligation_params)
      respond_to do |format|
        # Turbo Frame / Stream — replace the inline form with the refreshed display row
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            @obligation,
            partial: "side_letter_obligations/side_letter_obligation",
            locals: { obligation: @obligation }
          )
        end
        format.html do
          redirect_to (@obligation.side_letter.present? ? side_letter_path(@obligation.side_letter) : side_letter_obligations_path), notice: "Obligation updated."
        end
      end
    else
      # Validation failed — re-render the inline form with errors
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            @obligation,
            partial: "side_letter_obligations/inline_edit_row",
            locals: { obligation: @obligation }
          ), status: :unprocessable_entity
        end
        format.html { render :edit, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    return redirect_to side_letter_obligations_path, alert: "Approved obligations cannot be deleted — waive them instead." if @obligation.approved?

    @obligation.destroy
    redirect_to side_letter_obligations_path, notice: "Obligation deleted."
  end

  # Approve an obligation: projects it into the task system (recurring, one-time,
  # or armed). Responds with a Turbo Stream row replacement so the matrix updates
  # in-place without a full page reload.
  # @note Only pending_review obligations can be approved (enforced by ObligationApprove)
  def approve
    result = ObligationApprove.call(obligation: @obligation, user: current_user)
    if result.success?
      @obligation.reload
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            @obligation,
            partial: "side_letter_obligations/side_letter_obligation",
            locals: { obligation: @obligation }
          )
        end
        format.html do
          redirect_back_or_to(side_letter_obligations_path, notice: "Obligation approved#{@obligation.dated? ? ' — tasks scheduled.' : ' — armed.'}")
        end
      end
    else
      redirect_back_or_to(side_letter_obligations_path, alert: result[:error])
    end
  end

  # Reject an obligation: marks it as rejected so it never creates tasks or alerts.
  # Responds with a Turbo Stream row replacement to update status in-place.
  # @note Rejected obligations are not resurfaced on re-extraction of the same clause
  def reject
    result = ObligationReject.call(obligation: @obligation, user: current_user)
    if result.success?
      @obligation.reload
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            @obligation,
            partial: "side_letter_obligations/side_letter_obligation",
            locals: { obligation: @obligation }
          )
        end
        format.html do
          redirect_back_or_to(side_letter_obligations_path, notice: "Obligation rejected.")
        end
      end
    else
      redirect_back_or_to(side_letter_obligations_path, alert: result[:error])
    end
  end

  def waive
    result = ObligationTeardown.call(obligation: @obligation, new_status: "waived", user: current_user)
    if result.success?
      redirect_back_or_to(side_letter_obligations_path, notice: "Obligation waived — open tasks removed, history kept.")
    else
      redirect_back_or_to(side_letter_obligations_path, alert: result[:error])
    end
  end

  # Undo a wrongly applied waive: back to active, projections rebuilt
  def revert
    result = ObligationRevert.call(obligation: @obligation, user: current_user)
    if result.success?
      redirect_back_or_to(side_letter_obligations_path, notice: "Obligation reverted to active — tasks and alerts resume.")
    else
      redirect_back_or_to(side_letter_obligations_path, alert: result[:error])
    end
  end

  # Fire an armed obligation: creates a dated task with the user-supplied deadline.
  # The obligation remains armed (re-firable for the next event occurrence).
  # Redirects to the obligation matrix so the user sees the updated row.
  def fire
    result = ObligationFire.call(obligation: @obligation, due_date: params[:due_date].presence, user: current_user)
    if result.success?
      redirect_to side_letter_obligations_path, notice: "Obligation fired — task due #{result[:task].due_date.strftime('%d %b %Y')}."
    else
      redirect_back_or_to side_letter_obligations_path, alert: result[:error]
    end
  end

  def fulfill
    fulfillment = @obligation.obligation_fulfillments.new(fulfillment_params)
    fulfillment.entity_id = @obligation.entity_id
    fulfillment.fulfilled_by = current_user
    fulfillment.fulfilled_at ||= Time.zone.today

    if fulfillment.save
      @obligation.update!(status: "fulfilled") if @obligation.trigger_one_time? && @obligation.approved?
      redirect_back_or_to(side_letter_obligation_path(@obligation), notice: "Fulfillment recorded.")
    else
      redirect_back_or_to(side_letter_obligation_path(@obligation), alert: fulfillment.errors.full_messages.to_sentence)
    end
  end

  private

  def set_obligation
    @obligation = SideLetterObligation.find(params[:id])
    authorize @obligation
  end

  # @return [ActionController::Parameters] permitted obligation attributes.
  #   Includes legal_category so counsel can correct CP/CS/SLO classification
  #   from the inline edit form before approving.
  def obligation_params
    params.require(:side_letter_obligation).permit(
      :obligation_type, :title, :description, :source_clause, :owner_user_id,
      :owner_team, :trigger_type, :trigger_description, :frequency_rrule,
      :next_due_date, :reminder_days_before, :mfn_relevant, :mfn_review_status,
      :legal_category
    )
  end

  def fulfillment_params
    params.require(:obligation_fulfillment).permit(:fulfilled_at, :fulfillment_method, :period_covered, :document_id)
  end
end

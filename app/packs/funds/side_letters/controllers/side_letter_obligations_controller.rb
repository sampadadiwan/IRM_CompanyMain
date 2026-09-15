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
    # Context param controls pre-filtering and column visibility:
    #   "cp_cs"       → only CP/CS obligations, hides legal category column
    #   "side_letter"  → only SLO obligations, hides legal category column
    #   nil (default)  → all obligations, shows legal category column
    @obligation_context = params[:context]
    @bread_crumbs = { 'Obligation Matrix': side_letter_obligations_path }
    # Eager-load tasks alongside obligations to avoid N+1 when rendering the
    # fired-task due date and count in the matrix's "Next Due" column.
    # Eager-load side_letter chain for commitment obligations; portfolio
    # obligations have no side_letter — they use sourceable instead.
    # preload(:sourceable) instead of includes(:sourceable) because Rails
    # cannot eager-load a polymorphic association via LEFT JOIN — preload
    # uses a separate query per type, which works with polymorphics.
    scope = policy_scope(SideLetterObligation)
            .includes(:owner_user, :tasks,
                      side_letter: { capital_commitment: %i[investor fund] })
            .preload(:sourceable)
    if params[:fund_id].present?
      # Fund filter: both paths use subqueries to avoid polymorphic JOIN issues.
      # Commitment obligations: side_letter → capital_commitment → fund_id
      commitment_ids = SideLetterObligation
                         .joins(side_letter: :capital_commitment)
                         .where(capital_commitments: { fund_id: params[:fund_id] })
                         .select(:id)
      # Portfolio obligations: sourceable → portfolio_investment → fund_id
      pi_ids = PortfolioInvestment.where(fund_id: params[:fund_id]).select(:id)
      scope = scope.where(id: commitment_ids)
                   .or(scope.where(sourceable_type: "PortfolioInvestment", sourceable_id: pi_ids))
    end
    # Stakeholder filter: narrows to portfolio obligations linked to a specific
    # portfolio company. Uses a subquery to avoid conflicting with the
    # polymorphic :sourceable eager-load on the base scope.
    if params[:stakeholder_id].present?
      pi_ids = PortfolioInvestment.where(portfolio_company_id: params[:stakeholder_id]).select(:id)
      scope = scope.where(sourceable_type: "PortfolioInvestment", sourceable_id: pi_ids)
    end
    # Context-based legal category scoping — pre-filters the matrix to the
    # relevant obligation type when arriving from an agent tab.
    if @obligation_context == "cp_cs"
      scope = scope.where(legal_category: %i[condition_precedent condition_subsequent])
    elsif @obligation_context == "side_letter"
      scope = scope.where(legal_category: :side_letter_obligation)
    end
    @q = scope.ransack(params[:q])
    @side_letter_obligations = @q.result.order(Arel.sql("next_due_date IS NULL, next_due_date ASC"))
    @funds = Fund.where(entity_id: current_user.entity_id).order(:name)
    # Stakeholder options: portfolio companies that have at least one obligation
    @stakeholders = Investor.where(
      id: PortfolioInvestment.where(
        id: SideLetterObligation.where(entity_id: current_user.entity_id, sourceable_type: "PortfolioInvestment").select(:sourceable_id)
      ).select(:portfolio_company_id)
    ).order(:investor_name)
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
        # Layout breadcrumb: commitment obligations link through side letter;
        # portfolio obligations link to the obligation matrix instead.
        investor_name = @obligation.source_investor&.investor_name || "Obligation"
        investor_link = if @obligation.side_letter.present?
                          side_letter_path(@obligation.side_letter)
                        else
                          side_letter_obligations_path
                        end
        @bread_crumbs = {
          Obligations: side_letter_obligations_path,
          "#{investor_name}": investor_link,
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

  # Creates a new obligation. CP/CS obligations attach to a portfolio investment
  # via sourceable; SLO obligations attach to a side letter. Both go through
  # the same pending_review gate before tasks and alerts go live.
  def create
    op = params[:side_letter_obligation]

    if op[:sourceable_type] == "PortfolioInvestment" && op[:sourceable_id].present?
      # CP/CS path: attach to portfolio investment, no side letter
      portfolio_investment = PortfolioInvestment.find(op[:sourceable_id])
      @obligation = SideLetterObligation.new(obligation_params)
      @obligation.sourceable = portfolio_investment
      @obligation.entity_id = portfolio_investment.entity_id
    else
      # SLO path: attach to side letter (original behaviour)
      side_letter = SideLetter.find(op[:side_letter_id])
      @obligation = side_letter.side_letter_obligations.new(obligation_params)
      @obligation.entity_id = side_letter.entity_id
    end

    # Manual entry goes through the same review gate as AI extraction
    @obligation.extracted_by = "manual"
    @obligation.review_status = "pending_review"
    authorize @obligation

    if @obligation.save
      redirect_to side_letter_obligations_path, notice: "Obligation added — pending review."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # Renders the edit form. Turbo Frame requests from the obligation matrix
  # receive the inline edit row partial (swapped in-place); standard requests
  # fall back to the full-page edit layout.
  # @note Only pending_review obligations may be edited (approved ones have live projections)
  # Renders the edit form. Portfolio obligations (no side_letter) are always
  # editable inline; commitment obligations are restricted to pending_review
  # because approved ones have live task projections.
  # @note Turbo Stream requests get the inline row; standard requests get the full page
  def edit
    unless editable_obligation?
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            @obligation,
            partial: "side_letter_obligations/side_letter_obligation",
            locals: { obligation: @obligation }
          )
        end
        format.html { redirect_to side_letter_obligation_path(@obligation), alert: "Only pending obligations can be edited." }
      end
      return
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

  # Persists counsel edits. Portfolio obligations are always editable;
  # commitment obligations are restricted to pending_review status.
  # Turbo Stream requests receive the display row partial so the matrix row
  # snaps back to read mode after save; validation failures re-render the
  # inline form. Standard requests redirect as before.
  def update
    return redirect_to side_letter_obligation_path(@obligation), alert: "Only pending obligations can be edited." unless editable_obligation?

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

  # Portfolio obligations (from CP/CS extraction) are always editable because
  # they have no live task projections tied to approval. Commitment obligations
  # (side letter) are restricted to pending_review to protect live projections.
  # @return [Boolean] whether the current obligation can be edited
  def editable_obligation?
    @obligation.sourceable_type == "PortfolioInvestment" || @obligation.pending_review?
  end

  # @return [ActionController::Parameters] permitted obligation attributes.
  #   Includes legal_category so counsel can correct CP/CS/SLO classification
  #   from the inline edit form before approving.
  # @return [ActionController::Parameters] permitted obligation attributes.
  #   Includes legal_category so counsel can correct CP/CS/SLO classification,
  #   and sourceable fields so manual CP/CS obligations can attach to a
  #   portfolio investment instead of a side letter.
  def obligation_params
    params.require(:side_letter_obligation).permit(
      :obligation_type, :title, :description, :source_clause, :owner_user_id,
      :owner_team, :trigger_type, :trigger_description, :frequency_rrule,
      :next_due_date, :reminder_days_before, :mfn_relevant, :mfn_review_status,
      :legal_category, :sourceable_type, :sourceable_id
    )
  end

  def fulfillment_params
    params.require(:obligation_fulfillment).permit(:fulfilled_at, :fulfillment_method, :period_covered, :document_id)
  end
end

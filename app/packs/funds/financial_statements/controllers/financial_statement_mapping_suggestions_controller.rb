# "Suggest from statements": upload, the draft review page (move entries / flip signs), Approve,
# Discard and Retry. Nothing reaches the fund's mapping before Approve.
# Worked examples H11, E18, E19, E20, X7, X12, X18 — openspec/changes/fund-financial-statements/design.md#worked-examples
class FinancialStatementMappingSuggestionsController < ApplicationController
  include FinancialStatementFundContext

  before_action :set_suggestion, only: %i[show approve discard retry_draft move flip]
  after_action :verify_authorized

  def new
    @fund = policy_scope(Fund).find(params[:fund_id])
    # No dates asked: the draft is mapping only (any period of statements will do)
    @suggestion = FinancialStatementMappingSuggestion.new(fund: @fund, entity_id: @fund.entity_id)
    authorize @suggestion
    fund_breadcrumbs("Suggest from statements")
  end

  def create
    @fund = policy_scope(Fund).find(params.dig(:financial_statement_mapping_suggestion, :fund_id))
    attrs = params.expect(financial_statement_mapping_suggestion: %i[file])
    # status and user are set here, never from the form
    @suggestion = FinancialStatementMappingSuggestion.new(fund: @fund, entity_id: @fund.entity_id, user: current_user, status: "processing",
                                                          # Mapping only: the fund's entries up to today are offered to the AI
                                                          file: attrs[:file], as_at_date: Time.zone.today)
    authorize @suggestion
    # X7: type and size are validated on create
    if @suggestion.save
      # The AI call runs in the background; the draft page polls until it is ready or failed
      FinancialStatementMappingSuggestJob.perform_later(@suggestion.id)
      redirect_to financial_statement_mapping_suggestion_path(@suggestion), notice: "Reading the statements. This usually takes a minute or two."
    else
      fund_breadcrumbs("Suggest from statements")
      render :new, status: :unprocessable_content
    end
  end

  def show
    # Which review tab is open: "lines" (by statement line) or "entries" (by account entry)
    @tab = fs_draft_tab
    fund_breadcrumbs("Mapping draft")
  end

  # PATCH move?entry_type=&name=&target= (line key | excluded | unplaced)
  def move
    return redirect_to(financial_statement_mapping_suggestion_path(@suggestion), alert: "This draft can no longer be changed.") unless @suggestion.ready?

    # From "Add an entry…" the entry comes as one value "type|||name"; from "Move to" as two params
    entry_type, name = if params[:entry].present?
                         params[:entry].to_s.split(FinancialStatementMappingSuggestion::ENTRY_SEPARATOR, 2)
                       else
                         [params[:entry_type].to_s, params[:name].to_s]
                       end
    # Rewrites the draft's rules (mapping only — nothing is recomputed)
    @suggestion.move!(entry_type.to_s, name.to_s, params[:target].to_s)
    # Back to the tab the change was made on, at the row that changed
    # (the entries tab sends its row id: an any-name rule's name is blank, the row's is not)
    anchor = fs_draft_tab == "entries" ? params[:row].presence || helpers.fs_draft_entry_anchor(entry_type, name) : "line-#{params[:target]}"
    redirect_to financial_statement_mapping_suggestion_path(@suggestion, tab: fs_draft_tab, anchor:), notice: "Moved #{entry_type} · #{name.presence || '(any name)'}."
  end

  def flip
    return redirect_to(financial_statement_mapping_suggestion_path(@suggestion), alert: "This draft can no longer be changed.") unless @suggestion.ready?

    @suggestion.flip!(params[:line].to_s)
    redirect_to financial_statement_mapping_suggestion_path(@suggestion, anchor: "line-#{params[:line]}")
  end

  def approve
    # One transaction into the fund's mapping; refused unless the draft is ready
    @suggestion.approve!(current_user)
    redirect_to financial_statement_mappings_path(fund_id: @fund.id, period_start: @suggestion.effective_period_start, period_end: @suggestion.as_at_date),
                notice: "Mapping saved from the draft. Check the preview and the Unmapped list."
  rescue FinancialStatementMappingSuggestion::NotReady
    redirect_to financial_statement_mapping_suggestion_path(@suggestion), alert: "Only a ready draft can be approved."
  rescue ActiveRecord::RecordInvalid => e
    # A line the draft can't save (e.g. a label too long): the transaction rolled back, nothing changed
    redirect_to financial_statement_mapping_suggestion_path(@suggestion), alert: "The draft could not be saved: #{e.record.errors.full_messages.to_sentence}"
  end

  # E19: nothing in the mapping changes
  def discard
    @suggestion.discard!
    redirect_to financial_statement_mappings_path(fund_id: @fund.id), notice: "Draft discarded. The mapping is unchanged."
  end

  # X12 / X18: run the AI again on the same upload
  def retry_draft
    # A failed or ready draft can be read again (an approved / discarded / running one is left alone)
    return redirect_to(financial_statement_mapping_suggestion_path(@suggestion), alert: "Only a failed or ready draft can be read again.") unless %w[failed ready].include?(@suggestion.status)

    # Back to processing so the job accepts it
    @suggestion.update!(status: "processing", error: nil)
    FinancialStatementMappingSuggestJob.perform_later(@suggestion.id)
    redirect_to financial_statement_mapping_suggestion_path(@suggestion), notice: "Trying again."
  end

  private

  # The review tab from the request; "lines" unless the entries tab is asked for
  def fs_draft_tab
    params[:tab] == "entries" ? "entries" : "lines"
  end

  def set_suggestion
    @suggestion = policy_scope(FinancialStatementMappingSuggestion).find(params[:id])
    @fund = @suggestion.fund
    authorize @suggestion
  end
end

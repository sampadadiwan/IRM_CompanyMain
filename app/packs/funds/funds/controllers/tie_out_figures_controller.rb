# Records the fund's own figure for one number while it reviews an allocation run — the "Yours"
# column of the fund totals sheet on the Account Entries Period Report. See
# docs/modules/allocation/allocation_run_review_proposals.md (proposal 3).
#
# One action, create, doing an upsert: the sheet has no separate "add" and "edit" states — a
# reviewer types over whatever is in the box, and clearing the box removes the figure. Rows are
# keyed by (fund, as_of_date, folio, name), so the same request creates or updates as needed.
class TieOutFiguresController < ApplicationController
  after_action :verify_authorized

  # POST /tie_out_figures
  # Replies with a Turbo Stream that replaces the one row, so typing a figure never re-runs the
  # report's aggregate passes over account_entries.
  def create
    @fund = policy_scope(Fund).find(params[:fund_id])
    # Fund-scoped: this run's end_date is the date the figure is filed under, so a run
    # belonging to another fund would file it against a date no sheet of this fund reads,
    # leaving a row the reviewer can neither see nor clear.
    @allocation_run = AllocationRun.find_by!(id: params[:allocation_run_id], fund_id: @fund.id)
    @name = params[:name].to_s

    @figure = TieOutFigure.find_or_initialize_by(
      fund_id: @fund.id, entity_id: @fund.entity_id, as_of_date: @allocation_run.end_date,
      capital_commitment_id: nil, name: @name, entry_type: nil
    )
    authorize @figure

    amount_cents = TieOutFigure.parse_amount_cents(params[:amount])

    if amount_cents.nil?
      # An empty box means "I have no figure for this", which is different from "my figure is
      # zero" — a fund's sheet may legitimately say 0.00 and that must read as a match.
      @figure.destroy if @figure.persisted?
      @figure = nil
    else
      @figure.assign_attributes(amount_cents: amount_cents, user: current_user)
      unless @figure.save
        @error = @figure.errors.full_messages.to_sentence
        # Redraw what is actually stored, not the rejected input: a row rebuilt from the
        # unsaved record reads as entered and tied out while nothing was written.
        @figure = @figure.persisted? ? @figure.reload : nil
      end
    end

    # The row is re-rendered from the system total the page already displayed, carried back in
    # the form, rather than by re-running AccountEntryReport's aggregate passes over
    # account_entries to recompute a number that has not changed. Nothing is stored from it —
    # it only decides what this one row draws — so a tampered value misleads nobody but the
    # person who tampered with it.
    @row = AllocationRunTieOut::Row.new(
      name: @name, system_cents: params[:system_cents].to_d,
      entry_count: params[:entry_count].to_i, figure: @figure
    )

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back_or_to fund_report_account_entry_reports_path(fund_id: @fund.id) }
    end
  end
end

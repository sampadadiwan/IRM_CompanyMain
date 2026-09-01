# frozen_string_literal: true

# Reply emails for the Deal Update Agent pipeline.
#
# Sends a confirmation reply when a Note or Task is successfully
# created from an inbound email. Warehoused emails do not get a
# reply — users check the warehouse tab on the deal page.
#
# These are direct replies to the sender — no CC, no entity-level routing.
# The From address uses the entity's from_email setting for consistency
# with other outbound mail.
#
# @see DealIngestProcessor for the orchestrator that triggers these
class DealIngestMailer < ApplicationMailer
  # Confirmation reply — a Note or Task was created on the deal board.
  #
  # Params:
  #   entity_id   [Integer] — for ApplicationMailer's setup_defaults
  #   user_id     [Integer] — the sender, for setup_defaults
  #   deal        [Deal]    — the deal this was filed on
  #   intent      [String]  — "meeting_note" or "task"
  #   stakeholder [String]  — matched investor name
  #   due_date    [String, nil] — task due date (nil for notes)
  #   body_preview [String] — first 100 chars of the filed body
  def confirmation
    @deal = params[:deal]
    @intent = params[:intent]
    @stakeholder = params[:stakeholder]
    @due_date = params[:due_date]
    @body_preview = params[:body_preview]&.truncate(100)
    @entity = Entity.find(params[:entity_id])

    item_type = @intent == "meeting_note" ? "Meeting Note" : "Task"
    subject = "✓ #{item_type} created on #{@deal.name} — #{@stakeholder}"

    mail(from: @from, to: @to, subject: subject)
  end
end

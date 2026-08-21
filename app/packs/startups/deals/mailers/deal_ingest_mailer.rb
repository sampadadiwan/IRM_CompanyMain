# frozen_string_literal: true

# Reply emails for the Deal Update Agent pipeline.
#
# Every authenticated inbound email gets exactly one reply:
#   - confirmation: a Note or Task was successfully created
#   - warehoused: the email couldn't be auto-filed and is awaiting manual review
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

  # Warehouse notification — the email couldn't be auto-filed.
  #
  # Params:
  #   entity_id   [Integer] — for ApplicationMailer's setup_defaults
  #   user_id     [Integer] — the sender, for setup_defaults
  #   deal        [Deal]    — the deal this was intended for
  #   reason      [String]  — why it was warehoused (e.g. "no stakeholder match")
  def warehoused
    @deal = params[:deal]
    @reason = params[:reason]
    @entity = Entity.find(params[:entity_id])

    subject = "⏳ Your update for #{@deal.name} needs manual review"

    mail(from: @from, to: @to, subject: subject)
  end
end

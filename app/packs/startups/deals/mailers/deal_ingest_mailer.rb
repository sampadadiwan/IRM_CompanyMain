# frozen_string_literal: true

# Reply emails for the Deal Update Agent pipeline.
#
# Sends two types of replies to the sender:
# - Confirmation: a Note or Task was successfully created from the email
# - Warehoused: the email couldn't be auto-filed and needs manual review
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

  # Warehoused reply — the email couldn't be auto-filed and is parked
  # for manual review on the deal's warehouse tab.
  #
  # Tells the sender why it was warehoused so they know what to expect:
  # - Unknown intent: the agent couldn't determine if it was a note or task
  # - Unmatched stakeholder: the investor name didn't match anyone on the deal
  #
  # @see DealIngestProcessor#warehouse! where this is triggered
  #
  # Params:
  #   entity_id      [Integer] — for ApplicationMailer's setup_defaults
  #   user_id        [Integer] — the sender, for setup_defaults
  #   deal           [Deal]    — the deal this email was sent to
  #   reason         [String]  — "unknown_intent" or "unmatched_stakeholder"
  #   body_preview   [String]  — first 100 chars of the email body
  #   stakeholder_string [String, nil] — the stakeholder name that couldn't be matched (nil for unknown intent)
  def warehoused
    @deal = params[:deal]
    @reason = params[:reason]
    @body_preview = params[:body_preview]&.truncate(100)
    @stakeholder_string = params[:stakeholder_string]
    @entity = Entity.find(params[:entity_id])

    subject = "⚠ Your update on #{@deal.name} needs review"

    mail(from: @from, to: @to, subject: subject)
  end
end

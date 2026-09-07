# frozen_string_literal: true

# Orchestrates the full processing of an authenticated deal ingest email.
#
# Called by ProcessDealIngestJob after the email has passed authentication.
# Chains: body cleanup → LLM parse → stakeholder match → create Note/Task (+ attachments) or warehouse → reply email (confirmation or warehoused reason).
# Each step updates the AgentIngestedEmail record with results as it goes,
# so we have a full audit trail even if processing fails midway.
#
# @see ProcessDealIngestJob for the async wrapper
# @see DealEmailParser for the LLM parsing step
# @see DealStakeholderMatcher for the stakeholder matching step
# @see EmailBodyCleaner for the signature/reply stripping step
# @see AssigneeMatcher for the @name assignee matching step
class DealIngestProcessor
  # Process a single authenticated email end-to-end.
  #
  # @param ingested_email_id [Integer] the AgentIngestedEmail record ID
  # @return [void]
  def self.call(ingested_email_id)
    new(ingested_email_id).process
  end

  def initialize(ingested_email_id)
    @email = AgentIngestedEmail.find(ingested_email_id)
    @deal = @email.deal
    @user = @email.sender_user
  end

  # Run all processing steps in sequence.
  # Rescues errors to mark the email as dropped rather than leaving it pending.
  #
  # @return [void]
  def process
    # Idempotency: only process emails still in "pending" status.
    # Prevents duplicate Notes/Tasks on Sidekiq retry.
    return if @email.reload.status != "pending"

    parsed = parse_email
    return warehouse!(parsed) if parsed["intent"] == "unknown"

    match_result = match_stakeholder(parsed)
    return warehouse!(parsed, match_result) unless match_result.matched

    create_item!(parsed, match_result)
  rescue StandardError => e
    Rails.logger.error { "DealIngestProcessor: failed for email ##{@email.id} — #{e.message}" }
    Rails.logger.error { e.backtrace&.first(5)&.join("\n") }
    @email.mark_dropped!
  end

  private

  # Step 1: Clean and parse the email body via LLM.
  # Strips signatures and quoted replies before parsing to avoid
  # wasting LLM tokens and prevent quoted text from confusing the parser.
  # Passes the email subject for subject/body stakeholder conflict detection.
  # Stores the parse result on the email record for audit trail.
  #
  # @return [Hash] parsed result with intent, stakeholder_string, subject_stakeholder_string, body, due_date
  def parse_email
    cleaned_body = EmailBodyCleaner.call(@email.raw_payload)

    parsed = DealEmailParser.call(
      email_body: cleaned_body,
      subject: @email.subject,
      entity: @deal.entity,
      received_at: @email.received_at
    )
    @email.store_parse_result!(parsed)
    parsed
  end

  # Step 2: Match the stakeholder string against the deal's investors.
  #
  # @param parsed [Hash] LLM parse result
  # @return [DealStakeholderMatcher::Result]
  def match_stakeholder(parsed)
    DealStakeholderMatcher.call(
      stakeholder_string: parsed["stakeholder_string"],
      deal: @deal
    )
  end

  # Step 3a: Confident match — create a Note or Task on the deal board.
  # Links the created record back to this email via the polymorphic
  # filed_as association on AgentIngestedEmail. For tasks, attaches any
  # email attachments as Documents via the WithFolder concern.
  #
  # @param parsed [Hash] LLM parse result
  # @param match_result [DealStakeholderMatcher::Result]
  # @return [void]
  def create_item!(parsed, match_result)
    deal_investor = match_result.deal_investor

    ActiveRecord::Base.transaction do
      item = case parsed["intent"]
             when "meeting_note"
               create_note!(parsed, deal_investor)
             when "task"
               create_task!(parsed, deal_investor)
             else
               raise ArgumentError, "Unexpected intent: #{parsed['intent']}"
             end

      @email.mark_filed!(
        confidence: match_result.confidence,
        match_tier: "A",
        filed_as: item
      )

      attach_documents!(item) if parsed["intent"] == "task"
    end

    send_confirmation_reply!(parsed, deal_investor)
  end

  # Create a Note on the matched DealInvestor.
  #
  # @param parsed [Hash] LLM parse result
  # @param deal_investor [DealInvestor] the matched stakeholder
  # @return [Note]
  def create_note!(parsed, deal_investor)
    Note.create!(
      entity_id: @deal.entity_id,
      user_id: @user.id,
      owner: deal_investor,
      details: parsed["body"],
      on: Date.current
    )
  end

  # Create a Task on the matched DealInvestor.
  # Attempts to match an assignee from the email body — falls back
  # to the sender if no confident match is found.
  #
  # @param parsed [Hash] LLM parse result
  # @param deal_investor [DealInvestor] the matched stakeholder
  # @return [Task]
  def create_task!(parsed, deal_investor)
    assignee = resolve_assignee(parsed) || @user

    Task.create!(
      entity_id: @deal.entity_id,
      for_entity_id: @deal.entity_id,
      user_id: @user.id,
      assigned_to: assignee,
      owner: deal_investor,
      details: parsed["body"],
      due_date: parse_due_date(parsed["due_date"])
    )
  end

  # Resolve the assignee from the parsed email.
  # Best-effort — returns nil if no match, caller falls back to sender.
  #
  # @param parsed [Hash] LLM parse result
  # @return [User, nil]
  def resolve_assignee(parsed)
    return nil if parsed["assignee_string"].blank?

    AssigneeMatcher.call(
      assignee_string: parsed["assignee_string"],
      deal: @deal
    )
  end

  # Step 3b: Low-confidence or unknown intent — park in the warehouse
  # for manual review. Sends a reply to the sender explaining why the
  # email couldn't be auto-filed.
  #
  # @param parsed [Hash] LLM parse result
  # @param match_result [DealStakeholderMatcher::Result, nil] nil for unknown intent
  # @return [void]
  def warehouse!(parsed, match_result = nil)
    candidate_ids = match_result&.candidates&.map { |c| c[:deal_investor].id } || []

    WarehouseItem.create!(
      agent_ingested_email: @email,
      deal: @deal,
      parsed_intent: parsed["intent"],
      candidate_stakeholder_ids: candidate_ids
    )

    @email.mark_warehoused!

    send_warehoused_reply!(parsed)
  end

  # Send a confirmation email to the sender with what was created.
  #
  # @param parsed [Hash] LLM parse result
  # @param deal_investor [DealInvestor] the matched stakeholder
  # @return [void]
  def send_confirmation_reply!(parsed, deal_investor)
    DealIngestMailer.with(
      entity_id: @deal.entity_id,
      user_id: @user.id,
      deal: @deal,
      intent: parsed["intent"],
      stakeholder: deal_investor.investor.investor_name,
      due_date: parsed["due_date"],
      body_preview: parsed["body"]
    ).confirmation.deliver_later
  end

  # Send a warehoused reply to the sender explaining why the email
  # couldn't be auto-filed. Two reasons:
  # - unknown_intent: the LLM couldn't determine note vs task
  # - unmatched_stakeholder: the stakeholder name didn't match any deal investor
  #
  # @param parsed [Hash] LLM parse result
  # @return [void]
  def send_warehoused_reply!(parsed)
    reason = parsed["intent"] == "unknown" ? "unknown_intent" : "unmatched_stakeholder"

    DealIngestMailer.with(
      entity_id: @deal.entity_id,
      user_id: @user.id,
      deal: @deal,
      reason: reason,
      body_preview: parsed["body"],
      stakeholder_string: parsed["stakeholder_string"]
    ).warehoused.deliver_later
  end

  # Parse a date string safely, returning nil for invalid dates.
  #
  # @param date_string [String, nil] ISO 8601 date string
  # @return [Date, nil]
  def parse_due_date(date_string)
    return nil if date_string.blank?

    Date.parse(date_string)
  rescue Date::Error
    nil
  end

  # Attach uploaded files from the inbound email to the created Task.
  # Documents are created via the polymorphic owner association provided
  # by WithFolder on Task. Shrine promotes files from cache to permanent
  # storage automatically.
  #
  # @param item [Task] the created task
  # @return [void]
  def attach_documents!(item)
    return if @email.attachment_data.blank?

    item.setup_document_folder

    @email.attachment_data.each do |file_meta|
      uploaded_file = Shrine.uploaded_file(file_meta["shrine_data"])
      doc = Document.new(
        entity_id: @deal.entity_id,
        user_id: @user.id,
        name: file_meta["filename"],
        owner: item,
        folder: item.document_folder,
        orignal: true
      )
      doc.file_attacher.set(uploaded_file)
      doc.save!
    end
  end
end

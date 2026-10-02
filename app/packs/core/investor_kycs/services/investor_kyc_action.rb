class InvestorKycAction < Trailblazer::Operation
  # Columns whose change is bookkeeping (status, verification and AI/AML results, timestamps), not
  # the KYC's details: changing only these after "Review KYC" does not move the journey back to it.
  # Worked examples E12 — openspec/changes/investor-kyc-journey/design.md#worked-examples
  JOURNEY_BOOKKEEPING_COLUMNS = %w[
    submission_status completed_by_investor verified verified_by_id submitted_at link_sent_at reminder_sent
    reminder_sent_date send_kyc_form_to_user pan_verified pan_verification_status pan_verification_response
    bank_verified bank_verification_status bank_verification_response aml_status aml_manual_override
    aml_override_reason doc_question_answers all_docs_valid docs_completed investor_user_updated_at
    notification_msg document_folder_id type investor_name updated_at created_at
  ].freeze

  def save(ctx, investor_kyc:, **)
    # Taken before anything changes, so sign-offs given before this save are reset if it moves the journey back
    ctx[:journey_started_at] = Time.current
    # We get this param validate to decide whether to validate or not, if the investor is doing an interim save validate is false, and he will complete the form later.
    validate = ctx[:validate].nil? ? ctx[:investor_user] : ctx[:validate]
    # If the KYC is verified, then its also completed by the investor
    investor_kyc.completed_by_investor = investor_kyc.verified if investor_kyc.verified
    # If a fund user explicitly flips completed_by_investor from true -> false, unlock the KYC for the investor again.
    # (Avoid forcing draft_saved on normal edits where completed_by_investor was already false.)
    if !ctx[:investor_user] && investor_kyc.completed_by_investor_was && !investor_kyc.completed_by_investor
      investor_kyc.submission_status = "draft_saved"
      investor_kyc.submitted_at = nil
    end
    # And the reverse: a fund user ticking "I confirm … complete" on a KYC they filled in marks it
    # submitted (until now the tick was reset by sync_boolean_fields_from_status and thrown away).
    # Worked examples H9 — openspec/changes/investor-kyc-journey/design.md#worked-examples
    if !ctx[:investor_user] && !investor_kyc.completed_by_investor_was && investor_kyc.completed_by_investor &&
       !(investor_kyc.submission_completed? || investor_kyc.submission_verified?)
      investor_kyc.submission_status = "completed"
      investor_kyc.submitted_at = Time.current
    end
    investor_kyc.save(validate:)
  end

  # Last step of create and update: tells the KYC's journey what this save did (a no-op without a
  # journey, and never fails the save). Moves back with the reason when the save undid something —
  # unverified (single or bulk), marked incomplete, or details edited after "Review KYC" — and
  # otherwise just re-checks (submitted, verified, imported, ...), so open pages update.
  # Worked examples H4, E11, E12, E16, E17 — openspec/changes/investor-kyc-journey/design.md#worked-examples
  def journey_hook(ctx, investor_kyc:, **)
    return true if investor_kyc.destroyed?

    changes = investor_kyc.saved_changes
    from_status, to_status = changes["submission_status"]
    actor = journey_actor
    started_at = ctx[:journey_started_at] || Time.current
    if from_status == "verified"
      investor_kyc.journey_undo_evaluate(note: "Unverified", started_at:, actor:)
    elsif %w[completed verified].include?(from_status) && %w[draft_saved link_sent not_sent].include?(to_status)
      investor_kyc.journey_undo_evaluate(note: "Marked incomplete", started_at:, actor:)
    elsif (changes.keys - JOURNEY_BOOKKEEPING_COLUMNS).any? && !investor_kyc.previously_new_record?
      investor_kyc.journey_invalidate(check_keys: "investor_kyc.review_kyc", reason: "KYC details changed after review",
                                      actor:, only_if_passed: "investor_kyc.review_kyc")
      investor_kyc.journey_undo_evaluate(note: "KYC details changed after review", started_at:, actor:)
    else
      investor_kyc.journey_progress!(actor:)
    end
    true
  end

  def handle_errors(ctx, investor_kyc:, **)
    unless investor_kyc.valid?
      ctx[:errors] = investor_kyc.errors.full_messages.join(", ")
      Rails.logger.error("Investor KYC errors: #{investor_kyc.errors.full_messages}")
    end
    investor_kyc.valid?
  end

  def fix_folder_paths(_ctx, investor_kyc:, **)
    document_folder = investor_kyc.document_folder
    parent_folder = document_folder.parent
    parent_folder.name = "KYC-#{investor_kyc.id}"
    path_parts = investor_kyc.folder_path.split("/")
    parent_folder.full_path = path_parts[0...-1].join("/")
    document_folder.owner = investor_kyc
    document_folder.save!
    parent_folder.save!
  end

  def validate_bank(_ctx, investor_kyc:, **)
    investor_kyc.validate_bank unless investor_kyc.destroyed?
    true
  end

  def validate_pan_card(_ctx, investor_kyc:, **)
    investor_kyc.validate_pan_card unless investor_kyc.destroyed?
    true
  end

  def enable_kyc(_ctx, investor_kyc:, **)
    investor_kyc.enable_kyc
    true
  end

  def send_kyc_form_on_create(_ctx, investor_kyc:, investor_user:, **)
    SendKycFormJob.perform_later(investor_kyc.id) if investor_kyc.send_kyc_form_to_user && !investor_user
    true
  end

  def send_kyc_form(_ctx, investor_kyc:, investor_user:, **)
    SendKycFormJob.perform_later(investor_kyc.id) if investor_kyc.saved_change_to_send_kyc_form_to_user? && investor_kyc.send_kyc_form_to_user && !investor_user
    true
  end

  # The signed-in user behind this request (audited's own lookup), nil in jobs and imports
  def journey_actor
    ::Audited.store[:audited_user] || ::Audited.store[:current_user].try(:call)
  rescue StandardError
    nil
  end

  def updated_notification(ctx, investor_kyc:, investor_user:, **)
    # reload the kyc in case it was changed from individual to non individual or visa versa
    validate = ctx[:validate].nil? ? ctx[:investor_user] : ctx[:validate]
    investor_kyc = InvestorKyc.find(investor_kyc.id)
    investor_kyc.updated_notification if investor_user && validate
    true
  end
end

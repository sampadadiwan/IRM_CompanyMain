# Polls IDFy (via AmlApiResponseService) for the result of an AML screening request and,
# once the report is ready, downloads the PDF and attaches it to the platform.
#
# Lifecycle / flow:
#   1. An AmlReport record is created elsewhere (e.g. when a fund manager triggers AML
#      screening for an InvestorKyc) and this job is enqueued with its id.
#   2. The job asks IDFy for the report status:
#        - "completed"   -> download the profile PDF, store it as a Document, update the
#                           AmlReport / InvestorKyc match statuses, and notify the user.
#        - "in_progress" -> re-enqueue itself to check again in 60 seconds (self-polling).
#        - anything else -> treat as failure and notify the user.
#   3. All user feedback is delivered as UserAlert broadcasts (the toast popups in the UI).
#      Note the user-facing wording says "Generated": from the user's perspective the
#      report was generated — the HTTP download from IDFy is an internal implementation
#      detail.
#
# Queueing notes:
#   - Runs on the :serial queue so report downloads don't compete with each other or
#     hammer the IDFy API in parallel.
#   - sidekiq retry is disabled (retry: 0) because the job manages its own retry loop for
#     the "in_progress" case; a hard error should surface once (alert + email) rather than
#     be retried blindly by Sidekiq.
class AmlReportAsyncDownloadJob < ApplicationJob
  queue_as :serial
  sidekiq_options retry: 0

  # @param aml_report_object_id [Integer] id of the AmlReport being polled
  # @param user_id [Integer, nil] user who triggered the screening; receives the
  #   success/failure alerts. May be nil for system-triggered runs, in which case
  #   no alerts are broadcast.
  def perform(aml_report_object_id, user_id)
    # Chewy.strategy(:sidekiq) defers Elasticsearch index updates (from the Document /
    # AmlReport / InvestorKyc writes below) to background index jobs instead of updating
    # the index inline.
    Chewy.strategy(:sidekiq) do
      aml_report = AmlReport.find(aml_report_object_id)
      json_res = AmlApiResponseService.new.get_report(aml_report)
      # The API returns an array of results; only the first entry is relevant here.
      json_res = json_res.first
      handle_report_status(json_res, aml_report, user_id)
    rescue StandardError => e
      handle_error(e, aml_report, user_id)
    end
  end

  private

  # Dispatches on the report status returned by IDFy.
  def handle_report_status(json_res, aml_report, user_id)
    case json_res['status']
    when 'completed'
      process_completed_report(json_res, aml_report, user_id)
    when 'in_progress'
      # Report generation is still running on IDFy's side — poll again in a minute.
      AmlReportAsyncDownloadJob.set(wait: 60.seconds).perform_later(aml_report.id, user_id)
    else
      # Unknown/failed status (e.g. "failed") — give up and tell the user.
      broadcast_failure(aml_report, user_id)
    end
  end

  # Handles a completed report: fetches the PDF, files it as a Document, and syncs the
  # AML match status onto the AmlReport and (conditionally) the InvestorKyc.
  def process_completed_report(json_res, aml_report, user_id)
    kyc = aml_report.investor_kyc
    # Prefer the report's custom name (used when screening someone other than the KYC's
    # primary holder, e.g. a joint holder or authorised signatory) over the KYC full name.
    name = kyc.full_name
    name = aml_report.custom_name if aml_report.custom_name.present?
    doc_name = "AML Report - #{name}"
    tmpfile = Tempfile.new([doc_name, '.pdf'])
    file_url = json_res.dig("result", "profile_pdf")
    if file_url.present?
      download_file(file_url, tmpfile)
      # File the PDF in the entity's document system, tagged "AML" and owned by the
      # AmlReport so it shows up alongside the KYC's compliance documents.
      Document.create(entity: aml_report.entity, owner: aml_report, name: doc_name, file: File.open(tmpfile.path, "rb"), folder: aml_report.document_folder, user_id: user_id, orignal: true, owner_tag: "AML")
      # User-facing wording: the report was "generated" (the download from IDFy is an internal step)
      UserAlert.new(user_id: user_id, message: "Generated AML Report for #{name}", level: :success).broadcast if user_id.present?
      # Persist IDFy's screening verdict (e.g. "Potential Match" / "No Match") on the report.
      aml_report.match_status = json_res.dig("result", "match_status")&.titleize
      aml_report.save
      # Propagate the verdict to the KYC's overall aml_status, but only when it wouldn't
      # clobber meaningful state:
      #   - Skip if the fund has manually overridden the status, so a fresh IDFy result
      #     doesn't silently revert their decision.
      #   - Otherwise update only when this report found a potential match, or when the
      #     KYC has no status yet (first screening).
      if !kyc.aml_manual_override? && (aml_report.match_status == "potential_match" || kyc.aml_status.blank?)
        started_at = Time.current
        kyc.assign_attributes(aml_status: aml_report.match_status)
        # validate: false — status sync must not be blocked by unrelated KYC validation errors.
        kyc.save(validate: false)
        # A new potential match reopens "Clear AML match"; anything else moves the journey on.
        # Worked examples H6, E7 — openspec/changes/investor-kyc-journey/design.md#worked-examples
        if kyc.aml_status.to_s.parameterize(separator: "_") == "potential_match"
          kyc.journey_undo_evaluate(note: "New AML result", started_at:)
        else
          kyc.journey_progress!
        end
      end
    elsif user_id.present?
      # Completed but no PDF URL in the payload — nothing to attach, report it as a failure.
      broadcast_failure(aml_report, user_id)
    end
  end

  # Streams the remote PDF to the tempfile in 1KB chunks so large reports are never
  # held fully in memory.
  def download_file(file_url, tmpfile)
    require 'open-uri'
    URI.parse(file_url).open do |file|
      File.open(tmpfile.path, 'wb') do |output|
        while (chunk = file.read(1024)) # Read 1KB chunks
          output.write(chunk)
        end
      end
    end
  end

  # Toast alert for the non-exception failure paths (bad status, missing PDF URL).
  def broadcast_failure(aml_report, user_id)
    name = aml_report.investor_kyc.full_name
    name = aml_report.custom_name if aml_report.custom_name.present?
    UserAlert.new(user_id: user_id, message: "Failed to generate AML Report for #{name}", level: :danger).broadcast if user_id.present?
  end

  # Exception path: log, alert the user, email the entity's doc-gen error report, and
  # re-raise so the failure is visible in Sidekiq (no retry — retry: 0 above).
  def handle_error(err, aml_report, user_id)
    name = aml_report.investor_kyc.full_name
    name = aml_report.custom_name if aml_report.custom_name.present?
    msg = "Failed to generate AML Report for #{name}: #{err.message}"
    Rails.logger.error msg
    UserAlert.new(user_id: user_id, message: msg, level: :danger).broadcast if user_id.present?
    errs = [{ investing_entity: aml_report.investor_kyc.full_name, aml_report_name: name, error: msg }]
    EntityMailer.with(entity_id: User.find(user_id).entity_id, user_id:, error_msg: errs).doc_gen_errors.deliver_now
    raise err
  end
end

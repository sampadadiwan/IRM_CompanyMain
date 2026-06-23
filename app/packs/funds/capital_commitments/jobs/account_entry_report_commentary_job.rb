class AccountEntryReportCommentaryJob < ApplicationJob
  queue_as :default

  def perform(fund_id, section_key, start_date, end_date, capital_commitment_id: nil, user_id: nil)
    fund = Fund.find(fund_id)
    capital_commitment = CapitalCommitment.find(capital_commitment_id) if capital_commitment_id
    # Job arguments are serialized to strings (ActiveJob/GlobalID); AccountEntryReport
    # does date arithmetic (trailing_trend's lookback), so these must be real Dates.
    start_date = start_date.to_date
    end_date = end_date.to_date

    insight = AccountEntryReportInsight.find_or_initialize_by(
      fund_id: fund.id, capital_commitment_id: capital_commitment&.id,
      start_date: start_date, end_date: end_date, section_key: section_key
    )
    insight.entity_id ||= fund.entity_id
    insight.status = "generating"
    insight.save!

    report = AccountEntryReport.new(fund: fund, capital_commitment: capital_commitment, start_date: start_date, end_date: end_date)
    fingerprint = AccountEntryReportInsight.fingerprint_for(report.scoped_entries)

    data = AccountEntryReportCommentaryService.generate(report: report, section_key: section_key, fund: fund, start_date: start_date, end_date: end_date, capital_commitment: capital_commitment)

    if data.nil?
      insight.with_lock do
        insight.update_columns(status: "error")
      end
      send_notification("AI commentary for \"#{AccountEntryReportCommentaryService::SECTION_LABELS.fetch(section_key)}\" failed to parse — please retry.", user_id, "danger")
      return
    end

    insight.with_lock do
      insight.update_columns(
        content: data,
        status: "complete",
        data_fingerprint: fingerprint,
        generated_at: Time.current,
        generated_by_id: user_id
      )
    end

    send_notification("AI commentary for \"#{AccountEntryReportCommentaryService::SECTION_LABELS.fetch(section_key)}\" is ready.", user_id)
  rescue ActiveRecord::RecordNotFound
    send_notification("AI commentary job skipped: fund or folio no longer exists.", user_id, "danger")
  rescue StandardError => e
    insight&.with_lock { insight.update_columns(status: "error") }
    send_notification("AI commentary generation failed: #{e.message}", user_id, "danger")
    raise
  end
end

class AccountEntryExplainJob < ApplicationJob
  queue_as :default

  # Fix: accept reporting_date so the notification link includes the partition key,
  # avoiding cross-partition scans on the show page.
  def perform(account_entry_id, user_id, reporting_date = nil)
    # Fix: discard gracefully when the record has been deleted rather than
    # retrying forever — RecordNotFound is rescued separately before the
    # generic StandardError rescue.
    account_entry = AccountEntry.find(account_entry_id)

    data = AccountEntryExplainerService.explain(account_entry)

    if data.nil?
      # Fix: use with_lock for the read-modify-write so concurrent jobs
      # cannot clobber each other's json_fields keys.
      account_entry.with_lock do
        account_entry.update_columns(
          json_fields: account_entry.json_fields.merge(
            "ai_explanation_status" => "error",
            "ai_explanation_data" => nil # Fix: clear stale data so UI is consistent
          )
        )
      end
      send_notification("AI explanation for \"#{account_entry.name}\" failed to parse — please retry.", user_id, "danger")
      return
    end

    account_entry.with_lock do
      account_entry.update_columns(
        json_fields: account_entry.json_fields.merge(
          "ai_explanation_data" => data,
          "ai_explanation_status" => "complete",
          "ai_explanation_at" => Time.current.iso8601
        )
      )
    end

    # Fix: include reporting_date in the notification link so set_account_entry
    # uses the partition-key fast path instead of a cross-partition find.
    date_param = reporting_date || account_entry.reporting_date
    send_notification(
      "AI explanation for \"#{account_entry.name}\" is ready. " \
      "<a href=\"/account_entries/#{account_entry_id}?reporting_date=#{date_param}\">View it here</a>",
      user_id
    )
  rescue ActiveRecord::RecordNotFound
    # Fix: record was deleted after enqueue — discard silently instead of retrying forever.
    send_notification(
      "AI explanation job skipped: account entry ##{account_entry_id} no longer exists.",
      user_id,
      "danger"
    )
    # Do not re-raise — let the job complete without retry.
  rescue StandardError => e
    account_entry = AccountEntry.find_by(id: account_entry_id)
    account_entry&.with_lock do
      account_entry.update_columns(
        json_fields: account_entry.json_fields.merge(
          "ai_explanation_status" => "error",
          "ai_explanation_data" => nil # Fix: clear stale data on error
        )
      )
    end
    send_notification(
      "AI explanation for account entry ##{account_entry_id} failed: #{e.message}",
      user_id,
      "danger"
    )
    raise
  end
end

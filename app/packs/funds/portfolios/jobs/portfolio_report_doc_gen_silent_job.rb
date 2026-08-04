# Runs the same doc generation as PortfolioReportDocGenJob but stays quiet: PortfolioReportJob
# runs one of these per company and needs a single batch notification at the end, not one toast
# and one error email per company. Errors are collected here and read back via #error_msg so the
# caller can fold them into its own summary.
class PortfolioReportDocGenSilentJob < PortfolioReportDocGenJob
  # Errors accumulated by DocGenJob#generate / #valid_inputs for this company.
  #
  # @return [Array<Hash>] Each entry is { msg:, model: }.
  def error_msg
    Array(@error_msg)
  end

  # Log only — no UserAlert broadcast, so the per-document progress and failure toasts stay out
  # of the user's way. This also silences send_errors_notification, which broadcasts through here.
  def send_notification(message, _user_id, level = "success")
    if level.to_s == "danger"
      Rails.logger.error { message }
    else
      Rails.logger.debug { message }
    end
  end

  # Skip the per-company error email and danger toast; PortfolioReportJob reports the batch.
  def completed(succeeded, failed, _user_id)
    Rails.logger.info { "#{self.class}: succeeded #{succeeded}, failed #{failed}" }
    @error_msg
  end
end

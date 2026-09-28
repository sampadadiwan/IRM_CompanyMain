# frozen_string_literal: true

# Sends an ops alert to the on-call phones on WhatsApp via WATI, and says whether WATI
# accepted it. Shared by GrafanaAlertsController (Grafana's webhook) and
# CriticalErrorWhatsapp (the app's own exception pager) so phone parsing and rejection
# detection cannot drift between the two paths.
module OpsWhatsappAlert
  # `result` is checked too because the older v1 endpoints in WhatsappGeneralNotification
  # use that key instead — cheap to accept both rather than depend on which one answered.
  FAILURE_RESULTS = %w[false failure failed error].freeze

  Result = Struct.new(:ok, :response, keyword_init: true) do
    def ok? = ok
  end

  class << self
    # Sends +message+ to every configured phone, using this environment's own WATI account
    # and phones (IN and US are independent). +link+ is a path appended to the template's
    # fixed button URL — never a hostname.
    def deliver(message, title:, link:, broadcast_name:, phones: configured_phones)
      response = WhatsappGeneralNotification.send_template_message(
        {
          recipients: phones.map do |phone|
            {
              phone_number: phone,
              custom_params: [
                { name: '1',            value: title },
                { name: 'notification', value: sanitize(message).truncate(1000) },
                { name: 'link',         value: link }
              ]
            }
          end
        },
        template_name: ENV.fetch('CAPHIVE_NOTIFICATION', 'caphive_notification_6'),
        broadcast_name: broadcast_name
      )
      Result.new(ok: accepted?(response), response: response)
    end

    # Positive confirmation, not just the absence of a known failure shape:
    # WhatsappGeneralNotification.parse_response returns the JSON body whatever the HTTP
    # status, so a WATI 401/429/5xx answering {"message" => "Unauthorized"} carries none of
    # the keys delivery_failed? looks for and would read as delivered. Every accepted v3
    # messageTemplates/send response has "success" => true (see below).
    def accepted?(response)
      response.is_a?(Hash) && response['success'] == true && !delivery_failed?(response)
    end

    # WATI reports a rejected template send inside a 200 body rather than via HTTP status.
    # The confirmed v3 messageTemplates/send shape, from a live production call:
    #
    #   {"success" => true,
    #    "broadcast_id" => "6a8037d8...",
    #    "recipients" => [{"local_message_id" => "...", "phone_number" => "917721046692",
    #                      "target" => "917721046692", "errors" => []}]}
    #
    # NOTE: success == true means WATI ACCEPTED the broadcast, not that WhatsApp delivered it.
    # Meta can still reject the message downstream (e.g. an unapproved template, or a
    # parameter value containing newlines/tabs/4+ spaces) after this call has returned 200.
    # Final delivery state is only visible in the WATI dashboard or via its status webhooks,
    # so a clean response here rules out API-level rejection and nothing more.
    def delivery_failed?(response)
      # Non-Hash means the transport helper returned something unexpected; the caller logs it.
      return false unless response.is_a?(Hash)

      # WhatsappGeneralNotification.parse_response returns {"error" => "non_json_response"}
      # when WATI answers with HTML (auth failure, gateway error) — caught here too.
      return true if response['error'].present?
      return true if response['errors'].is_a?(Hash) && response.dig('errors', 'error').present?

      # v3 top-level accept/reject flag.
      return true if response['success'] == false
      # v1-style flag, for whichever endpoint answered.
      return true if response['result'] == false
      return true if response['result'].is_a?(String) && FAILURE_RESULTS.include?(response['result'].downcase)

      # Per-recipient rejections: the broadcast can be accepted overall while individual
      # numbers are refused (invalid number, no opt-in), so one bad phone in the batch must
      # not read as a clean send for the whole alert.
      recipients = response['recipients']
      recipients.is_a?(Array) && recipients.any? { |r| r.is_a?(Hash) && Array(r['errors']).any? }
    end

    # Alert recipients, normalised to the bare-digit E.164 form WATI insists on.
    #
    # The credential is hand-maintained ops config, so it drifts from the documented
    # "comma-separated, E.164 without +" format: a leading '+', a space between the country
    # code and the number, a dash, or a trailing newline from an editor all creep in. WATI
    # answers any of those with `{"success" => false, "error" => "There are no valid
    # Receivers", "recipients" => []}` — it rejects the whole broadcast rather than the one
    # malformed entry, so a single stray character silences every alert. Stripping to digits
    # here makes the senders tolerant of the formats a human would reasonably type.
    #
    # No length validation here on purpose. A malformed entry is already loud: WATI refuses
    # it and delivery_failed? catches the refusal. Re-checking the length locally would
    # only reword that error.
    def configured_phones
      configured = Rails.application.credentials[:grafana_alert_phones]
      # A YAML list is the safer shape — each number is its own element, so there is no
      # separator to drop. The CSV string is still accepted for the existing config.
      raw = configured.is_a?(Array) ? configured : configured.to_s.split(',')

      raw.filter_map do |entry|
        digits = entry.to_s.gsub(/\D/, '')
        digits unless digits.empty?
      end
    end

    # Last 4 digits only — enough to identify which number was refused when reading logs,
    # without writing ops staff's full numbers into production.log.
    def mask_phones(phones)
      phones.map { |p| "***#{p.last(4)}" }.join(',')
    end

    # WhatsApp rejects template PARAMETER values that contain newlines, tabs, or runs of 4+
    # spaces — the template body may have line breaks, but the variables spliced into it
    # may not. Collapse every whitespace run to a single space.
    def sanitize(text)
      text.to_s.gsub(/\s+/, ' ').strip
    end
  end
end

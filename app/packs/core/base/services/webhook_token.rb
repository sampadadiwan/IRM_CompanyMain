# frozen_string_literal: true

# Shared-secret check for provider webhooks that cannot sign their posts: WATI (WhatsApp) and the
# Digio / DocuSign branches of DocumentsController#signature_progress.
#
# Each environment has its own secret in its own credentials (whatsapp.webhook_token,
# esign.webhook_token — IN and US never share one), and ops put it in the callback URL they
# configure in that provider's dashboard as `?webhook_token=<secret>`. Rails' parameter filter
# (`token`) keeps it out of the request log.
#
# Follows the Zoho pattern (ZohoEsignHelper.verify_signature): with no secret configured, posts are
# accepted only in development and test. Refusal is switched on per environment by
# WEBHOOK_TOKEN_ENFORCE=1, so a deploy changes nothing until ops have reconfigured every provider
# dashboard; until then a post without the right token is accepted and logged, which is how ops
# see which dashboards still need the new URL.
#
# docs/security/security_review_2026_10.md "Authentication and session — Medium / Low", M1.
class WebhookToken
  ENFORCE_ENV = "WEBHOOK_TOKEN_ENFORCE"

  # @param presented [String, nil] the ?webhook_token= the provider sent
  # @param expected [String, nil] this environment's secret for that provider
  # @param source [String] which webhook, for the log line
  # @return [Boolean] whether the post may be applied
  def self.accept?(presented, expected, source:)
    # M1-H — the right token is accepted everywhere
    return true if expected.present? && presented.present? &&
                   ActiveSupport::SecurityUtils.secure_compare(presented.to_s, expected.to_s)

    # M1-E — no secret configured in development/test: accepted, as the Zoho webhook is
    return true if expected.blank? && Rails.env.local?

    reason = if expected.blank? then "no webhook token configured for this environment"
             elsif presented.blank? then "no webhook_token in the callback URL"
             else "wrong webhook_token"
             end
    accept_unauthenticated?(source, reason)
  end

  # Logs a failed check and answers whether the post is still accepted: refused only once ops have
  # switched enforcement on (M1-1, M1-2, M1-3); before that it is accepted, so production behaves
  # as it did (M1-E).
  # @return [Boolean] true to accept, false to refuse
  def self.accept_unauthenticated?(source, reason)
    if enforced?
      Rails.logger.warn("[WebhookToken] #{source} refused: #{reason}")
      false
    else
      Rails.logger.warn("[WebhookToken] #{source} accepted without authentication (#{reason}); " \
                        "set #{ENFORCE_ENV}=1 once the provider's callback URL carries the token")
      true
    end
  end

  def self.enforced?
    ENV[ENFORCE_ENV] == "1"
  end
end

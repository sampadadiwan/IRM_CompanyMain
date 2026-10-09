class KycDocExtractorJob < ApplicationJob
  queue_as :default

  # How long a finished extraction's redirect URL waits for the processing page to pick it up.
  REDIRECT_TTL = 1.hour.to_i

  # The "extraction done" marker lives in Redis (via Sidekiq's connection pool) because it
  # is written by the Sidekiq process and read by Puma. Neither process memory nor
  # Rails.cache works for that: dev/test run Rails.cache as :null_store, which drops writes.
  # The key carries TEST_ENV_NUMBER so parallel cucumber workers (each with its own DB but
  # overlapping KYC ids) never read each other's markers.
  def self.redirect_key(kyc_id)
    "kyc_extraction_done:#{Rails.env}#{ENV.fetch('TEST_ENV_NUMBER', nil)}:#{kyc_id}"
  end

  def self.store_redirect(kyc_id, url)
    Sidekiq.redis { |r| r.call("SET", redirect_key(kyc_id), url, "EX", REDIRECT_TTL) }
  end

  # Returns the stored redirect URL (or nil) and deletes it, so each completion redirects once.
  # GET + DEL rather than GETDEL: GETDEL needs Redis >= 6.2, and a double read is harmless.
  def self.consume_redirect(kyc_id)
    key = redirect_key(kyc_id)
    Sidekiq.redis do |r|
      url = r.call("GET", key)
      r.call("DEL", key) if url
      url
    end
  end

  # Drops a marker left by an earlier run that nobody consumed (e.g. the tab was closed),
  # so a fresh upload does not skip straight past the processing page.
  def self.clear_redirect(kyc_id)
    Sidekiq.redis { |r| r.call("DEL", redirect_key(kyc_id)) }
  end

  def perform(investor_kyc_id, support_agent_id, redirect_url)
    investor_kyc = InvestorKyc.find(investor_kyc_id)
    investor_kyc.reload # ensure committed documents are visible

    KycDocExtractorAgent.call(support_agent_id: support_agent_id, target: investor_kyc)
  rescue StandardError => e
    Rails.logger.error("[KycDocExtractorJob] Extraction failed for KYC #{investor_kyc_id}: #{e.message}")
  ensure
    # Durable marker first: the processing page polls for it, which covers the job finishing
    # before the page's Turbo Stream subscription is open (the broadcast below is then lost).
    self.class.store_redirect(investor_kyc_id, redirect_url)

    # Fast path: an already-subscribed processing page redirects as soon as this arrives.
    Turbo::StreamsChannel.broadcast_replace_to(
      "kyc_extraction_#{investor_kyc_id}",
      target: "extraction_processing",
      html: %(<div id="extraction_processing"
                   data-controller="extraction-redirect"
                   data-extraction-redirect-url-value="#{redirect_url}"></div>)
    )
  end
end

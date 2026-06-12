class KycDocExtractorJob < ApplicationJob
  queue_as :default

  # In-process store for the redirect URL written in the job's ensure block.
  # Used when Rails.cache is :null_store (test env) and the inline adapter runs the job
  # synchronously in the same Puma process before the browser reaches the processing page.
  # Keyed by investor_kyc_id (string); entries are consumed (deleted) on first read.
  # rubocop:disable Style/MutableConstant
  PENDING_REDIRECTS = {}
  PENDING_REDIRECTS_MUTEX = Mutex.new
  # rubocop:enable Style/MutableConstant

  def self.store_redirect(kyc_id, url)
    PENDING_REDIRECTS_MUTEX.synchronize { PENDING_REDIRECTS[kyc_id.to_s] = url }
  end

  def self.consume_redirect(kyc_id)
    PENDING_REDIRECTS_MUTEX.synchronize { PENDING_REDIRECTS.delete(kyc_id.to_s) }
  end

  def perform(investor_kyc_id, support_agent_id, redirect_url)
    investor_kyc = InvestorKyc.find(investor_kyc_id)
    investor_kyc.reload # ensure committed documents are visible

    KycDocExtractorAgent.call(support_agent_id: support_agent_id, target: investor_kyc)
  rescue StandardError => e
    Rails.logger.error("[KycDocExtractorJob] Extraction failed for KYC #{investor_kyc_id}: #{e.message}")
  ensure
    # In-process store (works even when Rails.cache is :null_store in test).
    self.class.store_redirect(investor_kyc_id, redirect_url)

    # Also write to Rails.cache for production environments with a real cache store.
    Rails.cache.write("kyc_extraction_done_#{investor_kyc_id}", redirect_url, expires_in: 1.hour)

    # Also broadcast via Turbo Streams for real-time redirect in production
    Turbo::StreamsChannel.broadcast_replace_to(
      "kyc_extraction_#{investor_kyc_id}",
      target: "extraction_processing",
      html: %(<div id="extraction_processing"
                   data-controller="extraction-redirect"
                   data-extraction-redirect-url-value="#{redirect_url}"></div>)
    )
  end
end

# features/support/sync_api_stub.rb
require "digest"

module SyncApiStub
  def stub_sync_upsert_for(region, status: 200, &block)
    base = ENV.fetch("SYNC_API_BASE_URL_#{region}")
    url  = "#{base}/internal/sync/users"

    WebMock::API.stub_request(:post, url).with { |req|
      ts   = req.headers["X-Timestamp"].to_s
      body = req.body.to_s
      origin_region = req.headers["X-Region"] || "IN"
      secret = Rails.application.credentials.CROSS_INSTANCE_SECRET rescue nil

      data = "POST\n/internal/sync/users\n#{ts}\n#{Digest::SHA256.hexdigest(body)}"
      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, data)

      raise "Bad HMAC for region #{origin_region}" unless req.headers["X-Signature"] == expected

      block.call(JSON.parse(body)) if block
      true
    }.to_return(status: status, body: '{"ok":true}', headers: { "Content-Type" => "application/json" })
  end

  def stub_sync_disable_for(region, status: 200, &block)
    base = ENV.fetch("SYNC_API_BASE_URL_#{region}")
    url  = "#{base}/internal/sync/users/disable"

    WebMock::API.stub_request(:post, url).with { |req|
      ts   = req.headers["X-Timestamp"].to_s
      body = req.body.to_s
      origin_region = req.headers["X-Region"] || "IN"
      secret = Rails.application.credentials.CROSS_INSTANCE_SECRET rescue nil

      data = "POST\n/internal/sync/users/disable\n#{ts}\n#{Digest::SHA256.hexdigest(body)}"
      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, data)

      raise "Bad HMAC for region #{origin_region}" unless req.headers["X-Signature"] == expected

      block.call(JSON.parse(body)) if block
      true
    }.to_return(status: status, body: '{"ok":true}', headers: { "Content-Type" => "application/json" })
  end
end

World(SyncApiStub)

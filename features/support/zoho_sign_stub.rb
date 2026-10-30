# Fake Zoho Sign for @zoho-http scenarios: answers every Zoho accounts and Sign API address (all
# regions) through WebMock, keeps the request's state between calls, records each call, and can be
# told to fail a call. Steps reach it through `zoho_fake`.
class ZohoSignFake
  PDF = Rails.public_path.join("sample_uploads/rta_demo_fund_11_success.pdf").binread.freeze
  REQUEST_ID = "3z10c1234567890zoho".freeze
  ACCOUNTS = %r{\Ahttps://accounts\.zoho(?:cloud)?\.[a-z.]+/oauth/v2/token}
  SIGN = %r{\Ahttps://sign\.zoho(?:cloud)?\.[a-z.]+/api/v1/requests}
  JSON_HEADERS = { "Content-Type" => "application/json;charset=UTF-8" }.freeze

  Call = Data.define(:op, :verb, :host, :path, :query, :body)

  attr_accessor :request_status, :expire_by, :request_id
  attr_reader :calls, :actions

  def initialize
    @calls = []
    @failures = {}
    @actions = []
    @request_status = "inprogress"
    @request_id = REQUEST_ID
    @tokens = 0
  end

  def install
    WebMock.stub_request(:post, ACCOUNTS).to_return { |req| respond(:token, req) }
    WebMock.stub_request(:any, SIGN).to_return { |req| respond(sign_op(req), req) }
    self
  end

  # Signers as Zoho reports them: [{ email:, action_id:, status: }]
  def signers=(signers)
    @actions = signers.map { |s| { "action_id" => s[:action_id].to_s, "recipient_email" => s[:email], "action_status" => s[:status] || "UNOPENED" } }
  end

  def signer_status(email, status)
    @actions.find { |a| a["recipient_email"] == email }&.store("action_status", status)
  end

  # status: HTTP status with Zoho's error body; timeout: true raises Net::OpenTimeout;
  # error: an OAuth error code ("invalid_code") on the token endpoint.
  def refuse(op, status: 400, message: "Zoho refused the request", timeout: false, error: nil, times: nil)
    @failures[op] = { status:, message:, timeout:, error:, times: }
  end

  def heal(op)
    @failures.delete(op)
  end

  def calls_to(op)
    calls.select { |c| c.op == op }
  end

  def created_data
    calls_to(:create).last&.body
  end

  def submitted_actions
    calls_to(:submit).last&.body&.dig("requests", "actions")
  end

  private

  def respond(op, req)
    body = parse_body(op, req)
    calls << Call.new(op:, verb: req.method, host: req.uri.host, path: req.uri.path, query: req.uri.query_values || {}, body:)
    failure = take_failure(op)
    return failed(op, failure) if failure

    send(:"#{op}_response", req, body)
  end

  def take_failure(op)
    failure = @failures[op]
    return unless failure

    failure[:times] -= 1 if failure[:times]
    @failures.delete(op) if failure[:times]&.zero?
    failure
  end

  def failed(op, failure)
    raise Net::OpenTimeout, "execution expired" if failure[:timeout]
    return json({ error: failure[:error] }) if op == :token && failure[:error]

    json({ code: 4000, status: "failure", message: failure[:message] }, http: failure[:status])
  end

  def sign_op(req)
    path = req.uri.path
    case [req.method, path]
    in [:post, %r{/api/v1/requests\z}] then :create
    in [:get, %r{/api/v1/requests\z}] then :list
    in [:post, %r{/submit\z}] then :submit
    in [:get, %r{/completioncertificate\z}] then :certificate
    in [:get, %r{/pdf\z}] then :pdf
    in [:post | :put, %r{/(recall|remind|extend|delete)\z}] then ::Regexp.last_match(1).to_sym
    in [:get, _] then :get
    end
  end

  def parse_body(op, req)
    case op
    when :create then JSON.parse(req.body[/name="data"\r\n\r\n(.*?)\r\n--/m, 1].to_s)
    when :submit then JSON.parse(Rack::Utils.parse_nested_query(req.body)["data"].to_s)
    when :extend then Rack::Utils.parse_nested_query(req.body)
    when :token then req.uri.query_values
    end
  rescue JSON::ParserError
    nil
  end

  def token_response(_req, query)
    @tokens += 1
    tokens = { access_token: "zoho-access-#{@tokens}", expires_in: 3600 }
    tokens[:refresh_token] = "zoho-refresh-#{@tokens}" if query&.dig("grant_type") == "authorization_code"
    json(tokens)
  end

  def create_response(_req, data)
    self.signers = Array(data&.dig("requests", "actions")).each_with_index.map do |action, idx|
      { email: action["recipient_email"], action_id: 9_000 + idx, status: "UNOPENED" }
    end
    json(status: "success", requests: { request_id:, document_ids: [{ document_id: "#{request_id}-doc" }],
                                        actions: @actions.map { |a| a.merge("action_type" => "SIGN", "signing_order" => 0, "verify_recipient" => false) } })
  end

  def submit_response(_req, _body)
    json(status: "success", requests: { request_id:, request_status: "inprogress" })
  end

  def get_response(_req, _body)
    requests = { request_id:, request_status:, actions: @actions }
    requests[:expire_by] = expire_by.to_i * 1000 if expire_by
    json(status: "success", requests:)
  end

  def list_response(_req, _body) = json(status: "success", requests: [])
  def recall_response(_req, _body) = json(status: "success", message: "Document recalled")
  def remind_response(_req, _body) = json(status: "success", message: "Reminder sent")
  def extend_response(_req, _body) = json(status: "success", message: "Expiry extended")
  def delete_response(_req, _body) = json(status: "success", message: "Document deleted")
  def pdf_response(_req, _body) = { status: 200, body: PDF, headers: { "Content-Type" => "application/pdf" } }
  def certificate_response(_req, _body) = { status: 200, body: PDF, headers: { "Content-Type" => "application/pdf" } }

  def json(body = nil, http: 200, **fields)
    { status: http, body: (body || fields).to_json, headers: JSON_HEADERS }
  end
end

module ZohoSignFakeWorld
  def zoho_fake
    @zoho_fake ||= ZohoSignFake.new.install
  end

  # A Zoho webhook POST, signed with secret (or unsigned when secret is nil), to path.
  def zoho_signed_post(path, payload, secret)
    Capybara.current_session # boots the app server when no page has been visited yet
    body = payload.is_a?(String) ? payload : payload.to_json
    headers = { "Content-Type" => "application/json" }
    headers["X-ZS-WEBHOOK-SIGNATURE"] = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", secret, body)) if secret
    uri = URI.parse("#{Capybara.app_host}#{path}")
    request = Net::HTTP::Post.new(uri.path, headers)
    request.body = body
    @webhook_response = Net::HTTP.new(uri.host, uri.port).request(request)
  end
end

World(ZohoSignFakeWorld)

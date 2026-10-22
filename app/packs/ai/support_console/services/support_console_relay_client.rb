# frozen_string_literal: true

require "net/http"
require "openssl"

# Talks to the relay on the support machine: starts a turn and streams its events back, stops a
# running turn, and deletes a transcript.
#
# Every request is signed: X-Signature = hex(HMAC-SHA256(secret, "<ts>.<METHOD>.<path>.<body>"))
# with X-Timestamp = <ts> (unix seconds). The relay rejects bad signatures and timestamps more
# than 60 s off (X6, X8). The response to a turn is NDJSON, one event object per line.
#
# @see openspec/changes/archive/2026-10-22-support-console/lld.md (External Integrations)
class SupportConsoleRelayClient
  class Error < StandardError; end
  # Connection refused, DNS failure, 401, 5xx — X4, X5.
  class Unavailable < Error; end
  # 409: a turn is already running for this conversation — E11.
  class Busy < Error; end
  # Nothing arrived for IDLE_TIMEOUT, or the whole turn passed TOTAL_TIMEOUT — X7.
  class Timeout < Error; end

  OPEN_TIMEOUT = 5
  IDLE_TIMEOUT = 120
  TOTAL_TIMEOUT = 15 * 60
  MACHINE_ENV_FILE = "tmp/support_console/machine.env"

  # @return [String, nil] the relay's base URL for this environment: SUPPORT_CONSOLE_RELAY_URL when set
  #   (local mode, or a manual override — E37), else found from the machine's private IP (H12)
  def self.url
    configured_url || SupportConsoleMachineControl.relay_url
  end

  # @return [String, nil] a relay URL set by hand, rather than found
  def self.configured_url
    ENV["SUPPORT_CONSOLE_RELAY_URL"].presence ||
      Rails.application.credentials[:SUPPORT_CONSOLE_RELAY_URL].presence ||
      local_machine_env["SUPPORT_CONSOLE_RELAY_URL"].presence
  end

  # @return [String, nil] the HMAC secret shared with this environment's relay
  def self.secret
    ENV["SUPPORT_CONSOLE_RELAY_SECRET"].presence ||
      Rails.application.credentials[:SUPPORT_CONSOLE_RELAY_SECRET].presence ||
      local_machine_env["SUPPORT_CONSOLE_RELAY_SECRET"]
  end

  # @return [Boolean] whether this environment has a relay at all. The secret is checked first, so an
  #   environment without one never asks EC2.
  def self.configured?
    secret.present? && url.present?
  end

  # Local mode only: `rake support_console:local_setup` writes the relay URL and secret to
  # tmp/support_console/machine.env, read here in development when nothing else is set.
  #
  # @return [Hash{String => String}]
  def self.local_machine_env
    return {} unless Rails.env.development?

    path = Rails.root.join(MACHINE_ENV_FILE)
    return {} unless path.exist?

    # KEY=VALUE per line; comments and blank lines ignored.
    path.readlines(chomp: true).each_with_object({}) do |line, env|
      next if line.blank? || line.start_with?("#")

      key, value = line.split("=", 2)
      env[key.strip] = value.to_s.strip
    end
  end

  # Starts a turn and yields each event the relay streams back.
  #
  # @param request [Hash] session_key, entity_id, question, resume_id, brief
  # @yieldparam event [Hash] one parsed NDJSON line
  # @return [void]
  # @raise [Unavailable, Busy, Timeout]
  def post_turn(request, &)
    deadline = monotonic_now + TOTAL_TIMEOUT
    body = request.to_json

    perform(Net::HTTP::Post, "/turns", body) do |response|
      # H1 — 200 starts the stream; E11 — 409 means a turn is already running; X5 — anything else.
      case response.code.to_i
      when 200 then nil
      when 409 then raise Busy, "a turn is already running for #{request[:session_key]}"
      else raise Unavailable, "relay answered #{response.code}"
      end

      read_events(response, deadline, &)
    end
  end

  # Stops the running turn of a conversation. A 404 means it already finished.
  #
  # @param session_key [String]
  # @return [true]
  def stop(session_key)
    perform(Net::HTTP::Delete, "/turns/current", { session_key: session_key }.to_json) do |response|
      raise Unavailable, "relay answered #{response.code}" unless [200, 204, 404].include?(response.code.to_i)
    end
    true
  end

  # Deletes a conversation's transcript on the machine. A 404 means it is already gone.
  #
  # @param entity_id [Integer]
  # @param claude_session_id [String]
  # @return [true]
  def delete_transcript(entity_id, claude_session_id)
    body = { entity_id: entity_id, claude_session_id: claude_session_id }.to_json
    perform(Net::HTTP::Delete, "/transcripts", body) do |response|
      raise Unavailable, "relay answered #{response.code}" unless [200, 204, 404].include?(response.code.to_i)
    end
    true
  end

  private

  # Opens a signed request and yields the response while its body is still unread.
  def perform(verb, path, body, &)
    raise Unavailable, "Support Console relay is not configured" unless self.class.configured?

    uri = URI.join(self.class.url, path)
    request = verb.new(uri, signed_headers(verb::METHOD, uri.path, body))
    request.body = body

    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                        open_timeout: OPEN_TIMEOUT, read_timeout: IDLE_TIMEOUT) do |http|
      http.request(request, &)
    end
  rescue Net::ReadTimeout
    # X7 — the stream went quiet for IDLE_TIMEOUT.
    raise Timeout, "no events for #{IDLE_TIMEOUT} s"
  rescue Net::OpenTimeout, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError => e
    # X4 — the machine cannot be reached. E38 — a found address may be stale (machine recreated).
    SupportConsoleMachineControl.forget_relay_url! unless self.class.configured_url
    raise Unavailable, "#{e.class}: #{e.message}"
  end

  # Splits the streamed body into NDJSON lines and yields each parsed event.
  def read_events(response, deadline)
    buffer = +""
    response.read_body do |chunk|
      # X7 — the whole turn ran past TOTAL_TIMEOUT.
      raise Timeout, "turn exceeded #{TOTAL_TIMEOUT} s" if monotonic_now > deadline

      buffer << chunk
      while (line = buffer.slice!(/\A[^\n]*\n/))
        yield JSON.parse(line) if line.strip.present?
      end
    end
    yield JSON.parse(buffer) if buffer.strip.present?
  end

  # @return [Hash] the signature headers
  def signed_headers(method, path, body)
    timestamp = Time.now.to_i.to_s
    signature = OpenSSL::HMAC.hexdigest("SHA256", self.class.secret, "#{timestamp}.#{method}.#{path}.#{body}")
    { "Content-Type" => "application/json", "X-Timestamp" => timestamp, "X-Signature" => signature }
  end

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end

# frozen_string_literal: true

require "aws-sdk-ec2"
require "net/http"

# Starts, stops and reports on this environment's support machine, from the app.
#
# The machine is found through the relay address the app already talks to
# (SUPPORT_CONSOLE_RELAY_URL), so an environment can only ever reach its own machine. It is
# stopped and started, never terminated: a stopped instance keeps its private IP, which the
# relay URL and the 'support_ro'@'<IP>' account are both tied to.
#
# Same client set-up as DbRestoreService: the app's own AWS keys and AWS_REGION.
#
# @see openspec/changes/support-console/design.md (card ⑨ Machine control)
class SupportConsoleMachineControl
  NAME_PREFIX = "irm-support-console-"
  # How long a start may take before the machine is reported as not coming up
  START_TIMEOUT = 5.minutes
  POLL_INTERVAL = 10.seconds
  HEALTH_TIMEOUT = 3
  LIVE_TURN = %w[queued running].freeze

  class << self
    # @return [String] running | starting | stopping | stopped | unknown
    def status
      # EC2 first: a stopped machine's IP does not answer at all, so /health would sit out its timeout
      case instance&.state&.name
      # Running at EC2 but the relay not answering yet: still booting
      when "running" then healthy? ? "running" : "starting"
      when "pending" then "starting"
      when "stopping" then "stopping"
      when "stopped" then "stopped"
      # No machine found, or AWS not reachable from here (local mode): the relay alone decides
      else healthy? ? "running" : "unknown"
      end
    end

    # @return [Boolean] whether the relay answers /health — what "able to answer a question" means
    def healthy?
      url = SupportConsoleRelayClient.url
      return false if url.blank?

      uri = URI.join(url, "/health")
      Net::HTTP.start(uri.host, uri.port, open_timeout: HEALTH_TIMEOUT, read_timeout: HEALTH_TIMEOUT) do |http|
        http.get(uri.path).code.to_i == 200
      end
    rescue StandardError
      false
    end

    # @return [Boolean] whether a start was sent (false when it was already up or coming up)
    def start!(user:, reason:)
      found = instance
      return false unless found&.state&.name == "stopped"

      ec2.start_instances(instance_ids: [found.instance_id])
      Rails.logger.info("[support_console] machine #{found.instance_id} started by user=#{user&.id || '-'} (#{reason})")
      true
    end

    # @return [Boolean] whether a stop was sent
    def stop!(user:, reason:)
      found = instance
      return false unless found&.state&.name == "running"

      ec2.stop_instances(instance_ids: [found.instance_id])
      Rails.logger.info("[support_console] machine #{found.instance_id} stopped by user=#{user&.id || '-'} (#{reason})")
      true
    end

    # Waits until the relay answers, or START_TIMEOUT passes.
    #
    # @return [Boolean] whether it came up
    def wait_until_healthy
      deadline = Time.current + START_TIMEOUT
      loop do
        return true if healthy?
        return false if Time.current > deadline

        sleep POLL_INTERVAL
      end
    end

    # Refreshes the machine badge on every open console page (one stream for all: it holds no client data).
    def broadcast_status(status = self.status)
      Turbo::StreamsChannel.broadcast_replace_to(:support_console_machine, target: "support-console-machine",
                                                                           partial: "support_console/machine",
                                                                           locals: { status: status })
    rescue StandardError => e
      Rails.logger.warn("[support_console] machine badge broadcast failed: #{e.class}: #{e.message}")
    end

    # @return [Integer] turns queued or running now, across all clients — what a stop would cut off
    def running_turns_count
      agent = SupportConsoleAgent.existing
      return 0 unless agent

      # Only the last STALE_TURN can hold a live turn; the rest were closed or swept
      AgentChatMessage.joins(:agent_chat_session)
                      .where(agent_chat_sessions: { support_agent_id: agent.id }, role: "assistant")
                      .where(created_at: SupportConsoleRetentionJob::STALE_TURN.ago..)
                      .select(:id, :metadata, :created_at).to_a
                      .count { |m| LIVE_TURN.include?(m.metadata&.dig("turn_status")) && !SupportConsoleRetentionJob.stale_turn?(m) }
    end

    # @return [Time, nil] when the last question was asked, across all clients
    def last_question_at
      agent = SupportConsoleAgent.existing
      return unless agent

      AgentChatMessage.joins(:agent_chat_session)
                      .where(agent_chat_sessions: { support_agent_id: agent.id }, role: "user")
                      .maximum(:created_at)
    end

    # @return [Aws::EC2::Types::Instance, nil] the machine behind the relay URL; nil when there is none
    #   or AWS cannot be asked (the console then behaves as before: unavailable)
    def instance
      host = relay_host
      # No default region: IN and US are separate, and a guess could reach the other's account
      return if host.blank? || ENV["AWS_REGION"].blank?

      ec2.describe_instances(filters: [
                               { name: "private-ip-address", values: [host] },
                               { name: "tag:Name", values: ["#{NAME_PREFIX}*"] },
                               { name: "instance-state-name", values: %w[pending running stopping stopped] }
                             ]).reservations.flat_map(&:instances).first
    rescue Aws::Errors::ServiceError, Seahorse::Client::NetworkingError, Aws::Errors::MissingCredentialsError => e
      Rails.logger.warn("[support_console] machine lookup failed: #{e.class}: #{e.message}")
      nil
    end

    private

    def relay_host
      url = SupportConsoleRelayClient.url
      url.present? ? URI(url).host : nil
    end

    def ec2
      Aws::EC2::Client.new(
        access_key_id: Rails.application.credentials[:AWS_ACCESS_KEY_ID],
        secret_access_key: Rails.application.credentials[:AWS_SECRET_ACCESS_KEY],
        region: ENV.fetch("AWS_REGION"),
        http_open_timeout: 5,
        http_read_timeout: 20
      )
    end
  end
end

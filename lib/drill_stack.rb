# frozen_string_literal: true

# Marks the processes of a DR DRILL stack (openspec fix-dr-drill-hygiene).
#
# aws:dr_drill writes DR_DRILL_STACK=<region> into the drill branch's .env, so every process on
# the drill's servers knows it is a rehearsal:
# - its error mail is tagged "[DR DRILL <region>]", so it is never mistaken for a live incident;
# - it never sends a critical WhatsApp page (CriticalErrorWhatsapp.enabled?) - a drill must not
#   wake anyone, and its errors still arrive as tagged mail.
# A real recovery never sets it, so a recovered production still pages as before.
#
# Plain Ruby, required at boot by config/initializers/exception_notification.rb and
# lib/critical_error_whatsapp.rb (the notifier must not autoload at the moment it fires).
require "net/http"

module DrillStack
  # --- Silence on a drill copy (openspec fix-dr-drill-contacts-users) --------------------------
  # A drill runs the real app on a copy of real data. On a drill stack, and ONLY there, every
  # outgoing channel is stopped at one choke point each, so no user ever hears from the copy:
  # - email: MailInterceptor (every mailer passes ActionMailer's interceptors);
  # - WhatsApp (WATI), push (Expo), SMS (Twilio, via Faraday's Net::HTTP adapter):
  #   OutboundGuard on Net::HTTP#request, matching these providers' hosts only;
  # - timed jobs: register_timed_jobs? is false (config/initializers/sidekiq.rb), and the drill
  #   deploy clears the whenever crontab (config/deploy.rb).
  # The real app never has DR_DRILL_STACK, so activate! does nothing there.

  # Hosts of the providers that reach a person outside email. Exact host or a subdomain of it.
  BLOCKED_HOSTS = [/(\A|\.)wati\.io\z/, /\Aexp\.host\z/, /(\A|\.)twilio\.com\z/].freeze
  # Rails.cache key counting what a drill copy held back (shown by dr:verify)
  SUPPRESSED_KEY = "dr:drill_suppressed"

  # ActionMailer interceptor: the email is built as usual, then never delivered
  module MailInterceptor
    def self.delivering_email(message)
      message.perform_deliveries = false
      DrillStack.record_suppressed("email to #{Array(message.to).size} recipient(s): #{message.subject}")
    end
  end

  # Prepended to Net::HTTP on drill stacks: a request to a messaging provider is answered
  # locally (a 200 saying "suppressed") instead of being sent. Everything else - S3, GitHub, AWS -
  # passes through, so the drill itself keeps working.
  module OutboundGuard
    def request(req, body = nil, &block)
      return super unless DrillStack.blocked_host?(address)

      DrillStack.record_suppressed("#{req.method} #{address}#{req.path}")
      response = DrillStack.synthetic_ok
      # The block form (Net::HTTP.post / #post) reads the response through the block
      block&.call(response)
      response
    end

    private

    # No socket to a messaging provider at all: Net::HTTP.start would otherwise open one
    # (and a TLS handshake) before any request is made
    def connect
      super unless DrillStack.blocked_host?(address)
    end
  end

  module_function

  def blocked_host?(host)
    name = host.to_s.downcase
    BLOCKED_HOSTS.any? { |pattern| name.match?(pattern) }
  end

  # A 200 response with a small JSON body, so callers proceed without retrying or raising
  def synthetic_ok
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.instance_variable_set(:@body, %({"result":true,"suppressed":"dr drill"}))
    response.instance_variable_set(:@read, true)
    response["content-type"] = "application/json"
    response
  end

  # Logs and counts one held-back message. Never raises: silence must not break the job.
  def record_suppressed(what)
    Rails.logger.info("[DR DRILL] suppressed #{what}") if defined?(Rails.logger) && Rails.logger
    Rails.cache.write(SUPPRESSED_KEY, suppressed_count + 1, expires_in: 7 * 24 * 3600) if defined?(Rails.cache) && Rails.cache
  rescue StandardError
    nil
  end

  def suppressed_count
    (defined?(Rails.cache) && Rails.cache && Rails.cache.read(SUPPRESSED_KEY)).to_i
  end

  # Should timed jobs (sidekiq-cron) be registered? Not on a drill copy.
  def register_timed_jobs?(env = ENV)
    !drill?(env)
  end

  # Switches the silence on, only on a drill stack. Called once at boot by
  # config/initializers/drill_stack.rb. Returns whether it switched anything on.
  def activate!(env = ENV)
    return false unless drill?(env)

    ActionMailer::Base.register_interceptor(MailInterceptor)
    Net::HTTP.prepend(OutboundGuard) unless Net::HTTP <= OutboundGuard
    # Safeguard: say so loudly, so a real server that somehow got the flag shows it at once
    message = boot_message(env)
    Rails.logger&.warn(message)
    warn(message)
    true
  end

  def boot_message(env = ENV)
    "🛑 DRILL STACK (#{region(env)}): all outgoing contact suppressed — email, WhatsApp, SMS and push are held back " \
      "and timed jobs are off. If this is NOT a DR drill server, remove DR_DRILL_STACK from .env and redeploy."
  end

  # Is the drill mail interceptor registered? Reads the mail gem's PUBLIC registry
  # (Mail.delivery_interceptors - ActionMailer's register_interceptor adds to it). The first
  # version read @@delivery_interceptors off Mail::Message, which does not exist there, and
  # the 2026-11-08 14:39 drill's check crashed with a NameError.
  def mail_intercepted?
    Mail.delivery_interceptors.include?(MailInterceptor)
  end

  # dr:verify's "Drill cannot contact users": every channel must be shut on a drill copy
  def grade_silence(mail_intercepted:, requests_guarded:, timed_jobs:, crontab_installed:, suppressed:)
    grade = Dr::BackupSchedule::Grade
    live = []
    live << "mail delivery is live" unless mail_intercepted
    live << "WhatsApp/SMS/push requests are not guarded" unless requests_guarded
    live << "#{timed_jobs} timed jobs registered" if timed_jobs.positive?
    live << "the cron (whenever) is installed" if crontab_installed
    return grade.new(:fail, "#{live.join('; ')} — this drill copy could contact real users") if live.any?

    grade.new(:ok, "nothing can reach users: mail intercepted, messaging hosts guarded, no timed jobs (#{suppressed} held back so far)")
  end

  # The drill's region ("ap-south-2"), or nil on every real environment
  def region(env = ENV)
    value = env["DR_DRILL_STACK"].to_s.strip
    value.empty? ? nil : value
  end

  def drill?(env = ENV)
    !region(env).nil?
  end

  # dr:verify's check that a stack is marked correctly for its kind of run.
  # expected_drill: this run is a drill (DR_DRILL=true, forwarded by cap).
  # Returns a Dr::BackupSchedule::Grade (resolved at call time, after boot).
  def grade_mark(expected_drill:, env: ENV)
    grade = Dr::BackupSchedule::Grade
    if expected_drill
      # A drill server without the mark would page WhatsApp and send untagged mail
      return grade.new(:ok, "drill servers marked (#{region(env)}): tagged mail, no WhatsApp pages") if drill?(env)

      grade.new(:fail, "drill servers are NOT marked (no DR_DRILL_STACK in .env) — they would page WhatsApp like a live outage")
    else
      # A recovered production marked as a drill would never page anyone
      return grade.new(:ok, "not marked as a drill — critical alerts page as normal") unless drill?(env)

      grade.new(:fail, "this recovered stack is marked as a drill (DR_DRILL_STACK=#{region(env)}) — it will NEVER page; " \
                       "remove DR_DRILL_STACK from .env and redeploy")
    end
  end

  # The error mail subject prefix: unchanged on a real environment, tagged on a drill stack
  def email_prefix(rails_env:, base_domain:, env: ENV)
    tag = drill?(env) ? "[DR DRILL #{region(env)}]" : ""
    "[Error]#{tag} #{rails_env}:(#{base_domain})"
  end
end

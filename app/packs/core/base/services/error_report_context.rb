# frozen_string_literal: true

# The "who / what / where" block attached to every error email (EntityMailer#notify_errors,
# #doc_gen_errors and #spa_job_errors).
#
# Why this exists: the error emails used to carry the error text and nothing else — a support
# inbox would receive `caphive.com Errors / Missing rates: ["Capital Commitments: USD->INR on
# 1899-12-30"]` with no way to tell which job produced it, who triggered it, for which entity,
# or with what arguments. Everything needed to reproduce the failure had to be guessed. This
# builds an ordered Hash of String => String that the mailer views render as a table above the
# error list.
#
# Values are plain strings on purpose: the hash travels as an ActionMailer `params` value, so a
# caller that switches to deliver_later still serializes cleanly (ActiveJob cannot serialize an
# AR object, and we never want an error report to fail on its own diagnostics).
class ErrorReportContext
  # Shown instead of a name when nothing attributed the work to a person — a sidekiq-cron run,
  # a console invocation, or a job enqueued before ApplicationJob started carrying the actor.
  UNATTRIBUTED = "Not attributed — scheduled (sidekiq-cron) or console run"

  class << self
    # Context for an error raised inside an ActiveJob. `job` is normally `self` from within the
    # job. Extra keys are appended before the environment block; symbol keys are humanized
    # ("fund_id" -> "Fund id"), string keys are used verbatim.
    def for_job(job, **extra)
      base = {
        "Source" => job.class.name,
        "Triggered by" => actor(job.try(:acting_user)),
        "Triggered from" => job.try(:enqueued_from),
        "Job arguments" => job_arguments(job),
        "Job id" => job.try(:job_id),
        "Queue" => job.try(:queue_name),
        "Attempt" => job.try(:executions).to_i + 1
      }
      finish(base, extra)
    rescue StandardError => e
      fallback(e)
    end

    # Context for an error raised outside a job — a service object or a controller.
    # `source` names the entry point, e.g. "MultiSiteUserSyncOrchestrator.sync_all".
    def for_service(source, user: nil, **extra)
      finish({ "Source" => source.to_s, "Triggered by" => actor(user || Current.user) }, extra)
    rescue StandardError => e
      fallback(e)
    end

    # Last-resort context for a mailer that was handed no `context:` — everything we can still
    # recover from the mailer's own params. Keeps older callers useful without touching them.
    def for_mailer(user: nil, entity: nil)
      finish({ "Triggered by" => actor(user) }, entity ? { entity: entity } : {})
    rescue StandardError => e
      fallback(e)
    end

    private

    # This object exists only to describe a failure that has already happened. If building the
    # description itself blows up — normalize_extra does hit the database to name the entity, and
    # the database is exactly the kind of thing that is broken when these emails go out — the
    # error report must still be delivered. Swallowing the diagnostics is the lesser loss; losing
    # the report is what the caller was trying to avoid.
    def fallback(error)
      Rails.logger.error("ErrorReportContext failed to build: #{error.class}: #{error.message}")
      { "Context" => "unavailable (#{error.class})", "Environment" => Rails.env }
    end

    def finish(base, extra)
      base
        .merge(normalize_extra(extra))
        .merge(
          "Host" => hostname,
          "Environment" => Rails.env,
          "Occurred at" => "#{I18n.l(Time.current, format: :email, locale: :en)} #{Time.current.zone}"
        )
        .transform_values { |value| stringify(value) }
        .compact_blank
    end

    # :fund_id => "Fund id", "Funds processed" => "Funds processed". An :entity or :entity_id
    # key is resolved to a readable "Name (#12)" rather than a bare number.
    def normalize_extra(extra)
      extra.each_with_object({}) do |(key, value), acc|
        case key.to_sym
        when :entity, :entity_id
          entity = value.is_a?(Entity) ? value : Entity.find_by(id: value)
          acc["Entity"] = entity ? "#{entity.name} (##{entity.id})" : value
        else
          # keep_id_suffix: plain humanize turns "fund_id" into "Fund", which reads like a name
          # and then shows a bare number. "Fund id: 42" is honest about what the value is.
          acc[key.is_a?(Symbol) ? key.to_s.humanize(keep_id_suffix: true) : key.to_s] = value
        end
      end
    end

    def actor(user)
      return UNATTRIBUTED if user.blank?

      "#{user.try(:full_name).presence || user.try(:email)} (#{user.try(:email)}, user ##{user.id})"
    end

    # A job run with perform_now (or instantiated directly, as ChangeFundCurrencyJob does) has
    # no serialized arguments — nil rather than an empty list, so the row is dropped entirely.
    #
    # A job that came back off the Sidekiq queue carries ActiveJob's own "_aj_ruby2_keywords"
    # bookkeeping inside its keyword-argument hash; that is noise to whoever reads the email,
    # so it is dropped.
    def job_arguments(job)
      # ActiveJob deserializes arguments lazily: a job rebuilt from its Sidekiq payload has them
      # only in @serialized_arguments until perform_now unpacks them. That unpacking has always
      # happened by the time a job reports its own errors, but falling back keeps the block
      # populated for any caller that builds the context earlier.
      args = job.try(:arguments).presence || job.instance_variable_get(:@serialized_arguments)
      return nil if args.blank?

      args.map { |arg| arg.is_a?(Hash) ? arg.reject { |key, _| key.to_s.start_with?("_aj_") } : arg }
    end

    def stringify(value)
      case value
      when nil then nil
      when Hash then value.map { |k, v| "#{k}: #{stringify(v)}" }.join(", ")
      when Array then value.map { |v| stringify(v) }.join(", ")
      else value.to_s
      end
    end

    def hostname
      @hostname ||= Socket.gethostname
    rescue StandardError
      "unknown"
    end
  end
end

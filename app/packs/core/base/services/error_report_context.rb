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

  # Defers building a context until it is printed. ExceptionNotifier reads the request's
  # exception data from the Rack env, which must be set before the action runs - but building
  # the block then would mean a database lookup on every request, almost all of which succeed.
  # The email renders its data with PP, so computing on pretty_print / inspect builds the block
  # only for the requests that actually fail, and only once.
  class Lazy
    def initialize(&builder)
      @builder = builder
    end

    def value
      @value ||= @builder.call
    end

    # inspect / to_s cover the email's other renderers and any logging of the data hash.
    delegate :inspect, :to_s, to: :value

    def pretty_print(printer)
      printer.pp(value)
    end
  end

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

    # Context for an error raised while serving a web request — the block the developer error email
    # (ExceptionNotifier) carries for page errors. Built when the error is reported, not when the
    # request starts (see Lazy), so it shows the state at the moment of failure — after a persona
    # switch, with the support login-as already applied — and costs nothing on requests that succeed.
    def for_request(controller)
      user = safely { controller.send(:current_user) }
      request = controller.request
      base = {
        "Source" => "#{controller.class.name}##{controller.action_name}",
        "Request" => "#{request.request_method} #{request.fullpath}",
        "Request id" => request.request_id,
        "User" => user ? actor(user) : "Not signed in",
        # session, not user.support_user_id: that is set by authenticate_user!, which may not have
        # run yet when an early before_action raises.
        "Impersonated by" => safely { (id = controller.session[:support_user_id]).present? ? actor(User.find_by(id:)) : nil }
      }.merge(user ? user_whereabouts(user) : {})
      finish(base, {})
    rescue StandardError => e
      fallback(e)
    end

    # Context for a Sidekiq job failure, from the ctx Sidekiq hands its error handlers. Sidekiq's
    # payload holds the ActiveJob envelope as raw JSON, so the actor is an id, the arguments carry
    # ActiveJob's own "_aj_" bookkeeping and the job class hides behind Sidekiq's wrapper. This
    # unpacks it into the same rows for_job produces from inside a running job.
    def for_sidekiq(ctx)
      job = ctx[:job] || ctx["job"]
      return finish({ "Source" => "Sidekiq (#{ctx[:context] || ctx['context'] || 'no job'})" }, {}) unless job.is_a?(Hash)

      # ActiveJob jobs arrive wrapped: Sidekiq's "class" is the wrapper and the real job, its
      # arguments, acting_user_id and enqueued_from sit in the single envelope in "args".
      envelope = job["wrapped"] && job["args"]&.first.is_a?(Hash) ? job["args"].first : nil
      acting_user_id = envelope&.dig("acting_user_id")
      base = {
        "Source" => job["wrapped"] || job["class"],
        "Triggered by" => acting_user_id ? safely { actor(User.with_deleted.find_by(id: acting_user_id)) } : actor(nil),
        "Triggered from" => envelope&.dig("enqueued_from"),
        "Job arguments" => clean_arguments(envelope ? envelope["arguments"] : job["args"]),
        "Job id" => envelope&.dig("job_id"),
        "Sidekiq jid" => job["jid"],
        "Queue" => job["queue"],
        "Retry count" => job["retry_count"],
        "Sidekiq context" => ctx[:context] || ctx["context"]
      }
      finish(base, {})
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

    # Where the user was when it failed. The entity they are switched into is the most common
    # hidden cause - many checks assume the user is inside the record's entity - so it is spelled
    # out, along with an advisor's home firm and the roles in force at that moment.
    def user_whereabouts(user)
      {
        "Switched into" => safely { "#{user.entity&.name} (##{user.entity_id}, #{user.entity_type})" },
        "Home firm" => safely do
          next if user.advisor_entity_id.blank? || user.advisor_entity_id == user.entity_id

          "#{Entity.find_by(id: user.advisor_entity_id)&.name} (##{user.advisor_entity_id})"
        end,
        "Current role" => user.try(:curr_role),
        "Roles" => safely { user.roles.map(&:name).sort }
      }
    end

    # One row's lookup failing (the database is often what is broken when these emails go out)
    # must cost only that row, not the whole block.
    def safely
      yield
    rescue StandardError => e
      "unavailable (#{e.class})"
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
      clean_arguments(job.try(:arguments).presence || job.instance_variable_get(:@serialized_arguments))
    end

    def clean_arguments(args)
      return nil if args.blank?

      Array(args).map { |arg| arg.is_a?(Hash) ? arg.reject { |key, _| key.to_s.start_with?("_aj_") } : arg }
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

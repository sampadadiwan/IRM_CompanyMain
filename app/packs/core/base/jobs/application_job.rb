class ApplicationJob < ActiveJob::Base
  sidekiq_options backtrace: 20
  # Automatically retry jobs that encountered a deadlock
  retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  discard_on ActiveJob::DeserializationError

  # --- Audit attribution ----------------------------------------------------
  #
  # `audited` names the actor from Audited.store, a thread-local that
  # Audited::Sweeper fills from the controller on each request. A job runs on a
  # different thread in a different process, so that store is empty and every
  # audit the job writes lands with user_id NULL — which was ~74% of the whole
  # audits table (worst for updates: 94% of job-written update audits).
  #
  # So we carry the acting user across the process boundary ourselves: captured
  # from Current.user when the job is enqueued, restored around perform, and
  # handed to audited via as_user. Because the restore also sets Current.user, a
  # job that enqueues another job propagates the same actor down the chain.
  #
  # The id travels as a plain Integer, never a GlobalID to the User record. This
  # class sets `discard_on ActiveJob::DeserializationError` above, and User is
  # acts_as_paranoid (see Trackable), so a GlobalID pointing at a since-deleted
  # user would raise on deserialize and silently discard the entire job — losing
  # real work, not merely the attribution.
  def serialize
    # @enqueued_from is already set when this is a RE-serialize (a retry re-enqueues the job).
    # Recomputing there would overwrite the real call site with nil, since a retry's stack holds
    # nothing but ActiveJob/Sidekiq frames.
    super.merge("acting_user_id" => Current.user&.id, "enqueued_from" => @enqueued_from || enqueue_origin)
  end

  def deserialize(job_data)
    super
    @acting_user_id = job_data["acting_user_id"]
    @enqueued_from = job_data["enqueued_from"]
  end

  # --- Error-report attribution ---------------------------------------------
  #
  # The call site that enqueued this job, e.g.
  # "app/packs/core/entities/controllers/exchange_rates_controller.rb:13:in `update'".
  # Captured at enqueue time because by the time the job runs on a Sidekiq thread the
  # originating request is long gone, and an error email that names only the job class
  # cannot tell a scheduled sweep apart from a button someone pressed. Travels in the job
  # payload alongside acting_user_id and is surfaced by ErrorReportContext.for_job.
  #
  # nil for a sidekiq-cron run (no application frame on the stack) and for perform_now,
  # which never serializes at all — in both cases the row is simply omitted from the email.
  attr_reader :enqueued_from

  # Diagnostic block for an error email raised from inside this job. Extra keys are appended
  # as-is; symbol keys are humanized. See ErrorReportContext.
  #
  #   EntityMailer.with(error_msg:, entity_id:, context: error_context(entity_id:, force:))
  #               .notify_errors.deliver_now
  def error_context(**extra)
    ErrorReportContext.for_job(self, **extra)
  end

  # This file's own path as backtrace_cleaner reports it. Derived rather than written out so
  # moving this file can't silently degrade the attribution back to naming
  # ApplicationJob#serialize as the trigger. Both paths are absolute, so relative_path_from
  # cannot raise here.
  OWN_BACKTRACE_PATH = Pathname.new(__FILE__).relative_path_from(Rails.root).to_s.freeze

  # Rails.backtrace_cleaner strips the Rails.root prefix and silences gem frames, so the first
  # surviving "app/..." or "lib/..." line is the application call site that enqueued this job —
  # once this file's own frames are dropped, since `serialize` above is itself an "app/..." line
  # and would otherwise always win. Runs once per enqueue, on the enqueueing thread; a failure
  # here must never take an enqueue down, hence the rescue.
  def enqueue_origin
    # caller(1, 40): this runs on every single enqueue in the app, including bulk loops, so the
    # stack is capped rather than materialized in full. The enqueueing app frame sits a handful
    # of frames up, well inside 40.
    Rails.backtrace_cleaner.clean(caller(1, 40)).find do |line|
      line.start_with?("app/", "lib/") && !line.start_with?(OWN_BACKTRACE_PATH)
    end
  rescue StandardError
    nil
  end

  around_perform do |job, block|
    user = job.acting_user

    if user
      Current.set(user: user) { Audited.audit_class.as_user(user) { block.call } }
    else
      # Nothing known about the actor (a sidekiq-cron run, a console enqueue, or
      # a job enqueued before this code shipped). Leave the audits unattributed
      # rather than inventing an actor — a wrong name in a compliance trail is
      # worse than an honest blank.
      block.call
    end
  end

  # with_deleted: a user who has since been deactivated should still attribute to
  # their own name. Falls back to Current.user for perform_now, which never goes
  # through serialize/deserialize.
  def acting_user
    return @acting_user if defined?(@acting_user)

    @acting_user = if @acting_user_id
                     User.with_deleted.find_by(id: @acting_user_id)
                   else
                     Current.user
                   end
  end

  def send_notification(message, user_id, level = "success")
    if level == "danger"
      Rails.logger.error { message }
    else
      Rails.logger.debug { message }
    end
    UserAlert.new(user_id:, message:, level:).broadcast if user_id.present? && message.present?
  end

  def send_errors_notification(main_error, error_msg, user_id, _level = "success")
    @show_btn = true
    @error_msg = error_msg
    @user_id = user_id
    @main_error = main_error

    # Render the /entity_mailer/doc_gen_errors email template and capture the output as a string
    msg = ApplicationController.render(
      template: "entity_mailer/doc_gen_errors",
      assigns: { main_error: @main_error, error_msg: @error_msg, user_id: @user_id, show_btn: @show_btn },
      layout: false
    )
    send_notification(msg, user_id, "danger")
  end

  # email errors to the user
  def email_errors
    error_msg = @error_msg
    user_id = @user_id

    if error_msg.present?
      logger.info @main_error
      send_notification(@main_error, user_id, :danger)
      EntityMailer.with(entity_id: User.find(user_id).entity_id, user_id:, error_msg:, main_error: @main_error,
                        context: error_context).doc_gen_errors.deliver_now
    end
  end

  def self.run_from_console(queue = "default")
    # Get the last job enqueued (from the default queue, change if needed)
    job = Sidekiq::Queue.new(queue).to_a.first

    if job.present?
      # Inspect it
      job.klass      # => Worker class name
      job.args       # => Arguments passed
      job.enqueued_at

      # Run it immediately in the console
      job.klass.constantize.new.perform(*job.args)
    else
      Rails.logger.debug { "No jobs in the #{queue} queue" }
    end
  end
end

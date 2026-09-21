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
    super.merge("acting_user_id" => Current.user&.id)
  end

  def deserialize(job_data)
    super
    @acting_user_id = job_data["acting_user_id"]
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
      EntityMailer.with(entity_id: User.find(user_id).entity_id, user_id:, error_msg:, main_error: @main_error).doc_gen_errors.deliver_now
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

# frozen_string_literal: true

# Preview and manual-trigger helpers for the weekly task digest.
# See docs/modules/tasks/weekly_task_digest_prd.md.
#
# Three tasks, in increasing order of consequence:
#   preview  — renders to a file. Sends nothing, writes nothing to the database.
#   deliver  — really sends, to ONE named user, in this process.
#   run      — really sends, to every tagged recipient of an entity. Same path as cron.
#
# What "really sends" means is decided by the environment, not by this file:
#   development  — action_mailer.delivery_method is :letter_opener, so the message opens
#                  in a browser tab instead of leaving the machine, and sanitize_email
#                  rewrites the recipient to SANDBOX_EMAILS
#   staging/prod — SMTP through SES (config/application.rb). The entity's own
#                  entity_setting.sandbox can still redirect it to sandbox_emails.
namespace :task_digest do
  desc "Render the digest for a user to a file WITHOUT sending it. " \
       "Usage: rake 'task_digest:preview[123]' or rake 'task_digest:preview[123,2026-09-11]'"
  task :preview, %i[user_id as_of] => :environment do |_t, args|
    user, as_of, digest = TaskDigestRake.load(args)
    next unless TaskDigestRake.report(user, as_of, digest)

    mail = TaskDigestMailer.with(user_id: user.id, entity_id: user.entity_id, as_of: as_of.to_s).weekly_digest.message
    puts "Subject    : #{mail.subject}"
    puts "Would go to: #{Array(mail.to).join(', ')}"

    path = Rails.root.join("tmp/task_digest_preview_#{user.id}.html")
    File.write(path, mail.html_part&.decoded || mail.body.decoded)
    puts "HTML       : #{path}"
    puts "\nNothing sent. Use task_digest:deliver to actually send it."
  end

  desc "REALLY SEND the digest to one user, now, in this process. " \
       "Ignores the Tasks tag and the entity's enabled setting. " \
       "Usage: rake 'task_digest:deliver[123]' or rake 'task_digest:deliver[123,2026-09-11]'"
  task :deliver, %i[user_id as_of] => :environment do |_t, args|
    user, as_of, digest = TaskDigestRake.load(args)
    next unless TaskDigestRake.report(user, as_of, digest)

    notification = TaskDigestRake.deliver_now(user, as_of, digest.counts)

    puts "Sent via   : #{ActionMailer::Base.delivery_method}"
    TaskDigestRake.report_notification(notification)
  end

  desc "REALLY SEND the digest to every tagged, active employee of an entity — the same " \
       "path as the Friday cron, minus the entity_type and enabled-setting checks. " \
       "Enqueues through Sidekiq; pass now=true to send in this process instead. " \
       "Usage: rake 'task_digest:run[45]' or rake 'task_digest:run[45,2026-09-11,true]'"
  task :run, %i[entity_id as_of now] => :environment do |_t, args|
    raise ArgumentError, "entity_id is required" if args[:entity_id].blank?

    entity = Entity.find(args[:entity_id])
    as_of = args[:as_of].present? ? args[:as_of].to_date : Time.zone.today
    recipients = entity.employees.active.with_tag(WeeklyTaskDigestJob::RECIPIENT_TAG)

    puts "Entity     : #{entity.name} (#{entity.entity_type})"
    puts "Tagged     : #{recipients.count} active employee(s) tagged '#{WeeklyTaskDigestJob::RECIPIENT_TAG}'"
    puts "As of      : #{as_of} (#{as_of.strftime('%A')})"

    if recipients.none?
      puts "\nNobody to send to. Tag an employee with '#{WeeklyTaskDigestJob::RECIPIENT_TAG}' first."
      next
    end

    if args[:now].to_s == "true"
      sent = 0
      recipients.find_each do |user|
        d = WeeklyTaskDigest.new(user, entity, as_of: as_of)
        next unless d.any?

        TaskDigestRake.report_notification(TaskDigestRake.deliver_now(user, as_of, d.counts))
        sent += 1
      end
      puts "\nSent #{sent} digest(s) via #{ActionMailer::Base.delivery_method}."
    else
      WeeklyTaskDigestJob.perform_now(entity_id: entity.id, as_of: as_of.to_s)
      puts "\nQueued. Recipients with nothing in any section are skipped."
      TaskDigestRake.warn_if_no_sidekiq
    end
  end
end

# Shared plumbing for the three tasks above, so the "what would this send" report is
# identical whether or not it actually sends.
module TaskDigestRake
  def self.load(args)
    user = User.find(args[:user_id])
    as_of = args[:as_of].present? ? args[:as_of].to_date : Time.zone.today
    [user, as_of, WeeklyTaskDigest.new(user, user.entity, as_of: as_of)]
  end

  def self.report(user, as_of, digest)
    puts "Recipient  : #{user.full_name} <#{user.email}>"
    puts "Entity     : #{user.entity.name} (#{user.entity.entity_type})"
    puts "As of      : #{as_of} (#{as_of.strftime('%A')})"
    puts "Counts     : #{digest.counts.inspect}"

    if user.entity.entity_setting.sandbox
      puts "NOTE       : entity sandbox is ON — mail goes to #{user.entity.entity_setting.sandbox_emails}"
    end

    return true if digest.any?

    puts "\nNothing in any section — the Friday job would skip this recipient, so there is nothing to send."
    false
  end

  # Raise the notifier event and render its email synchronously.
  #
  # Noticed 3 aliases `deliver` to `deliver_later` — both always enqueue
  # Noticed::EventJob, which in turn enqueues the mailer. On a box with no Sidekiq
  # worker running that means the row appears and the email never does, which is
  # exactly the confusion this task exists to avoid. So: create the notification with
  # enqueue_job: false, then invoke the mailer here with the same params
  # Noticed::DeliveryMethods::Email would have passed it.
  #
  # This deliberately bypasses the deliver_by :if guards in BaseNotifier — a manual
  # trigger means "send it to me now", not "send it if the recipient's toggles allow".
  # The scheduled job goes through the guards normally.
  def self.deliver_now(user, as_of, counts)
    event = WeeklyTaskDigestNotifier.with(
      record: user,
      entity_id: user.entity_id,
      as_of: as_of.to_s,
      delayed_count: counts[:delayed],
      due_next_week_count: counts[:due_next_week],
      completed_count: counts[:completed_this_week]
    ).deliver(user, enqueue_job: false)

    notification = event.notifications.first
    params = event.email_data(notification).merge(
      notification: notification, record: user, recipient: user
    )
    TaskDigestMailer.with(params).weekly_digest.deliver_now

    notification.reload
  end

  def self.report_notification(notification)
    return puts("No notification row was created.") if notification.nil?

    puts "Notification: ##{notification.id} to #{notification.recipient.email}, " \
         "email_sent=#{notification.email_sent}, subject=#{notification.subject.inspect}"
  end

  # A queued send on a box with no worker looks identical to a successful one.
  def self.warn_if_no_sidekiq
    require "sidekiq/api"
    return if Sidekiq::ProcessSet.new.size.positive?

    puts "WARNING    : no Sidekiq process is running, so the queued emails will sit " \
         "until one starts. Re-run with now=true to send in this process."
  rescue StandardError => e
    puts "(could not check for a running Sidekiq: #{e.message})"
  end
end

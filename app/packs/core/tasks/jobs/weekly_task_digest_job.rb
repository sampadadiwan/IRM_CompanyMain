# frozen_string_literal: true

# Sends the weekly task digest. Cron-scheduled for Friday from
# config/initializers/sidekiq.rb; see docs/product/weekly_task_digest_prd.md.
#
# Three gates, all required, before anyone hears from us:
#   1. the entity is an Investment Fund (Entity.funds)
#   2. entity_setting.weekly_task_digest_enabled is on (defaults to false, so
#      deploying this feature sends nothing until a fund is explicitly enabled)
#   3. the employee is active and tagged "Tasks"
#
# Structure follows EntityDbDumpJob: each entity is wrapped in its own rescue so one
# fund's bad data cannot abort the batch for every other fund on the box.
class WeeklyTaskDigestJob < ApplicationJob
  queue_as :low

  # users.tag_list is free text; this is the exact string the digest looks for.
  # Matched by User.with_tag, which is a LIKE — a user tagged "Subtasks" matches too.
  # Consistent with the existing "Kpi" and "db_dump_notification" tags; see
  # User::NOTIFICATION_TAGS.
  RECIPIENT_TAG = "Tasks"

  # @param entity_id [Integer, nil] restrict to one entity (rake preview / manual run)
  # @param user_id [Integer, nil] restrict to one recipient, skipping the tag check
  # @param as_of [String, Date, nil] treated as "today"; defaults to the run date
  def perform(entity_id: nil, user_id: nil, as_of: nil)
    as_of = as_of.present? ? as_of.to_date : Time.zone.today

    eligible_entities(entity_id).find_each do |entity|
      sent = deliver_for(entity, as_of, user_id: user_id)
      Rails.logger.info { "[WeeklyTaskDigestJob] #{entity.name}: queued #{sent} digest(s)" }
    rescue StandardError => e
      Rails.logger.error { "[WeeklyTaskDigestJob] Error for entity #{entity.id}: #{e.message}" }
      ExceptionNotifier.notify_exception(e, data: { entity_id: entity.id, job: "WeeklyTaskDigestJob" })
    end
  end

  private

  # A manual run for one entity deliberately skips the entity_type and setting checks
  # so an admin can preview a digest for a fund that has not been switched on yet.
  # The scheduled run (entity_id nil) applies both.
  def eligible_entities(entity_id)
    return Entity.where(id: entity_id) if entity_id.present?

    Entity.funds
          .joins(:entity_setting)
          .where(entity_settings: { weekly_task_digest_enabled: true })
  end

  def deliver_for(entity, as_of, user_id: nil)
    sent = 0

    recipients(entity, user_id).find_each do |user|
      # counts runs the aggregate pass only — no rows loaded for someone who has
      # nothing to say. A recurring "you have nothing" email is the fastest way to
      # get the sender filtered.
      digest = WeeklyTaskDigest.new(user, entity, as_of: as_of)
      next unless digest.any?

      notify(user, entity, as_of, digest.counts)
      sent += 1
    end

    sent
  end

  # Raised through the notifier rather than the mailer so the digest gets the same
  # treatment as every other outgoing message: an in-app notification row, bounce
  # tracking, the per-entity send delay, and the recipient email toggles. See
  # WeeklyTaskDigestNotifier.
  def notify(user, entity, as_of, counts)
    WeeklyTaskDigestNotifier.with(
      record: user,
      entity_id: entity.id,
      as_of: as_of.to_s,
      delayed_count: counts[:delayed],
      due_next_week_count: counts[:due_next_week],
      completed_count: counts[:completed_this_week]
    ).deliver_later(user)
  end

  # A user_id override addresses that person directly, tag or no tag — it exists for
  # the preview rake task, where the point is to see the mail.
  def recipients(entity, user_id)
    return entity.employees.where(id: user_id) if user_id.present?

    entity.employees.active.with_tag(RECIPIENT_TAG)
  end
end

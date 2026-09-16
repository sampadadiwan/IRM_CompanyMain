# frozen_string_literal: true

# Steps for features/core/weekly_task_digest.feature.
# See docs/modules/tasks/weekly_task_digest_prd.md.

Given('the entity has the weekly task digest {word}') do |state|
  @entity.entity_setting.update!(weekly_task_digest_enabled: state == "enabled")
end

Given('the entity type is {string}') do |entity_type|
  @entity.update!(entity_type: entity_type)
end

Given('the user is tagged {string}') do |tag|
  @user.update!(tag_list: tag)
end

Given('the user is not tagged') do
  @user.update!(tag_list: nil)
end

Given('the user is inactive') do
  @user.update!(active: false)
end

Given('there is another employee {string} tagged {string} with role {string}') do |name, tag, role|
  @other_user = FactoryBot.build(:user, entity: @entity, first_name: name, tag_list: tag)
  @other_user.save!
  @other_user.add_role role.to_sym
end

# Columns: details, due_date, completed_on, assigned_to ("other" for @other_user).
#
# completed_on is written after the insert on purpose: Task#stamp_completed_on fires on
# any save that flips `completed`, and it stamps Time.zone.today — so a completed_on
# passed to create! is immediately overwritten with the real current date, which would
# put every "completed this week" fixture in whatever week the suite happens to run.
Given('the following digest tasks exist:') do |table|
  table.hashes.each do |row|
    completed_on = row['completed_on'].presence
    task = Task.new(
      details: row['details'],
      due_date: row['due_date'].presence,
      completed: completed_on.present?,
      entity: @entity,
      user: @user,
      assigned_to: (row['assigned_to'] == "other" ? @other_user : nil),
      response: row['note'].presence
    )
    # Keep TaskNotifier's per-task email out of ActionMailer::Base.deliveries so the
    # digest assertions count only digests.
    task.send_notification_flag = false
    task.save!
    Task.where(id: task.id).update_all(completed_on: completed_on) if completed_on
  end
end

# Enough to exceed WeeklyTaskDigest::ROW_LIMIT, so the "+N more" row renders.
Given('{int} open tasks are due next week') do |count|
  count.times do |i|
    task = Task.new(details: "Bulk task #{i + 1}", due_date: "2026-09-16", entity: @entity, user: @user)
    task.send_notification_flag = false
    task.save!
  end
end

When('the weekly task digest job runs on {string}') do |date|
  ActionMailer::Base.deliveries.clear
  travel_to(Time.zone.parse("#{date} 11:30:00")) do
    WeeklyTaskDigestJob.perform_now
  end
end

# The race the mailer's empty-digest guard exists for: the notification row is written
# when the job runs, but the digest is rebuilt when the mailer finally runs — which can
# be up to email_delay later, or much longer on a backed-up queue. Reproduced here by
# raising the event, closing every task, then delivering.
When('every task is closed between the job and the delivery on {string}') do |date|
  ActionMailer::Base.deliveries.clear
  as_of = date.to_date
  counts = WeeklyTaskDigest.new(@user, @entity, as_of: as_of).counts

  event = WeeklyTaskDigestNotifier.with(
    record: @user, entity_id: @entity.id, as_of: as_of.to_s,
    delayed_count: counts[:delayed], due_next_week_count: counts[:due_next_week],
    completed_count: counts[:completed_this_week]
  ).deliver(@user, enqueue_job: false)
  @notification = event.notifications.first

  # update_all so the completed_on stamping callback doesn't run — these tasks are
  # closed but land in no section, which is exactly the state that empties the digest.
  Task.where(entity: @entity).update_all(completed: true, completed_on: nil)

  TaskDigestMailer.with(event.email_data(@notification)).weekly_digest.deliver_now
end

def weekly_digest_emails
  ActionMailer::Base.deliveries.select { |mail| mail.subject.to_s.start_with?("Weekly Tasks") }
end

# Both parts, decoded — quoted-printable soft line breaks in the HTML part would
# otherwise split a phrase mid-word and defeat a plain `include`.
def weekly_digest_body(mail)
  [mail.html_part&.decoded, mail.text_part&.decoded, (mail.body.decoded unless mail.multipart?)].compact.join("\n")
end

def weekly_digest_email_for(user)
  weekly_digest_emails.find { |mail| Array(mail.to).include?(user.email) }
end

Then('{int} weekly digest email(s) is/are sent') do |count|
  expect(weekly_digest_emails.size).to eq(count)
end

Then('the weekly digest email subject contains {string}') do |text|
  expect(weekly_digest_emails.size).to be >= 1
  expect(weekly_digest_emails.first.subject).to include(text)
end

Then('the weekly digest email body contains {string}') do |text|
  expect(weekly_digest_emails.size).to be >= 1
  expect(weekly_digest_body(weekly_digest_emails.first)).to include(text)
end

Then('the weekly digest email body does not contain {string}') do |text|
  expect(weekly_digest_emails.size).to be >= 1
  expect(weekly_digest_body(weekly_digest_emails.first)).not_to include(text)
end

Then('the weekly digest email text body contains {string}') do |text|
  expect(weekly_digest_emails.size).to be >= 1
  expect(weekly_digest_emails.first.text_part.decoded).to include(text)
end

Then('the weekly digest email to the {word} employee contains {string}') do |_which, text|
  mail = weekly_digest_email_for(@other_user)
  expect(mail).to be_present, "no digest email addressed to #{@other_user.email}"
  expect(weekly_digest_body(mail)).to include(text)
end

Then('the weekly digest email to the {word} employee does not contain {string}') do |_which, text|
  mail = weekly_digest_email_for(@other_user)
  expect(mail).to be_present, "no digest email addressed to #{@other_user.email}"
  expect(weekly_digest_body(mail)).not_to include(text)
end

Then('the weekly digest email to the user contains {string}') do |text|
  mail = weekly_digest_email_for(@user)
  expect(mail).to be_present, "no digest email addressed to #{@user.email}"
  expect(weekly_digest_body(mail)).to include(text)
end

# The digest goes out through WeeklyTaskDigestNotifier, not straight to the mailer, so
# every send should also leave an in-app notification row — that is what puts the digest
# in the bell and in the notifications report, and what carries the bounce-tracking id.
Then('an in-app weekly digest notification is recorded for the user') do
  notification = Noticed::Notification.joins(:event)
                                      .where(recipient: @user, noticed_events: { type: "WeeklyTaskDigestNotifier" })
                                      .order(id: :desc).first
  expect(notification).to be_present, "no WeeklyTaskDigestNotifier notification for #{@user.email}"
  expect(notification.event.record).to eq(@user)
  expect(notification.email_sent).to be(true)
end

Then('the in-app weekly digest notification message is {string}') do |text|
  notification = Noticed::Notification.joins(:event)
                                      .where(recipient: @user, noticed_events: { type: "WeeklyTaskDigestNotifier" })
                                      .order(id: :desc).first
  expect(notification.message).to eq(text)
end

# A digest that empties before delivery must be recorded as a deliberate skip. Without
# skip_reason the row is indistinguishable from a send that SES rejected, while the
# in-app bell still shows the digest line.
Then('the weekly digest notification records a skip reason') do
  @notification.reload
  expect(@notification.skip_reason).to be_present
  expect(@notification.email_sent).to be_falsey
end

# Section links must pin the dates the digest was built with. due_filter=next_week
# resolves against "today" when the link is opened, so a Monday click on a Friday
# digest would land on a different week entirely.
Then('the weekly digest email links to the pinned week {string} through {string}') do |from, to|
  body = weekly_digest_body(weekly_digest_emails.first)
  expect(body).to include("due_date_gteq%5D=#{from}")
  expect(body).to include("due_date_lteq%5D=#{to}")
  expect(body).not_to include("due_filter")
end

# Steps for features/core/critical_error_whatsapp.feature.
#
# WATI is never called: the transport is replaced with a recorder and everything runs
# inline (async: false, no 60 s Redis wait) so each step can assert on what would have
# been sent.

# Raises for real so the exception has a backtrace and a cause, the way Rails hands a
# Mysql2::Error to the notifier: wrapped in ActiveRecord::StatementInvalid.
def raise_wrapped_mysql_error(message)
  raise Mysql2::Error, message
rescue Mysql2::Error
  begin
    raise ActiveRecord::StatementInvalid, "Mysql2::Error: #{message}"
  rescue ActiveRecord::StatementInvalid => e
    e
  end
end

DISK_FULL_MYSQL_MESSAGE = "Error writing file '/tmp/MYfd=81' (OS errno 28 - No space left on device)".freeze

Given('critical error WhatsApp paging is switched on with a recording transport') do
  @whatsapp_attempts = []
  @whatsapp_pages = []
  @wati_rejections = 0
  CriticalErrorWhatsapp.reset!
  ExceptionNotifier.error_grouping_cache.clear
  CriticalErrorWhatsapp.enabled = true
  CriticalErrorWhatsapp.async = false
  CriticalErrorWhatsapp.redis_recheck_after = 0.seconds
  CriticalErrorWhatsapp.phones = ['917721046692']
  CriticalErrorWhatsapp.transport = lambda do |_phones, message|
    @whatsapp_attempts << message
    if @wati_rejections.positive?
      @wati_rejections -= 1
      next OpsWhatsappAlert::Result.new(ok: false, response: { 'success' => false, 'error' => 'There are no valid Receivers' })
    end

    @whatsapp_pages << message
    OpsWhatsappAlert::Result.new(ok: true, response: { 'success' => true })
  end
end

# Undoes only the production guard override; the recorder stays so a send would show.
Given('critical error WhatsApp paging is left at its default') do
  CriticalErrorWhatsapp.enabled = nil
end

Given('WATI rejects the next WhatsApp page') do
  @wati_rejections = 1
end

Given('Redis will still be unreachable when rechecked') do
  CriticalErrorWhatsapp.redis_probe = -> { false }
end

Given('Redis will be reachable again when rechecked') do
  CriticalErrorWhatsapp.redis_probe = -> { true }
end

After('@critical_error_whatsapp') do
  CriticalErrorWhatsapp.reset!
  CriticalErrorWhatsapp.enabled = nil
  CriticalErrorWhatsapp.async = nil
  CriticalErrorWhatsapp.redis_recheck_after = nil
  CriticalErrorWhatsapp.redis_probe = nil
  CriticalErrorWhatsapp.phones = nil
  CriticalErrorWhatsapp.transport = nil
  ExceptionNotifier.error_grouping_cache.clear
end

When('a request fails with the MySQL error {string}') do |message|
  CriticalErrorWhatsapp.call(raise_wrapped_mysql_error(message))
end

When('a request fails with a {string} saying {string}') do |exception_class, message|
  CriticalErrorWhatsapp.call(exception_class.constantize.new(message))
end

When('the disk fills while writing {string}, {string} and {string}') do |*paths|
  paths.each { |path| CriticalErrorWhatsapp.call(Errno::ENOSPC.new("@ rb_sysopen - #{path}")) }
end

# Distinct messages, so each is its own error and only the per-window cap stops them.
When('{int} different disk-full errors are raised') do |count|
  count.times { |i| CriticalErrorWhatsapp.call(Errno::ENOSPC.new("volume #{'x' * (i + 1)}")) }
end

# One report per Sidekiq processor thread, the way a real outage arrives.
When("Sidekiq's fetch loop reports {int} Redis failures") do |count|
  count.times { CriticalErrorWhatsapp.note_fetch_loop_failure(RedisClient::ReadTimeoutError.new('Waited 5 seconds')) }
end

# Through the gem with no notifiers, so no error email is sent from the test. The third
# occurrence is one grouping holds back (log2(3) is not whole); the pager must still see it.
When('the disk-full MySQL error is reported through exception_notification {int} times, with the WhatsApp mute expiring in between') do |count|
  count.times do
    CriticalErrorWhatsapp.reset!
    ExceptionNotifier.notify_exception(raise_wrapped_mysql_error(DISK_FULL_MYSQL_MESSAGE), notifiers: [])
  end
end

Then('{int} WhatsApp page(s) should have been sent') do |count|
  expect(@whatsapp_pages.size).to eq(count)
end

Then('{int} WhatsApp page(s) should have been attempted') do |count|
  expect(@whatsapp_attempts.size).to eq(count)
end

Then('the last WhatsApp page should mention {string}') do |text|
  expect(@whatsapp_pages.last).to include(text)
end

# WhatsApp rejects template parameters containing newlines, tabs or 4+ spaces.
Then('the last WhatsApp page should be a single line') do
  expect(@whatsapp_pages.last).not_to match(/\n|\t| {4,}/)
end

Then('email grouping should send a critical error on occurrences {string} of 1 to {int}') do |expected, last|
  trigger = ExceptionNotifier.notification_trigger
  error = raise_wrapped_mysql_error(DISK_FULL_MYSQL_MESSAGE)
  expect((1..last).select { |n| trigger.call(error, n) }.join(',')).to eq(expected)
end

Then('email grouping should send an ordinary error on occurrences {string} of 1 to {int}') do |expected, last|
  trigger = ExceptionNotifier.notification_trigger
  error = raise_wrapped_mysql_error("Unknown column 'foo' in 'where clause'")
  expect((1..last).select { |n| trigger.call(error, n) }.join(',')).to eq(expected)
end

Then('exception_notification should group errors in an in-memory store') do
  expect(ExceptionNotifier.error_grouping).to be true
  expect(ExceptionNotifier.error_grouping_cache).to be_a(ActiveSupport::Cache::MemoryStore)
end

Then('the middleware stack should contain ExceptionNotification::Rack exactly once') do
  expect(Rails.application.middleware.count { |m| m.klass == ExceptionNotification::Rack }).to eq(1)
end

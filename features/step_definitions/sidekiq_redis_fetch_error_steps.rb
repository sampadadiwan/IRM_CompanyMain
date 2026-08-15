# Steps for features/misc/sidekiq_redis_fetch_error.feature.
#
# These exercise SidekiqRedisFetchError directly rather than through the error handler
# in config/initializers/exception_notification.rb: that handler is registered inside
# Sidekiq.configure_server, which only runs in a Sidekiq server process and therefore
# never runs under Cucumber.

# Frames taken from incident 2d7eca43 (gem paths shortened) so the classifier is tested
# against the real production shape — a redis-client read inside BasicFetch#retrieve_work.
SIDEKIQ_FETCH_LOOP_BACKTRACE = [
  "/gems/redis-client-0.30.0/lib/redis_client/ruby_connection/buffered_io.rb:214:in 'block in RedisClient::RubyConnection::BufferedIO#fill_buffer'",
  "/gems/redis-client-0.30.0/lib/redis_client.rb:424:in 'RedisClient#blocking_call'",
  "/gems/sidekiq-8.1.6/lib/sidekiq/fetch.rb:48:in 'Sidekiq::BasicFetch#retrieve_work'",
  "/gems/sidekiq-8.1.6/lib/sidekiq/processor.rb:92:in 'Sidekiq::Processor#get_one'"
].freeze

# The same exception class as it would look raised by application code touching Redis —
# no Sidekiq fetcher frame, so it must never be suppressed.
SIDEKIQ_APP_CODE_BACKTRACE = [
  "/gems/redis-client-0.30.0/lib/redis_client/ruby_connection/buffered_io.rb:214:in 'block in RedisClient::RubyConnection::BufferedIO#fill_buffer'",
  "/app/packs/core/base/services/some_service.rb:42:in 'SomeService#call'",
  "/gems/sidekiq-8.1.6/lib/sidekiq/processor.rb:210:in 'Sidekiq::Processor#dispatch'"
].freeze

Given('a {string} raised inside Sidekiq\'s fetch loop') do |exception_class|
  @sidekiq_exception = exception_class.constantize.new("Waited 5 seconds")
  @sidekiq_exception.set_backtrace(SIDEKIQ_FETCH_LOOP_BACKTRACE)
end

Given('a {string} raised inside application code') do |exception_class|
  @sidekiq_exception = exception_class.constantize.new("Waited 5 seconds")
  @sidekiq_exception.set_backtrace(SIDEKIQ_APP_CODE_BACKTRACE)
end

# Ruby leaves backtrace nil until an exception is actually raised — this is the shape a
# hand-built or re-wrapped exception arrives in, and we must fail open on it.
Given('a {string} raised with no backtrace') do |exception_class|
  @sidekiq_exception = exception_class.constantize.new("Waited 5 seconds")
end

# What Processor#handle_fetch_exception passes: handle_exception(ex) with no ctx at all,
# which is the "* data: {}" seen in the incident email.
Given('Sidekiq reports it with an empty context') do
  @sidekiq_context = {}
end

# What Processor#dispatch passes for a job that raised.
Given('Sidekiq reports it with the context of a failed job') do
  @sidekiq_context = { context: "Job raised exception", job: { "class" => "DocGenJob", "jid" => "abc123" } }
end

Then('the Sidekiq error handler should suppress the notification') do
  expect(SidekiqRedisFetchError.suppress?(@sidekiq_exception, @sidekiq_context)).to be true
end

Then('the Sidekiq error handler should send the notification') do
  expect(SidekiqRedisFetchError.suppress?(@sidekiq_exception, @sidekiq_context)).to be false
end

Feature: Sidekiq fetch-loop Redis errors do not raise a production alert
  As the person reading the production error mailbox
  I do not want an email for a Redis blip Sidekiq has already recovered from
  So that every alert that arrives is worth acting on

  # Incident 2d7eca43: a single BRPOP read timeout inside Sidekiq's own poll loop
  # emailed a production error with no job, no arguments and an empty data section,
  # for an event Sidekiq healed by itself one second later.

  Scenario: A BRPOP read timeout inside the fetch loop is counted, not emailed
    Given a "RedisClient::ReadTimeoutError" raised inside Sidekiq's fetch loop
    And Sidekiq reports it with an empty context
    Then the Sidekiq error handler should suppress the notification

  Scenario: A cannot-connect error inside the fetch loop is also suppressed
    Given a "RedisClient::CannotConnectError" raised inside Sidekiq's fetch loop
    And Sidekiq reports it with an empty context
    Then the Sidekiq error handler should suppress the notification

  Scenario: The same Redis timeout raised by a job is still emailed
    Given a "RedisClient::ReadTimeoutError" raised inside Sidekiq's fetch loop
    And Sidekiq reports it with the context of a failed job
    Then the Sidekiq error handler should send the notification

  Scenario: A Redis timeout raised outside the fetch loop is still emailed
    Given a "RedisClient::ReadTimeoutError" raised inside application code
    And Sidekiq reports it with an empty context
    Then the Sidekiq error handler should send the notification

  Scenario: A Redis error with no backtrace at all is still emailed
    Given a "RedisClient::ReadTimeoutError" raised with no backtrace
    And Sidekiq reports it with an empty context
    Then the Sidekiq error handler should send the notification

  Scenario: A Redis command error inside the fetch loop is still emailed
    Given a "RedisClient::CommandError" raised inside Sidekiq's fetch loop
    And Sidekiq reports it with an empty context
    Then the Sidekiq error handler should send the notification

  Scenario: An ordinary job exception with an empty context is still emailed
    Given a "NoMethodError" raised inside Sidekiq's fetch loop
    And Sidekiq reports it with an empty context
    Then the Sidekiq error handler should send the notification

  # A raise inside the classifier propagates into Sidekiq's error_handlers chain, which
  # aborts the chain and drops the report — turning a misclassification into a total loss
  # of production alerting. Seen in production when the deployed release directory was
  # removed under a running Sidekiq and merely resolving the classifier raised LoadError.
  Scenario: A classifier that blows up still lets the notification through
    Given a "RedisClient::ReadTimeoutError" raised inside Sidekiq's fetch loop
    And Sidekiq reports it with a context that raises when it is inspected
    Then the Sidekiq error handler should send the notification

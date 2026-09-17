Feature: Sidekiq has one launcher and a processing canary

  Sidekiq used to be started by monit, an @reboot cron entry, a daily
  pkill-and-relaunch cron entry and Capistrano, each finding "the" Sidekiq by
  regex. A copy that was still booting escaped the deploy's stop and its
  one-worker check, leaving duplicate workers that did not process jobs while
  "Sidekiq Down" stayed green. The sidekiq_IRM_<stage> systemd unit is now the
  only launcher (config/deploy/services/sidekiq_IRM_env.service.erb), and
  SidekiqCanaryJob proves jobs are actually running.

  # No DB needed: both halves read config files the way deploy/boot does.

  Scenario: The crontab restarts Sidekiq only through systemd
    When I render the whenever crontab from config/schedule.rb
    Then the rendered crontab should not invoke "bundle exec sidekiq"
    And the rendered crontab should not invoke "pkill"
    And the rendered crontab should not invoke "monit"
    And the rendered crontab should invoke "systemctl restart sidekiq_IRM_"

  Scenario: sidekiq-cron runs the processing canary every minute
    When I read the sidekiq-cron registrations from config/initializers/sidekiq.rb
    Then sidekiq-cron should run "SidekiqCanaryJob" on the cron "* * * * *"

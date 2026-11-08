# frozen_string_literal: true

module Dr
  # Guards the drill's pre-teardown service stop (openspec fix-dr-drill-hygiene).
  #
  # Before `pulumi destroy`, aws:dr_drill stops puma, sidekiq and cron on the drill's app servers -
  # otherwise destroying the DB box makes every running process email (and, in production, page)
  # a connection error. That stop runs Capistrano, which targets whatever config/deploy/<stage>.rb
  # names. On the drill branch that is the drill servers; back on main it is the LIVE servers.
  # So the stop runs only when the deploy file provably names exactly the drill's app servers.
  module DrillTeardown
    # `server "40.192.121.217", user: ...` - the address of each server line
    SERVER_LINE = /^\s*server\s+["']([\d.]+)["']/

    module_function

    # True only when the set of server addresses in the deploy file equals the drill's app server
    # addresses - no fewer (a partial match is not the drill), no more (a live server mixed in).
    def targets_drill?(deploy_file_text, drill_ips)
      listed = deploy_file_text.to_s.scan(SERVER_LINE).flatten.uniq.sort
      expected = Array(drill_ips).compact.map(&:to_s).uniq.sort
      expected.any? && listed == expected
    end
  end
end

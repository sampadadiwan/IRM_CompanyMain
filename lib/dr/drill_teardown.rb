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

    # The drill log's Teardown cell: what happened to the drill stack after the report was written
    # (the report itself cannot say - it is written before teardown).
    # stop: :stopped / :skipped / :failed / nil; destroyed: resources pulumi deleted, or :failed.
    def summary(passed:, teardown:, stop: nil, destroyed: nil)
      return "kept for diagnosis (failed run)" unless passed
      return "kept running (TEARDOWN not set)" unless teardown

      stopped = { stopped: "services stopped", skipped: "service stop skipped (deploy file not the drill's)",
                  failed: "service stop failed" }.fetch(stop, "services not stopped")
      gone = destroyed == :failed ? "destroy FAILED — stack still up" : "#{destroyed || '?'} resources destroyed"
      "#{stopped} · #{gone}"
    end

    # Resources `pulumi destroy` deleted, from its summary ("Resources:\n    - 46 deleted").
    # Anchored to that summary line: resource names end in "-0", "-1"..., so a loose
    # /(\d+) deleted/ matched "…subnet_1-0 deleted (0.48s)" and recorded 0 (2026-11-08 13:17).
    def destroyed_count(output)
      output.to_s.gsub(/\e\[[0-9;]*m/, "").scan(/^\s*-\s*(\d+) deleted\s*$/).flatten.last&.to_i
    end

    # Adds a Teardown cell to the drill's row in dr_drills.md, adding the column to the table
    # header once. Older rows simply have an empty cell. Returns the new text; unchanged if the
    # drill's row is not found.
    def add_teardown_cell(log_text, branch, cell)
      lines = log_text.lines
      # The header and its separator, the first time this column is used
      header = lines.index { |l| l.start_with?("| Date |") }
      if header && lines[header].exclude?("Teardown")
        lines[header] = lines[header].rstrip.sub(/\|\z/, "| Teardown |\n")
        lines[header + 1] = lines[header + 1].rstrip.sub(/\|\z/, "|---|\n")
      end
      # The LAST row for this branch is this run's
      row = lines.rindex { |l| l.rstrip.end_with?("| #{branch} |") }
      return log_text unless row

      lines[row] = "#{lines[row].rstrip} #{cell.tr('|', '/')} |\n"
      lines.join
    end

    # True only when the set of server addresses in the deploy file equals the drill's app server
    # addresses - no fewer (a partial match is not the drill), no more (a live server mixed in).
    def targets_drill?(deploy_file_text, drill_ips)
      listed = deploy_file_text.to_s.scan(SERVER_LINE).flatten.uniq.sort
      expected = Array(drill_ips).compact.map(&:to_s).uniq.sort
      expected.any? && listed == expected
    end
  end
end

# frozen_string_literal: true

module Dr
  # Everything a DR run report shows, computed once from what the run recorded
  # (openspec dr-drill-report-redesign). The HTML and Markdown renderers both read this model, so
  # the two copies can never disagree about sections, order or numbers.
  #
  # Pure: takes the run's phases, parsed verify scorecard and evidence as plain values. Never
  # reads files, ENV or globals - AwsUtils#write_dr_report gathers those and passes them in.
  module ReportModel
    Model = Data.define(:passed, :drill, :headline, :subline, :tiles, :plain_words, :objectives, :attention,
                        :steps, :hosts, :groups, :verified, :scope, :evidence, :glossary, :generated)

    # Section headings, in order: both renderers print exactly these (the feature compares them)
    SECTIONS = ["In plain words", "Recovery point and time vs what we promise clients", "Needs attention", "What the recovery did, step by step",
                "Verification: what was proven", "What the rebuild time does and does not include",
                "Proof you can check yourself", "Words used in this report"].freeze

    # The verify scorecard's icons, as statuses (⚠️ may carry a variation selector)
    STATUS = { "✅" => :ok, "⚠️" => :warn, "⚠" => :warn, "❌" => :fail }.freeze

    module_function

    # phases: [[title, started, ended]]; scorecard: {host => [[icon, "label — detail"]]};
    # evidence: {claim => [evidence, how_to_check]}
    # recovery_point: {full:, incr:, at:} - the backup chain the restore used (AwsUtils#parse_recovery_point)
    def build(phases:, scorecard:, evidence:, result:, stack:, region:, env_variant:, branch:,
              started_at:, finished:, drill:, teardown:, executed_by:, recovery_point: nil)
      passed = result.to_s.match?(/PASSED|COMPLETE/)
      checks = parse_checks(scorecard)
      steps = build_steps(phases, passed)
      data_age = data_age_hours(checks)
      # RPO achieved: minutes between the recovery point and the start of the recovery (the
      # "disaster"); without a known recovery point, the age of the newest restored record
      rpo_minutes = if recovery_point&.dig(:at) then ((started_at - recovery_point[:at]) / 60).round
                    elsif data_age then (data_age * 60).round
                    end
      objectives = objectives(passed, finished - started_at, rpo_minutes, recovery_point, steps)

      Model.new(
        passed: passed, drill: drill,
        headline: headline(passed, stack, region, finished - started_at, steps),
        subline: "#{drill ? 'DR drill' : 'Real recovery'} · #{stack} (#{env_variant}) → #{region} · " \
                 "#{started_at.utc.strftime('%-d %b %Y, %H:%M')}–#{finished.utc.strftime('%H:%M')} UTC · run by #{executed_by}",
        tiles: tiles(finished - started_at, phases, checks, rpo_minutes, recovery_point),
        plain_words: plain_words(passed, drill, teardown, stack, region, checks, data_age, steps, rpo_minutes, recovery_point) +
                   missed_promises(passed, objectives),
        objectives: objectives,
        # On a failed run the failed step already says why; missed promises are listed for passed runs
        attention: by_severity((passed ? objective_attention(objectives) : []) + attention(passed, steps, checks, scorecard.keys, branch)),
        steps: steps, hosts: scorecard.keys,
        groups: groups(checks, scorecard.keys), verified: checks.any?,
        scope: SCOPE, evidence: evidence.map { |claim, (ev, how)| [claim, ev, how] },
        glossary: glossary(branch), generated: finished.utc.strftime("%-d %b %Y %H:%M UTC")
      )
    end

    # One record per (host, check): catalog entry, shown name, status and the detail text
    def parse_checks(scorecard)
      scorecard.flat_map do |host, lines|
        lines.map do |icon, line|
          # verify prints "label — detail"; only the FIRST " — " separates them
          label, detail = line.split(" — ", 2)
          entry, name = ReportCatalog.check(label.strip)
          { host: host, entry: entry, name: name, status: STATUS.fetch(icon.strip, :warn), detail: detail.to_s.strip }
        end
      end
    end

    # The run's steps with plain names, times and bar widths (share of the total, min 1%)
    def build_steps(phases, passed)
      total = phases.sum { |_, s, e| e ? e - s : 0 }.to_f
      phases.each_with_index.map do |(title, started, ended), i|
        entry = ReportCatalog.step(title)
        secs = ended ? (ended - started).round : nil
        last_and_failed = !passed && i == phases.size - 1
        { n: i + 1, name: entry[:name], does: entry[:does], if_fails: entry[:if_fails],
          start: started.utc.strftime("%H:%M:%S"), took: secs ? hms(secs) : "—",
          pct: secs && total.positive? ? [(secs / total * 100).round, 1].max : 0,
          ok: !last_and_failed }
      end
    end

    def headline(passed, stack, region, seconds, steps)
      return "#{stack.capitalize} recovered in #{region} and verified: #{hms(seconds.round)}" if passed

      # X1 — say where it stopped, by the step's plain name
      stopped = steps.last
      stopped ? "Recovery stopped at step #{stopped[:n]} · #{stopped[:name]}" : "Recovery failed before its first step"
    end

    def tiles(seconds, phases, checks, rpo_minutes, recovery_point)
      db = phases.find { |t, _, _| t.include?("Restore the database") }
      ok = checks.count { |c| c[:status] == :ok }
      failed = checks.count { |c| c[:status] == :fail }
      warned = checks.count { |c| c[:status] == :warn }
      [
        [hms(seconds.round), "Recovery time (RTO): command start to verified · promised ~#{ReportCatalog::PROMISES[:rto_minutes]} min"],
        [db&.dig(2) ? hms((db[2] - db[1]).round) : "—", "Database restore (primary + replica together)"],
        [checks.any? ? "#{ok} / #{checks.size}" : "—", "Checks passed · #{warned} warning#{'s' unless warned == 1} · #{failed} failed"],
        [rpo_minutes ? "#{rpo_minutes} min" : "—",
         "Recovery point (RPO): data lost#{" · restored to #{recovery_point[:at].strftime('%H:%M')} UTC" if recovery_point&.dig(:at)} · promised #{ReportCatalog::PROMISES[:rpo_minutes]} min"]
      ]
    end

    # The restored data's age ("newest users/documents row is 0.4h old"). Take the OLDEST reading:
    # servers are checked one after another with traffic back on, so a later server can see rows
    # written since the restore (2026-11-08: 0.4 h, then 0.0 h) - the minimum would understate loss.
    def data_age_hours(checks)
      ages = checks.select { |c| c[:name] == "Restored data age" }.filter_map { |c| c[:detail][/([\d.]+)h old/, 1]&.to_f }
      ages.max
    end

    def plain_words(passed, drill, teardown, stack, region, checks, data_age, steps, rpo_minutes, recovery_point)
      words = []
      if passed
        words << "The whole #{stack} environment was rebuilt from scratch in #{region}, the disaster-recovery region, from the same backups a real recovery would use."
        servers = checks.pluck(:host).uniq.size
        words << "Each of the #{servers} app servers was checked end to end: web, background jobs, database, search and file storage, all through the app."
        attention = checks.reject { |c| c[:status] == :ok }.pluck(:name).uniq.size
        words << (attention.zero? ? "Every check passed." : "#{attention} check#{'s' unless attention == 1} need#{'s' if attention == 1} attention — see below.")
      else
        stopped = steps.last
        words << "The rebuild of #{stack} in #{region} stopped at step #{stopped&.dig(:n)} (#{stopped&.dig(:name)})."
        words << (checks.any? ? "Some checks ran; the failed ones are listed below." : "It stopped before verification, so no checks ran.")
      end
      # The search rebuild runs in the background and the run does not wait for it
      words << "Search is being rebuilt in the background: the site works now, and search results fill in over the next few minutes." if checks.any? { |c| c[:name] == "Search index populated" && c[:detail].match?(/queued in the background|rebuilding in the background/) }
      if recovery_point&.dig(:at) && rpo_minutes
        words << "The database was recovered as it was at #{recovery_point[:at].strftime('%H:%M')} UTC (the newest backup), #{rpo_minutes} minutes before the recovery started. That is the data a real recovery at this moment would have lost."
      elsif data_age
        words << "Data came back #{data_age} hours old. That is how much a real recovery at this moment would have lost."
      end
      words << if drill
                 ending = teardown && passed ? ", and the rebuilt servers were deleted afterwards." : ". The rebuilt servers are still running until they are torn down."
                 "This was a drill: the live site was not touched and nothing was switched over#{ending}"
               else
                 "This was a real recovery. Users reach it once DNS is switched to it (rake aws:dns_cutover)."
               end
      words
    end

    # The two recovery objectives against what CapHive promises clients (ReportCatalog::PROMISES)
    def objectives(passed, seconds, rpo_minutes, recovery_point, steps)
      promise = ReportCatalog::PROMISES
      point = if recovery_point&.dig(:at)
                "restored to #{recovery_point[:at].strftime('%-d %b %H:%M')} UTC (backup #{recovery_point[:incr] || recovery_point[:full]}): #{rpo_minutes} min of changes lost"
              elsif rpo_minutes
                "#{rpo_minutes} min (age of the newest restored record)"
              end
      rto = (seconds / 60.0).round(1)
      [
        { name: "Recovery point (RPO)", meaning: "How much data a real recovery would lose",
          promised: promise[:rpo_text], achieved: point || "not reached: the run stopped before the restore",
          status: if rpo_minutes.nil?
                    :fail
                  elsif rpo_minutes <= promise[:rpo_minutes]
                    :ok
                  else
                    :warn
                  end,
          todo: "The recovery point is the newest backup: check the live box's backup cadence (the promise needs a backup at least every #{promise[:rpo_minutes]} min) and that the backup-freshness alert was green." },
        { name: "Recovery time (RTO)", meaning: "How long until users are served again",
          promised: promise[:rto_text],
          achieved: passed ? "#{hms(seconds.round)} from the recovery command to a verified, serving stack" : "not reached: stopped at step #{steps.last&.dig(:n)} · #{steps.last&.dig(:name)}",
          status: if !passed
                    :fail
                  elsif rto <= promise[:rto_minutes]
                    :ok
                  else
                    :warn
                  end,
          todo: "See the slowest steps in the timeline below; the restore scales with database size." }
      ]
    end

    # One plain sentence when a passed run missed a promise to clients
    def missed_promises(passed, objectives)
      missed = objectives.select { |o| o[:status] == :warn }.pluck(:name)
      return [] if !passed || missed.empty?

      ["It did not meet what we promise clients for the #{missed.join(' and the ')} — see below."]
    end

    # Failures before warnings, keeping each group's own order (the failed step stays first)
    def by_severity(items)
      items.each_with_index.sort_by { |item, i| [item[:status] == :fail ? 0 : 1, i] }.map(&:first)
    end

    # A missed promise, as a Needs attention item
    def objective_attention(objectives)
      objectives.reject { |o| o[:status] == :ok }.map do |o|
        { status: o[:status], name: "#{o[:name]} #{o[:status] == :fail ? 'not reached' : 'not met'}", hosts: "—",
          means: "Promised: #{o[:promised]}. This run: #{o[:achieved]}.", todo: o[:todo] }
      end
    end

    # Failed step first, then failed checks, then warnings; each check once, naming its servers
    def attention(passed, steps, checks, hosts, branch)
      items = []
      if !passed && (stopped = steps.last)
        items << { status: :fail, name: "Step #{stopped[:n]} · #{stopped[:name]}", hosts: "—",
                   means: "The recovery stopped here.",
                   todo: [stopped[:if_fails], "Full output: docs/operations/dr/runs/#{branch}.log"].compact.join(" ") }
      end
      %i[fail warn].each do |status|
        checks.select { |c| c[:status] == status }.group_by { |c| c[:name] }.each do |name, same|
          items << { status: status, name: name, hosts: hosts_label(same.map { |c| c[:host] }.uniq, hosts),
                     means: means(same.first[:entry][:proves], same.map { |c| c[:detail] }.uniq.reject(&:empty?)),
                     todo: same.first[:entry][:if_fails] || "See the transcript for this check." }
        end
      end
      items
    end

    # "Should be: <what a pass proves> Found: <what the servers reported>"
    def means(proves, details)
      found = details.empty? ? nil : "Found: #{details.join(' / ')}"
      [proves && "Should be: #{proves}", found].compact.join(" ")
    end

    def hosts_label(seen, all)
      return "both servers" if all.size == 2 && seen.sort == all.sort
      return "all #{all.size} servers" if all.size > 2 && seen.sort == all.sort

      seen.join(", ")
    end

    # Groups in catalog order; within a group, rows in catalog order; one cell per server
    def groups(checks, hosts)
      order = ReportCatalog::CHECKS.each_with_index.to_h { |e, i| [e, i] }
      ReportCatalog::GROUPS.filter_map do |group|
        in_group = checks.select { |c| c[:entry][:group] == group }
        next if in_group.empty?

        rows = in_group.group_by { |c| c[:name] }.map do |name, same|
          { name: name, proves: same.first[:entry][:proves], rank: order.fetch(same.first[:entry], order.size),
            cells: hosts.to_h { |h| (c = same.find { |x| x[:host] == h }) ? [h, [c[:status], c[:detail]]] : [h, nil] } }
        end
        { name: group, rows: rows.sort_by { |r| r[:rank] } }
      end
    end

    SCOPE = {
      included: ["Creating the servers", "Installing the app", "Restoring the database", "Rebuilding search", "Every check above"],
      excluded: ["Noticing the outage", "Deciding to recover", "Switching the domain to the new servers (DNS) and the minutes it takes to spread"]
    }.freeze

    def glossary(branch)
      [["Drill", "A rehearsal: the same steps as a real recovery, in a separate copy, with the live site untouched."],
       ["Rebuild time", "From starting the recovery command to every check passing."],
       ["Recovery point (RPO)", "The moment the data was recovered to (the newest backup); the minutes between it and the start of the recovery are the data a real recovery would lose."],
       ["Recovery time (RTO)", "How long until users are served again. The figure here is the rebuild, from the recovery command to a verified stack; noticing the outage, deciding to recover and the DNS switch come on top."],
       ["Armed", "A database allowed to write backups. Exactly one may, and in a drill none."],
       ["Full transcript", "docs/operations/dr/runs/#{branch}.log: every command and its output."]]
    end

    def hms(seconds)
      format("%d:%02d", seconds / 60, seconds % 60)
    end
  end
end

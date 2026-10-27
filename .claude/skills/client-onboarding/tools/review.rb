# Manual review gate (SKILL.md hard rule 10): no upload file reaches the app until ops has looked at THAT exact file.
#   dump      copies every built upload file (out/fund, out/portfolio: *.xlsx, *.json) into <workspace>/review/ and writes
#             review/REVIEW.md — per file: rows, columns, money totals, date range, SHA-256 and whether it is approved
#   status    which files are approved, which wait for review, which changed since they were approved
#   summary   one line per file waiting for review (rows, money totals) — what Claude shows ops in the review question
#   approve   records a file's SHA-256 + who approved it + how (--via) in review/approved.yml; --all approves every file
#             that is waiting or changed. Ops approves by answering Claude's review question in the session (2026-10-27:
#             "approval should be from here"); Claude runs approve ONLY with ops' answer, quoted in --via, never on its own
# Library: Onboarding::Review.check!(workspace, path) — api.rb (every upload) and onboard.rb (every JSON post) call it and
# stop unless the file's current hash is approved. A rebuild that changes a file changes its hash → it needs review again.
# Waiver: onboarding.yml `review: {waived_by: <ops>, waived_on: <date>, reason: …}` — only on ops' explicit word for that
# client; files are still dumped, and every gated write prints a ⚠ REVIEW WAIVED banner.
#
# Usage: ruby review.rb [--workspace DIR] dump | status | summary | approve <file> | --all --summary <code> --by <name> --via "<how ops approved>"
require "digest"
require "fileutils"
require "json"
require "yaml"
require "date"
require "roo"

module Onboarding
  module Review
    module_function

    def dir(ws) = File.join(ws, "review")
    def approved_path(ws) = File.join(dir(ws), "approved.yml")
    def sha(path) = Digest::SHA256.file(path).hexdigest
    # Key = path relative to the workspace (out/fund/05b_remittances.xlsx), so a copy elsewhere is not mistaken for it
    def key(ws, path) = File.expand_path(path).delete_prefix("#{File.expand_path(ws)}/")
    def approvals(ws) = File.exist?(approved_path(ws)) ? (YAML.safe_load_file(approved_path(ws), permitted_classes: [Date, Time]) || {}) : {}

    def waiver(ws)
      cfg = YAML.safe_load_file(File.join(ws, "onboarding.yml"), permitted_classes: [Date])
      w = cfg["review"]
      w if w.is_a?(Hash) && w["waived_by"].to_s != "" && w["waived_on"].to_s != ""
    end

    # The upload files the builders write
    def built_files(ws) = Dir[File.join(ws, "out", "{fund,portfolio}", "**", "*.{xlsx,json}")].sort

    def state(ws, path)
      a = approvals(ws)[key(ws, path)]
      return :waiting unless a

      a["sha256"] == sha(path) ? :approved : :changed
    end

    # Stops the calling tool unless this exact file was approved (or review is waived for the client)
    def check!(ws, path)
      if (w = waiver(ws))
        warn "⚠ REVIEW WAIVED (by #{w['waived_by']} on #{w['waived_on']}): #{key(ws, path)} goes to the app without manual review"
        return
      end
      case state(ws, path)
      when :approved then nil
      when :changed then abort "✖ #{key(ws, path)} changed since it was approved — dump it (ruby review.rb dump) and have ops review it again"
      else abort "✖ awaiting manual review: #{key(ws, path)} — copy in review/; ops approves it in the session (review.rb summary → ops' answer → approve)"
      end
    end

    # One line of facts per sheet: rows, columns, Σ of each numeric column, date range — what ops checks against the source
    def describe(path)
      return describe_json(path) if path.end_with?(".json")

      book = Roo::Spreadsheet.open(path)
      book.sheets.map do |name|
        s = Roo::Spreadsheet.open(path).tap { _1.default_sheet = name } # sheet() returns the same object — open per sheet
        next "- sheet **#{name}**: empty" unless s.last_row

        headers = s.row(1)
        rows = (2..s.last_row).map { s.row(_1) }
        sums = headers.each_with_index.filter_map do |h, i|
          vals = rows.map { _1[i] }.grep(Numeric)
          "#{h} Σ #{format('%.2f', vals.sum)}" if vals.size.positive? && vals.size >= rows.size / 2
        end
        dates = rows.flat_map { |r| r.grep(Date) }
        "- sheet **#{name}**: #{rows.size} rows · columns: #{headers.compact.join(', ')}" \
          "#{"\n  - totals: #{sums.join(' · ')}" if sums.any?}#{"\n  - dates: #{dates.min} → #{dates.max}" if dates.any?}"
      end.join("\n")
    end

    def describe_json(path)
      data = JSON.parse(File.read(path))
      "- JSON: #{data.is_a?(Array) ? "#{data.size} items" : "keys #{data.keys.join(', ')}"}\n\n```json\n#{JSON.pretty_generate(data)[0, 1500]}\n```"
    end

    def dump(ws)
      FileUtils.mkdir_p(dir(ws))
      files = built_files(ws)
      md = ["# Upload files for manual review", "",
            "Generated #{Time.now.strftime('%Y-%m-%d %H:%M')}. Each file below is a copy of what will be sent to the app. Check rows, totals and",
            "dates against the client's source (the mapping is in `mappings/*.yml`), then approve each file:",
            "ops approves by answering Claude's review question in the session (recorded with `via:` in review/approved.yml). A file",
            "rebuilt after approval needs approving again.", ""]
      w = waiver(ws)
      md += ["> ⚠ Review waived for this client by #{w['waived_by']} on #{w['waived_on']}#{" — #{w['reason']}" if w['reason']}. Files are dumped for inspection only.", ""] if w
      files.each do |f|
        k = key(ws, f)
        dest = File.join(dir(ws), k.delete_prefix("out/"))
        FileUtils.mkdir_p(File.dirname(dest))
        FileUtils.cp(f, dest)
        st = state(ws, f)
        md += ["## #{k}", "", "Status: #{{ approved: '✅ approved', changed: '⚠ changed since approval', waiting: '⏳ waiting for review' }[st]} · SHA-256 `#{sha(f)[0, 16]}…` · copy: `review/#{k.delete_prefix('out/')}`", "",
               describe(f), ""]
      end
      File.write(File.join(dir(ws), "REVIEW.md"), md.join("\n"))
      puts "#{files.size} files copied to #{dir(ws)}/ · #{File.join(dir(ws), 'REVIEW.md')}"
      files
    end

    # Files still to review: never approved, or changed since (a rebuild changes the hash)
    def pending(ws) = built_files(ws).reject { state(ws, _1) == :approved }

    # A short code for exactly these files at their current hashes. `summary` prints it with the list ops is asked about;
    # `approve --all --summary <code>` refuses if anything was rebuilt or added since, so ops' answer covers only what
    # ops was shown
    def set_code(ws, files) = Digest::SHA256.hexdigest(files.map { "#{key(ws, _1)}=#{sha(_1)}" }.sort.join("\n"))[0, 12]

    # One short line per file for the review question: rows and the money columns' totals (sheet 1), or the JSON's shape
    def summary_line(path)
      if path.end_with?(".json")
        data = JSON.parse(File.read(path))
        return data.is_a?(Array) ? "#{data.size} items" : (data["name"] || data.dig("fund", "name") || data.dig("form_type", "name") || "#{data.size} keys").to_s
      end
      s = Roo::Spreadsheet.open(path).sheet(0)
      return "empty" unless s.last_row

      headers = s.row(1)
      rows = (2..s.last_row).map { s.row(_1) }
      money = headers.each_with_index.filter_map do |h, i|
        next unless h.to_s.match?(/amount|income|face value|committed/i) && !h.to_s.match?(/fund currency/i)

        vals = rows.map { _1[i] }.grep(Numeric)
        "#{h.to_s.sub(/ \(.*\)\z/, '')} Σ #{format('%.2f', vals.sum)}" if vals.any?
      end
      ["#{rows.size} rows", *money.first(2)].join(" · ")
    end

    # Records ops' approval of this exact file. `via` says how ops approved — for a session approval, ops' own answer — so
    # an audit can tell who said what; there is no approval without it
    def approve(ws, path, by, via)
      abort "✖ approve needs --by <name>" if by.to_s.strip.empty?
      abort "✖ approve needs --via \"<how ops approved, e.g. their answer in the session>\"" if via.to_s.strip.empty?
      abort "✖ no such file #{path}" unless File.exist?(path)
      a = approvals(ws)
      a[key(ws, path)] = { "sha256" => sha(path), "approved_by" => by, "approved_at" => Time.now.iso8601, "via" => via }
      FileUtils.mkdir_p(dir(ws))
      File.write(approved_path(ws), a.to_yaml)
      puts "✔ approved #{key(ws, path)} (#{sha(path)[0, 16]}…) by #{by}"
    end
  end
end

# Guarded on the feature, not just $PROGRAM_NAME: api.rb requires this file, so it can load a second time while it runs as
# the script — the CLI must run once. --workspace is parsed here (not via api.rb, which would require this file again)
if $PROGRAM_NAME == __FILE__ && !defined?(REVIEW_CLI_RAN)
  REVIEW_CLI_RAN = true
  i = ARGV.index("--workspace")
  ws = File.expand_path(i ? ARGV.slice!(i, 2).last : ENV.fetch("ONBOARDING_WORKSPACE", Dir.pwd))
  case ARGV.shift
  when "dump" then Onboarding::Review.dump(ws)
  when "status"
    Onboarding::Review.built_files(ws).each do |f|
      st = Onboarding::Review.state(ws, f)
      puts format("  %s %s", { approved: "✅", changed: "⚠ changed", waiting: "⏳" }[st], Onboarding::Review.key(ws, f))
    end
    (w = Onboarding::Review.waiver(ws)) && puts("  ⚠ review waived by #{w['waived_by']} on #{w['waived_on']}")
  when "summary"
    files = Onboarding::Review.pending(ws)
    puts(files.empty? ? "nothing waiting for review" : "#{files.size} file(s) waiting for review — copies in review/, detail in review/REVIEW.md")
    files.each { |f| puts format("  %-40s %s", Onboarding::Review.key(ws, f).delete_prefix("out/"), Onboarding::Review.summary_line(f)) }
    puts "summary code: #{Onboarding::Review.set_code(ws, files)}  (approve --all needs it: --summary <code>)" if files.any?
  when "approve"
    by = (i = ARGV.index("--by")) && ARGV.slice!(i, 2).last
    via = (i = ARGV.index("--via")) && ARGV.slice!(i, 2).last
    code = (i = ARGV.index("--summary")) && ARGV.slice!(i, 2).last
    # --all: every file still waiting or changed — and only if that is still exactly the list `summary` showed ops
    if ARGV.delete("--all")
      paths = Onboarding::Review.pending(ws)
      abort "nothing waiting for review" if paths.empty?
      abort "✖ approve --all needs --summary <code> from the `summary` ops was shown" if code.to_s.empty?
      if Onboarding::Review.set_code(ws, paths) != code
        abort "✖ the files changed since ops was asked (rebuilt or added) — run `review.rb summary` again and ask ops about the new list"
      end
    else
      paths = [File.expand_path(ARGV.shift.to_s, ws)]
    end
    paths.each { Onboarding::Review.approve(ws, _1, by, via) }
  else
    abort File.read(__FILE__).lines.grep(/^# Usage/).join
  end
end

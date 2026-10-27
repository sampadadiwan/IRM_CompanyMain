# Onboarding API client — the ONLY way the onboarding tools change CapHive: the website's existing .json endpoints with
# the ops user's bearer token (devise-api). Usable as a library (require_relative "api") and as a CLI.
#
# Settings come from the client workspace (never from this repo):
#   <workspace>/onboarding.yml   base_url, entity_id, ops_email
#   <workspace>/state/token      the bearer token (written by `sign_in` on dev, or pasted from Profile › API tokens)
# The workspace is --workspace DIR, else $ONBOARDING_WORKSPACE, else the current directory.
#
# CLI:
#   ruby api.rb [--workspace DIR] sign_in                       dev only; password from $OPS_PASSWORD
#   ruby api.rb [--workspace DIR] get <path>
#   ruby api.rb [--workspace DIR] post|patch|delete <path> [json]
#   ruby api.rb [--workspace DIR] upload <ImportType> <file> [gate step] [--resend <id>]   POST /import_uploads.json, then
#                                   watches it to the end (exit 0 only when every row went in; watches an upload of this file
#                                   still running instead of sending it twice; exit 2 when nothing has moved for 10 minutes).
#                                   --resend <id>: send the file even though upload <id> still shows running — only on ops'
#                                   word that its job died (rows it already imported stay in the app)
#   ruby api.rb [--workspace DIR] attach <OwnerType> <id> <name> <file>   POST /documents.json (e.g. a company "Logo")
#   ruby api.rb [--workspace DIR] sandbox_on                    first write of every onboarding
require "net/http"
require "json"
require "yaml"
require "date"
require "time"
require "securerandom"
require "openssl" # named in the watch loop's rescue
require_relative "gate"
require_relative "review"
require_relative "ui"

module Onboarding
  # Content types for multipart uploads, by file extension
  MIME = { ".xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", ".png" => "image/png",
           ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg", ".pdf" => "application/pdf" }.freeze

  class Api
    attr_reader :workspace, :base_url, :entity_id, :ops_email, :client, :last_headers

    # The sandbox guard re-reads the entity at most this often per process (it used to GET it before every write)
    SANDBOX_RECHECK_SECONDS = 60

    # Pulls "--workspace DIR" out of argv (if present) so every tool accepts it the same way
    def self.workspace_from!(argv)
      i = argv.index("--workspace")
      dir = i ? argv.slice!(i, 2).last : ENV.fetch("ONBOARDING_WORKSPACE", Dir.pwd)
      File.expand_path(dir)
    end

    def initialize(workspace)
      @workspace = workspace
      config_path = File.join(workspace, "onboarding.yml")
      abort "no #{config_path} — create it with base_url, entity_id, ops_email" unless File.exist?(config_path)
      config = YAML.safe_load_file(config_path, permitted_classes: [Date]) # dates such as check_data_approved_on
      @base_url = config.fetch("base_url")
      @entity_id = Integer(config.fetch("entity_id"))
      @ops_email = config.fetch("ops_email")
      @client = config["client"]
    end

    # The fund this workspace onboards (mappings/drawdowns.yml), nil for a portfolio-only workspace
    def fund_name
      path = File.join(workspace, "mappings", "drawdowns.yml")
      File.exist?(path) ? YAML.safe_load_file(path, permitted_classes: [Date]).dig("fund", "name") : nil
    end

    def token_path = File.join(workspace, "state", "token")
    # "bom|utf-8": Windows Notepad can save the pasted token with a byte-order mark, which strip does not remove
    def token = File.read(token_path, encoding: "bom|utf-8").strip

    # One HTTP call; returns [status, parsed body or raw text]. Every write first passes the checks below, and there is
    # no flag to skip them — the one write allowed before sandbox is on is #sandbox_on!.
    def call(method, path, body: nil, multipart: nil, auth: true)
      # One spelling for the checks: "POST" and "post", "/import_uploads.json", "/import_uploads/" all name the same call
      method = method.to_s.downcase
      # (from the raw text, not URI(): URI reads a leading "//" as a host name and the path would come out empty)
      route = path.to_s.split(/[?#]/).first.to_s.downcase.squeeze("/").chomp("/").delete_suffix(".json")
      if auth && method != "get"
        # Must-have gate (hard rule 9): creating the fund and anything on investor access need the client's answers
        Onboarding::Gate.check!(workspace, :fund) if method == "post" && route == "/funds"
        Onboarding::Gate.check!(workspace, :investor_access) if route.include?("investor_access")
        # Manual review (hard rule 10): an import upload goes in only if ops approved this exact file. Checked here, not in
        # the CLI, so a workspace script posting to /import_uploads itself is refused too
        if method == "post" && route == "/import_uploads"
          files = multipart.to_h.values.grep(File)
          abort "refusing POST #{path}: no import file attached" if files.empty?
          files.each { |f| Onboarding::Review.check!(workspace, f.path) }
        end
        # Sandbox (hard rule 4): the entity must still be in sandbox; re-read at most once a minute
        unless @sandbox_ok_at && Time.now - @sandbox_ok_at < SANDBOX_RECHECK_SECONDS
          _, ent = call("get", "/entities/#{entity_id}.json")
          abort "refusing #{method.upcase} #{path}: sandbox is not on for entity #{entity_id}" unless ent.is_a?(Hash) && ent.dig("entity_setting", "sandbox") == true
          @sandbox_ok_at = Time.now
        end
      end
      send_request(method, path, body:, multipart:, auth:)
    end

    # The first write of every onboarding (hard rule 4): turns sandbox on, so it is the only write that skips the
    # sandbox check in #call — sandbox is still off when it runs
    def sandbox_on!
      send_request("patch", "/entities/#{entity_id}.json",
                   body: { entity: { entity_setting_attributes: { sandbox: true, sandbox_emails: ops_email } } })
    end

    # The HTTP request itself, with no checks — private so tools and workspace scripts go through #call
    private def send_request(method, path, body: nil, multipart: nil, auth: true)
      uri = URI("#{base_url}#{path}")
      req = Net::HTTP.const_get(method.capitalize).new(uri)
      req["Accept"] = "application/json"
      req["Authorization"] = "Bearer #{token}" if auth
      if multipart
        boundary = "----onboarding#{SecureRandom.hex(8)}"
        req["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
        # Built as raw bytes: the file is binary and a name or value may not be ASCII (a client's file name, "·" in the
        # upload name) — joining UTF-8 text with binary content raises Encoding::CompatibilityError
        req.body = multipart.map do |name, value|
          if value.is_a?(File)
            "--#{boundary}\r\nContent-Disposition: form-data; name=\"#{name}\"; filename=\"#{File.basename(value.path)}\"\r\n".b +
              "Content-Type: #{MIME.fetch(File.extname(value.path).downcase, 'application/octet-stream')}\r\n\r\n".b + value.read.b + "\r\n".b
          else
            "--#{boundary}\r\nContent-Disposition: form-data; name=\"#{name}\"\r\n\r\n#{value}\r\n".b
          end
        end.join.b + "--#{boundary}--\r\n".b
      elsif body
        req["Content-Type"] = "application/json"
        req.body = body.to_json
      end
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: 300) { |h| h.request(req) }
      @last_headers = res.to_hash # e.g. total-count on paged fund lists (see #count)
      parsed = begin
        JSON.parse(res.body.to_s)
      rescue JSON::ParserError
        res.body.to_s[0, 300]
      end
      [res.code.to_i, parsed]
    end

    # GET a list endpoint; raises unless it answers 200 with an array
    def list(path)
      status, body = call("get", path)
      raise "#{path} → HTTP #{status}" unless status == 200 && body.is_a?(Array)

      body
    end

    # Row count of a paged list without reading it: one row (per_page=1) and the list's total-count header.
    # Fund lists send it to API callers (remittances, payments, commitments, calls, distribution payments); a list
    # without it (investors, account entries) raises — read those with #list
    def count(path)
      status, = call("get", "#{path}#{path.include?('?') ? '&' : '?'}per_page=1")
      raise "#{path} → HTTP #{status}" unless status == 200

      Integer(last_headers&.dig("total-count", 0) || raise("#{path} sends no total-count header — use list"))
    end

    # Polls a block until it returns the same truthy value twice in a row (a background job has settled). With a label
    # it shows progress: with `remaining_of:` the block's value is what is left of that total (counts down to 0), else
    # the value itself is shown (e.g. a KPI count, units issued). `grace:` seconds: while the value is still the first
    # reading, it does not count as settled — a job Sidekiq has not picked up yet looks exactly like one that finished
    def wait_until_stable(every: 10, tries: 60, label: nil, remaining_of: nil, unit: "", grace: 0)
      progress = label && Onboarding::UI::Progress.new(label, total: remaining_of, unit:)
      previous = first = nil
      started = Time.now
      tries.times do |n|
        current = yield
        first = current if n.zero?
        progress&.update(remaining_of && current ? [remaining_of - current.to_i, 0].max : current)
        not_started = current == first && Time.now - started < grace
        if current && current == previous && !not_started
          progress&.finish
          return current
        end

        previous = current
        progress ? progress.sleep(every) : sleep(every)
      end
      progress&.finish
      previous
    end
  end
end

# ── CLI ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
if $PROGRAM_NAME == __FILE__
  api = Onboarding::Api.new(Onboarding::Api.workspace_from!(ARGV))
  case ARGV[0]
  when "sign_in"
    # Dev only: production tokens are issued by ops (Profile › API tokens) and pasted into state/token
    password = ENV.fetch("OPS_PASSWORD") { abort "set OPS_PASSWORD (dev only)" }
    status, body = api.call("post", "/users/tokens/sign_in", body: { email: api.ops_email, password: }, auth: false)
    abort "sign_in failed: #{status}" unless status == 200
    Dir.mkdir(File.dirname(api.token_path)) unless Dir.exist?(File.dirname(api.token_path))
    File.write(api.token_path, body["token"])
    File.chmod(0o600, api.token_path)
    puts "signed in as #{body.dig('resource_owner', 'email')} (user #{body.dig('resource_owner', 'id')}), expires in #{body['expires_in']}s"
  when "get"
    status, body = api.call("get", ARGV[1])
    puts "HTTP #{status}"
    puts(body.is_a?(String) ? body : JSON.pretty_generate(body))
  when "post", "patch", "delete"
    status, body = api.call(ARGV[0], ARGV[1], body: ARGV[2] && JSON.parse(ARGV[2]))
    puts "HTTP #{status} #{body.to_s[0, 300]}"
  when "sandbox_on"
    status, body = api.sandbox_on!
    puts "HTTP #{status} #{body.is_a?(Hash) ? body.slice('id', 'name') : body}"
  when "upload"
    ui = Onboarding::UI
    # Sounds for ops when run on its own; under onboard.rb (ONBOARDING_CHILD=1) the step plays one at its end instead
    chime = ->(kind) { ui.chime(kind) unless ENV["ONBOARDING_CHILD"] == "1" }
    # --resend <id>: ops says upload <id> died, so it no longer stops this file being sent (see the stall message)
    resend = (at = ARGV.index("--resend")) && Integer(ARGV.slice!(at, 2)[1].to_s, exception: false)
    abort "✖ --resend needs the id of the upload whose job died, e.g. --resend 2733" if at && resend.nil?
    type, file, step = ARGV[1], ARGV[2], ARGV[3]
    # Must-have gate by import type (Investor/CapitalCommitment → commitments, calls/remittances/payments → drawdowns, …);
    # an explicit step wins where one type serves two steps (portfolio companies are an Investor import → portfolio)
    (step ||= Onboarding::Gate::IMPORT_STEP[type]) && Onboarding::Gate.check!(api.workspace, step.to_sym)
    # The name says which onboarding sent it: builders use the same file names for every fund, and uploads belong to the
    # entity, so two funds in one entity would otherwise mistake each other's uploads for their own
    owner = api.fund_name || api.client
    legacy_name = "#{type} #{File.basename(file)}" # the name before 2026-10-27, without the fund / client
    name = "#{legacy_name}#{" · #{owner}" if owner}"
    # Never upload twice: a rerun while the app is still importing this file (a closed laptop stops only the watching,
    # not the import) would add every row again — watch that upload instead. An upload sent under the old name counts too
    uploads = begin
      api.list("/import_uploads.json?q%5Bimport_type_eq%5D=#{type}")
    rescue RuntimeError => e
      raise unless e.message.include?("HTTP 401")

      ui.say(:token, "Token", "the API token in state/token is not accepted (HTTP 401)", color: :red)
      ui.hints_for("HTTP 401").each { ui.hint(_1) }
      chime.(:fail)
      exit 1
    end
    running = uploads.find { [name, legacy_name].include?(_1["name"]) && _1["outcome"] == "running" && _1["id"] != resend }
    rows = nil
    if running
      id = running["id"]
      ui.say(:watch, "Watching", "upload #{id} (sent #{Time.parse(running['created_at']).localtime.strftime('%H:%M')}) is still importing — not sending the file again")
    else
      # Rows in the file, for the bar until the app counts them — only when sending (a watched upload has the server's
      # count); nil when the file cannot be read here or its sheet is empty
      rows = begin
        last = Roo::Spreadsheet.open(file).sheet(0).last_row
        last && last - 1
      rescue StandardError
        nil
      end
      # The manual review gate (hard rule 10) and the sandbox check run inside api.call
      status, body = api.call("post", "/import_uploads.json", multipart: {
        "import_upload[name]" => name, "import_upload[owner_type]" => "Entity",
        "import_upload[owner_id]" => api.entity_id, "import_upload[entity_id]" => api.entity_id,
        "import_upload[import_type]" => type, "import_upload[import_file]" => File.open(file, "rb")
      })
      unless status == 201
        ui.say(:fail, "Refused", "HTTP #{status} #{body.to_s[0, 300]}", color: :red)
        ui.hints_for("HTTP #{status} #{body}").each { ui.hint(_1) }
        exit 1
      end
      id = body["id"]
      # Every check passed, or api.call would have stopped: say which, so ops sees what was enforced
      approval = Onboarding::Review.approvals(api.workspace)[Onboarding::Review.key(api.workspace, file)]
      checks = [("must-have answers (#{step})" if step),
                approval ? "approved by #{approval['approved_by']} #{Time.parse(approval['approved_at'].to_s).strftime('%d %b %H:%M')}" : "review waived",
                "sandbox on"].compact
      ui.say(:checks, "Checks", checks.map { "#{_1} ✓" }.join(" · "))
      ui.say(:sent, "Sent", "upload #{id} · #{ui.num(rows)} rows — the app is importing it now")
    end
    ui.say(:tip, "", "Big file: the import runs on the server, so this only watches it. If the watch stops, run the step again — it picks this upload back up, never a second one.") if rows.to_i >= 1000
    # Verification from the API only: outcome, counts and the first failed rows ("Completed" alone is not success).
    # Backoff 5 s, 10 s, 20 s, then every 30 s. The watch ends only when nothing has moved for 10 minutes, so a long
    # import that keeps moving is followed to the end
    progress = ui::Progress.new("Importing", total: rows)
    http_error = nil
    (0..).each do |i|
      progress.sleep([5 * (2**i), 30].min)
      st, up = begin
        api.call("get", "/import_uploads/#{id}.json")
      rescue SystemCallError, IOError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError => e
        # The app restarting or the network dropping: keep the last figures, as for a bad status below
        [e.class.name, nil]
      end
      # An expired token is not a stalled import: stop and say so (the import itself keeps running on the server)
      if st == 401
        progress.finish
        ui.say(:token, "Token", "the API token expired while watching upload #{id} — the import itself carries on", color: :red)
        ui.hints_for("HTTP 401").each { ui.hint(_1) }
        chime.(:fail)
        exit 1
      end
      # Any other failed read: keep the last figures (the stall clock keeps running) and say why they are not moving
      unless st == 200 && up.is_a?(Hash)
        http_error = st.is_a?(Integer) ? "the app answered HTTP #{st} to the last poll" : "the last poll got no answer (#{st})"
        next unless progress.stalled_for >= 600

        progress.finish
        ui.say(:stall, "Stalled", "upload #{id}: no answer from the app for 10 min (#{http_error})", color: :yellow)
        ui.hint("Check the app is up, then run the step again — it keeps watching this upload and never sends the file twice.")
        chime.(:fail)
        exit 2
      end
      if up["status"].to_s.empty? || up["outcome"] == "running"
        done, failed, total = up["processed_row_count"].to_i + up["failed_row_count"].to_i, up["failed_row_count"].to_i, up["total_rows_count"].to_i
        # Every row counted but no status yet: the importer's post-processing (e.g. recounts) is still running
        finishing = total.positive? && done >= total
        note = if done.zero? then "queued — waiting for a worker"
               elsif finishing then "all rows counted — finishing up"
               else "#{ui.num(failed)} failed"
               end
        progress.update(done, total:, extra: note)
        # Post-processing moves no counter, so it gets longer before it counts as stalled
        next if progress.stalled_for < (finishing ? 1800 : 600)

        progress.finish
        ui.say(:stall, "Stalled", "upload #{id}: nothing has moved for #{finishing ? 30 : 10} min (#{ui.num(done)} of #{ui.num(total.positive? ? total : rows)} rows)", color: :yellow)
        if done.zero?
          ui.hint("No worker has picked it up — check Sidekiq is running, then run the step again to keep watching.")
        else
          ui.hint("Run the step again to keep watching — it never sends the file a second time while this upload shows running.")
          ui.hint("If ops finds the job died (e.g. Sidekiq restarted), the upload keeps showing \"running\" for a day. Ops can then resend with `ruby api.rb upload #{type} #{file} --resend #{id}` — the #{ui.num(up['processed_row_count'])} rows it already imported stay in the app, so check them first.")
        end
        chime.(:fail)
        exit 2
      end
      progress.finish
      total, processed, failed = up["total_rows_count"].to_i, up["processed_row_count"].to_i, up["failed_row_count"].to_i
      ok = up["outcome"] == "succeeded" && failed.zero?
      if ok
        ui.say(:ok, "Imported", "#{ui.num(processed)} / #{ui.num(total)} rows · 0 failed · upload #{id}", color: :green)
        ui.say(:warn, "Note", up["warning"].to_s[0, 200]) if up["warning"].to_s != ""
      else
        ui.say(:fail, "Import", "#{up['outcome'].to_s.tr('_', ' ')} · #{ui.num(processed)} of #{ui.num(total)} rows went in · #{ui.num(failed)} failed · upload #{id}", color: :red)
        # The first few failed rows (the API keeps a sample, not all), then how many more — the full list is the results file
        errors = Array(up["row_errors"])
        shown = errors.first(5)
        shown.each { |e| puts "   row #{e['row']} · #{e['message'].to_s.delete_prefix('Error ')[0, 200]}" }
        unshown = failed - shown.size
        # Not the results_url itself: it is a pre-signed S3 link (carries an access key id) that would land in logs
        puts "   … and #{ui.num(unshown)} more failed rows — every row is in the results file on upload #{id}'s page" if shown.any? && unshown.positive?
        puts "   #{up['status'].to_s[0, 200]}" if errors.empty? && up["status"].to_s != ""
        ui.hints_for([up["status"], up["error_text"], *Array(up["row_errors"]).map { _1["message"] }].join("\n")).each { ui.hint(_1) }
      end
      ui.say(:ok, "Fields", "custom fields created: #{up['custom_fields_created']}") if up["custom_fields_created"].to_s != ""
      chime.(ok ? :done : :fail)
      # The exit code is the result onboard.rb reads: 0 only when every row went in
      exit(ok ? 0 : 1)
    end
  when "attach"
    owner_type, owner_id, name, file = ARGV[1..4]
    status, body = api.call("post", "/documents.json", multipart: {
      "document[name]" => name, "document[owner_type]" => owner_type, "document[owner_id]" => owner_id,
      "document[file]" => File.open(file, "rb")
    })
    puts "HTTP #{status} #{body.is_a?(Hash) ? body.slice('id', 'name') : body.to_s[0, 300]}"
  else
    abort File.read(__FILE__).lines.grep(/^#   ruby api\.rb/).join
  end
end

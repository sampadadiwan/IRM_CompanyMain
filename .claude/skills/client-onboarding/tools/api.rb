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
#   ruby api.rb [--workspace DIR] upload <ImportType> <file> [gate step]   POST /import_uploads.json, then polls until processed
#   ruby api.rb [--workspace DIR] attach <OwnerType> <id> <name> <file>   POST /documents.json (e.g. a company "Logo")
#   ruby api.rb [--workspace DIR] sandbox_on                    first write of every onboarding
require "net/http"
require "json"
require "yaml"
require "date"
require "securerandom"
require_relative "gate"
require_relative "review"

module Onboarding
  # Content types for multipart uploads, by file extension
  MIME = { ".xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", ".png" => "image/png",
           ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg", ".pdf" => "application/pdf" }.freeze

  class Api
    attr_reader :workspace, :base_url, :entity_id, :ops_email, :last_headers

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
    end

    def token_path = File.join(workspace, "state", "token")
    # "bom|utf-8": Windows Notepad can save the pasted token with a byte-order mark, which strip does not remove
    def token = File.read(token_path, encoding: "bom|utf-8").strip

    # One HTTP call; returns [status, parsed body or raw text]. Every write first re-checks that the entity is
    # still in sandbox (hard rule 4) and stops if it is not.
    def call(method, path, body: nil, multipart: nil, auth: true, guard: true)
      if guard && auth && method != "get"
        # Must-have gate (hard rule 9): creating the fund and anything on investor access need the client's answers
        Onboarding::Gate.check!(workspace, :fund) if method == "post" && path.start_with?("/funds.json")
        Onboarding::Gate.check!(workspace, :investor_access) if path.include?("investor_access")
        unless @sandbox_ok_at && Time.now - @sandbox_ok_at < SANDBOX_RECHECK_SECONDS
          _, ent = call("get", "/entities/#{entity_id}.json", guard: false)
          abort "refusing #{method.upcase} #{path}: sandbox is not on for entity #{entity_id}" unless ent.is_a?(Hash) && ent.dig("entity_setting", "sandbox") == true
          @sandbox_ok_at = Time.now
        end
      end
      uri = URI("#{base_url}#{path}")
      req = Net::HTTP.const_get(method.capitalize).new(uri)
      req["Accept"] = "application/json"
      req["Authorization"] = "Bearer #{token}" if auth
      if multipart
        boundary = "----onboarding#{SecureRandom.hex(8)}"
        req["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
        req.body = multipart.map do |name, value|
          if value.is_a?(File)
            "--#{boundary}\r\nContent-Disposition: form-data; name=\"#{name}\"; filename=\"#{File.basename(value.path)}\"\r\n" \
              "Content-Type: #{MIME.fetch(File.extname(value.path).downcase, 'application/octet-stream')}\r\n\r\n#{value.read}\r\n"
          else
            "--#{boundary}\r\nContent-Disposition: form-data; name=\"#{name}\"\r\n\r\n#{value}\r\n"
          end
        end.join + "--#{boundary}--\r\n"
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

    # Polls a block until it returns the same truthy value twice in a row (a background job has settled)
    def wait_until_stable(every: 10, tries: 60)
      previous = nil
      tries.times do
        current = yield
        return current if current && current == previous

        previous = current
        sleep every
      end
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
    status, body = api.call("patch", "/entities/#{api.entity_id}.json", guard: false,
                                                                        body: { entity: { entity_setting_attributes: { sandbox: true, sandbox_emails: api.ops_email } } })
    puts "HTTP #{status} #{body.is_a?(Hash) ? body.slice('id', 'name') : body}"
  when "upload"
    type, file, step = ARGV[1], ARGV[2], ARGV[3]
    # Must-have gate by import type (Investor/CapitalCommitment → commitments, calls/remittances/payments → drawdowns, …);
    # an explicit step wins where one type serves two steps (portfolio companies are an Investor import → portfolio)
    (step ||= Onboarding::Gate::IMPORT_STEP[type]) && Onboarding::Gate.check!(api.workspace, step.to_sym)
    # Manual review gate (hard rule 10): ops approved this exact file (review.rb), or review is waived for the client
    Onboarding::Review.check!(api.workspace, file)
    status, body = api.call("post", "/import_uploads.json", multipart: {
      "import_upload[name]" => "#{type} #{File.basename(file)}", "import_upload[owner_type]" => "Entity",
      "import_upload[owner_id]" => api.entity_id, "import_upload[entity_id]" => api.entity_id,
      "import_upload[import_type]" => type, "import_upload[import_file]" => File.open(file, "rb")
    })
    abort "upload refused: HTTP #{status} #{body}" unless status == 201
    id = body["id"]
    puts "upload #{id} created; waiting for ImportUploadJob…"
    # Verification from the API only: outcome, counts and the first failed rows ("Completed" alone is not success)
    # Backoff: 5 s, 10 s, 20 s, then every 30 s (a 15-minute import was ~174 polls at a flat 5 s, now ~35); 20 min in all
    waited = 0
    (0..).each do |i|
      break if waited >= 1200

      pause = [5 * (2**i), 30].min
      sleep pause
      waited += pause
      _, up = api.call("get", "/import_uploads/#{id}.json")
      next if up["status"].to_s.empty? || up["outcome"] == "running"

      puts "upload #{id}: outcome=#{up['outcome'].inspect} status=#{up['status'].to_s[0, 160].inspect} " \
           "total=#{up['total_rows_count'].inspect} processed=#{up['processed_row_count'].inspect} failed=#{up['failed_row_count'].inspect}"
      puts "  custom fields created: #{up['custom_fields_created']}" if up["custom_fields_created"].to_s != ""
      Array(up["row_errors"]).first(10).each { |e| puts "  row #{e['row']}: #{e['message'].to_s[0, 200]}" }
      exit
    end
    puts "upload #{id}: still running after 20 min — paused"
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

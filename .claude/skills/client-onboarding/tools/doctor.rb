# Setup check — run it first on a new machine (Windows, Linux, macOS) and at the start of every onboarding. READ-ONLY:
# no writes, to disk outside the workspace's out/ probe or to the app. One ✔ / ⚠ / ✖ line per check, each ✖ with its fix.
#   ① Ruby version, platform and UTF-8 default encoding    ② the gems the tools load (roo, caxlsx)
#   ③ the workspace: onboarding.yml keys, state/token, source/ files, out/ writable
#   ④ the token: accepted by the app (GET /users/tokens/info) and who it belongs to
#   ⑤ the entity: readable, sandbox state, whether it already holds funds (⚠ only: ops may load into a used entity)
# Exits non-zero when any ✖.
#
# Usage: ruby doctor.rb [--workspace DIR]
require "yaml"
require "date"
require "fileutils"
require "openssl" # named in the network rescue below — load it so that clause cannot itself raise NameError

$stdout.sync = true
i = ARGV.index("--workspace")
WS = File.expand_path(i ? ARGV.slice!(i, 2).last : ENV.fetch("ONBOARDING_WORKSPACE", Dir.pwd))
failed = false
ok = ->(msg) { puts "✔ #{msg}" }
warn_ = ->(msg) { puts "⚠ #{msg}" }
bad = lambda do |msg, fix|
  failed = true
  puts "✖ #{msg}\n    fix: #{fix}"
end

# ① Ruby: 3.1+ (endless methods, Hash shorthand); UTF-8 so the ✔ / ₹ / client names read and print correctly
ver_ok = Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.1")
utf8 = Encoding.default_external == Encoding::UTF_8
if ver_ok && utf8
  ok.("Ruby #{RUBY_VERSION} (#{RUBY_PLATFORM}) at #{RbConfig.ruby}, UTF-8")
else
  bad.("Ruby #{RUBY_VERSION}, default encoding #{Encoding.default_external}",
       ver_ok ? "set RUBYOPT=-Eutf-8 (Windows: setx RUBYOPT -Eutf-8, then open a new terminal)" : "install Ruby 3.3 (Windows: rubyinstaller.org, Ruby+Devkit x64)")
end

# Display: emoji + progress bars, or plain symbols — and why, so ops knows how to get the full display
require_relative "ui"
if (reason = Onboarding::UI.plain_reason)
  warn_.("display: plain symbols (#{reason})#{' — open the workspace in Windows Terminal for emoji and live progress bars' if Gem.win_platform?}")
else
  ok.("display: #{Onboarding::UI.icon(:ok)} emoji#{Onboarding::UI.color? ? ', colours' : ''} and live progress bars#{' (in a terminal)' unless Onboarding::UI.tty?}")
end

# Sound: which player the step chimes use (none is fine — a terminal bell, or silence)
if ENV["ONBOARDING_SOUND"] == "0"
  ok.("sound: off (ONBOARDING_SOUND=0)")
elsif (player = Onboarding::UI.sound_player)
  ok.("sound: 🔔 #{player} — a chime when a step is done, a doorbell when it needs you, a low alert when it fails")
else
  warn_.("sound: no player found (pw-play / paplay / aplay, afplay, or PowerShell) — steps will only ring the terminal bell")
end

# ② Gems: the only two outside the standard library
missing = %w[roo caxlsx].reject do |g|
  require g
  true
rescue LoadError
  false
end
if missing.empty?
  ok.("gems: roo #{Gem.loaded_specs['roo']&.version}, caxlsx #{Gem.loaded_specs['caxlsx']&.version}")
else
  bad.("gems missing: #{missing.join(', ')}", "gem install #{missing.join(' ')}")
end

# ③ Workspace files
cfg_path = File.join(WS, "onboarding.yml")
cfg = File.exist?(cfg_path) ? (YAML.safe_load_file(cfg_path, permitted_classes: [Date]) || {}) : nil
token_path = File.join(WS, "state", "token")
if cfg.nil?
  bad.("no onboarding.yml in #{WS}", "create it with base_url, entity_id, ops_email, client (see tools/README.md › Client workspace)")
elsif (keys = %w[base_url entity_id ops_email client].reject { cfg[_1].to_s.strip != "" }).any?
  bad.("onboarding.yml lacks #{keys.join(', ')}", "add them to #{cfg_path}")
else
  ok.("workspace #{WS}: onboarding.yml (#{cfg['base_url']}, entity #{cfg['entity_id']}, #{cfg['client']})")
end
if File.exist?(token_path) && File.read(token_path).strip != ""
  ok.("state/token present")
else
  bad.("no state/token", "paste the ops user's API token (CapHive › Profile › API tokens) into #{token_path}")
end
sources = Dir[File.join(WS, "source", "*.{xlsx,xls,csv}")]
sources.any? ? ok.("source/: #{sources.size} client file(s)") : warn_.("source/ has no client files yet — copy them in before step 3")
begin
  probe = File.join(WS, "out", ".doctor_probe")
  FileUtils.mkdir_p(File.dirname(probe))
  File.write(probe, "ok")
  File.delete(probe)
  ok.("out/ writable")
rescue SystemCallError => e
  bad.("out/ not writable (#{e.class})", "check the folder's permissions or move the workspace under your user folder")
end

# ④ + ⑤ The app: only when the workspace and token are there (the API client aborts without them)
if cfg && File.exist?(token_path) && !failed
  require_relative "api"
  api = Onboarding::Api.new(WS)
  begin
    status, me = api.call("get", "/users/tokens/info")
    if status == 200 && me.is_a?(Hash)
      ok.("token accepted: user #{me['id']} #{me['email']} (GET /users/tokens/info)")
      warn_.("token user #{me['email']} ≠ ops_email #{cfg['ops_email']} in onboarding.yml") if me["email"] != cfg["ops_email"]
    else
      bad.("token not accepted (HTTP #{status})", "create a new API token in CapHive › Profile › API tokens and paste it into state/token")
    end
    status, ent = api.call("get", "/entities/#{api.entity_id}.json")
    if status == 200 && ent.is_a?(Hash)
      sandbox = ent.dig("entity_setting", "sandbox") == true
      funds = api.list("/funds.json").select { _1["entity_id"] == api.entity_id }
      ok.("entity #{ent['id']} \"#{ent['name']}\" readable · sandbox #{sandbox ? 'ON' : 'off'} · #{funds.size} fund(s)")
      warn_.("sandbox is off — step 2 turns it on before any other write") unless sandbox
      warn_.("entity already holds #{funds.map { _1['name'] }.join(', ')} — load here only on ops' explicit word (hard rule 3)") if funds.any?
    else
      bad.("entity #{api.entity_id} not readable (HTTP #{status})", "check entity_id in onboarding.yml and that the token's user belongs to that entity")
    end
  rescue SocketError, SystemCallError, OpenSSL::SSL::SSLError, Net::OpenTimeout, Net::ReadTimeout => e
    bad.("cannot reach #{cfg['base_url']} (#{e.class}: #{e.message[0, 80]})", "check base_url, the network/VPN, and that the site opens in a browser")
  end
end

puts(failed ? "✖ fix the lines above, then run doctor.rb again" : "✔ ready — next: ruby onboard.rb --workspace #{WS} status")
exit(failed ? 1 : 0)

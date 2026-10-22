# frozen_string_literal: true

# Support Console local mode (openspec/changes/archive/2026-10-22-support-console/design.md#local-development):
# the whole loop on a laptop — Rails, the relay on 127.0.0.1:4900 (SUPPORT_CONSOLE_LOCAL=1), your
# own `claude` login, a code archive under tmp/support_console/ and a SELECT-only support_ro on
# the local MySQL. Nothing here touches staging or production.
#
#   bundle exec rake support_console:local_setup            # dev DB on 3306
#   DB_PORT=33066 bundle exec rake support_console:local_setup   # the prod copy (mysql-restored)
#   npm --prefix support_console/machine ci && npm --prefix support_console/machine run dev
#   bundle exec rake support_console:local_check
namespace :support_console do
  desc "Support Console local mode: SELECT-only support_ro, machine.env, code archive of HEAD"
  task local_setup: :environment do
    abort "local_setup is for development only" unless Rails.env.development?

    db = ActiveRecord::Base.configurations.configs_for(env_name: "development", name: "primary").configuration_hash
    host = db[:host].presence || "127.0.0.1"
    port = Integer(ENV.fetch("DB_PORT", db[:port] || 3306))
    database = db[:database]
    FileUtils.mkdir_p(support_console_local_dir.join("clients"))

    # 1. The read-only account. '%' because a dockerised MySQL sees the laptop as a bridge address.
    password = SecureRandom.alphanumeric(32)
    admin = Mysql2::Client.new(host: host, port: port, username: ENV.fetch("DB_ADMIN_USER", db[:username]),
                               password: ENV.fetch("DB_ADMIN_PASS", db[:password]))
    admin.query("CREATE USER IF NOT EXISTS 'support_ro'@'%' IDENTIFIED BY '#{password}'")
    admin.query("ALTER USER 'support_ro'@'%' IDENTIFIED BY '#{password}' WITH MAX_USER_CONNECTIONS 4")
    admin.query("REVOKE ALL PRIVILEGES, GRANT OPTION FROM 'support_ro'@'%'")
    admin.query("GRANT SELECT, SHOW VIEW ON `#{admin.escape(database)}`.* TO 'support_ro'@'%'")
    admin.close
    password_file = support_console_local_dir.join("db_password")
    File.write(password_file, password)
    File.chmod(0o600, password_file)
    puts "support_ro: SELECT, SHOW VIEW on #{database} at #{host}:#{port}"

    # 2. The code the machine reads: an archive of HEAD (uncommitted changes are not included).
    sha = SupportConsoleCodeArchive.git("rev-parse", "HEAD").strip
    code_dir = support_console_local_dir.join("code", sha)
    if code_dir.exist?
      puts "code archive: #{sha.first(12)} already extracted"
    else
      SupportConsoleCodeArchive.extract(sha, code_dir)
      puts "code archive: #{sha.first(12)} -> #{code_dir}"
    end
    current = support_console_local_dir.join("code/current")
    FileUtils.rm_f(current)
    File.symlink(code_dir, current)

    # 3. machine.env — read by `npm run dev` (the relay) and, in development, by Rails.
    secret = support_console_machine_env["SUPPORT_CONSOLE_RELAY_SECRET"].presence || SecureRandom.hex(32)
    File.write(support_console_local_dir.join("machine.env"), <<~ENV)
      # Written by rake support_console:local_setup — local mode only.
      SUPPORT_CONSOLE_LOCAL=1
      SUPPORT_CONSOLE_RELAY_URL=http://127.0.0.1:4900
      SUPPORT_CONSOLE_RELAY_SECRET=#{secret}
      RELAY_HOST=127.0.0.1
      RELAY_PORT=4900
      SUPPORT_CONSOLE_CODE_DIR=#{current}
      SUPPORT_CONSOLE_CLIENTS_DIR=#{support_console_local_dir.join('clients')}
      SUPPORT_DB_HOST=#{host}
      SUPPORT_DB_PORT=#{port}
      SUPPORT_DB_NAME=#{database}
      SUPPORT_DB_USER=support_ro
      SUPPORT_DB_PASSWORD_FILE=#{password_file}
    ENV
    File.chmod(0o600, support_console_local_dir.join("machine.env"))
    puts "machine.env: #{support_console_local_dir.join('machine.env')}"
    puts "next: npm --prefix support_console/machine ci && npm --prefix support_console/machine run dev"
  end

  desc "Support Console local mode: check the relay, the code archive and the read-only database"
  task local_check: :environment do
    env = support_console_machine_env
    abort "run rake support_console:local_setup first" if env.empty?

    # The machine-side checks, with the same environment the relay uses.
    ok = system(env, "node", Rails.root.join("support_console/machine/scripts/check.js").to_s)

    # The relay answers, and Rails can see its URL and secret.
    begin
      health = JSON.parse(Net::HTTP.get(URI("#{env['SUPPORT_CONSOLE_RELAY_URL']}/health")))
      puts "✓ Relay: up at #{env['SUPPORT_CONSOLE_RELAY_URL']}#{' (local mode)' if health['local']}, code #{health['code_rev'].to_s.first(12)}"
    rescue StandardError => e
      ok = false
      puts "✗ Relay: #{e.class}: #{e.message} — start it with npm --prefix support_console/machine run dev"
    end
    puts SupportConsoleRelayClient.configured? ? "✓ Rails: relay configured" : "✗ Rails: relay not configured"
    abort "local check failed" unless ok && SupportConsoleRelayClient.configured?
  end

  # @return [Pathname] where local mode keeps its files
  def support_console_local_dir
    Rails.root.join("tmp/support_console")
  end

  # @return [Hash{String => String}] tmp/support_console/machine.env, if written
  def support_console_machine_env
    path = support_console_local_dir.join("machine.env")
    return {} unless path.exist?

    path.readlines(chomp: true).reject { |l| l.blank? || l.start_with?("#") }.to_h { |l| l.split("=", 2) }
  end
end

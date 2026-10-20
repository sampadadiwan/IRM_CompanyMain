# lib/tasks/support_console/db_access.rake
#
# Provision the Support Console's access to an environment's replica
# (openspec/changes/support-console/design.md (card ⑦)): a SELECT-only database account, an SSM parameter
# holding its details, the IAM permission to read that parameter, and the one
# security-group rule from the support machine to the replica.
#
#   bundle exec rake "support_console:provision_db_access[staging.in]"              # DRY RUN (default)
#   EXECUTE=1 bundle exec rake "support_console:provision_db_access[staging.in]"    # apply
#   EXECUTE=1 bundle exec rake "support_console:provision_db_access[production.in]"
#
#   The AWS keys, the endpoints and the admin account all come from that
#   environment's credentials, so there is nothing to export first.
#
#   The security-group rule from the support machine to the replica is found, not typed: the support machine's
#   group by the name support_console:machine gives it, the replica's from the network interface holding its
#   address. SUPPORT_CONSOLE_SG / DB_SG override either; SUPPORT_CONSOLE_ROLE is only for a machine made some other
#   way (support_console:machine's own policy already reads the parameter).
#
#   DB_USER_RO=support_ro_<name> EXECUTE=1 rake "support_console:provision_db_access[production.in]"
#     one account per person, so the database attributes queries to a person
#
#   SKIP_ACCOUNT=1 EXECUTE=1 bundle exec rake "support_console:provision_db_access[staging.in]"
#     the account already exists (a DBA applied the SQL this task printed): does everything
#     else, reading the stored password instead of rotating it
#
#   bundle exec rake "support_console:db_access_check[staging.in]"    # verify only, changes nothing
#
# WHY THIS EXISTS
#   The Support Console's data tool reads the replica through a SELECT-only account
#   (it never runs the app's code). These four pieces are what the machine needs from the
#   environment, and they are easy to get subtly wrong: the
#   account has to be created on the WRITER (accounts and grants replicate from
#   there; a replica refuses to create them), while the MACHINE must be pointed at
#   the REPLICA, and the account must hold nothing beyond SELECT.
#
#   The endpoints and the admin account come from that environment's credentials —
#   config/credentials/<env>.yml.enc — so nothing is typed in and nothing can drift
#   from what the app itself uses.
#
# SAFETY
#   - DRY RUN by default; every mutating call goes through .act, so without
#     EXECUTE=1 nothing is created or changed.
#   - The STS account id must match the env's account, because staging
#     (174852986003) and production (825199636520) are separate AWS accounts and
#     exporting the wrong keys is an easy mistake.
#   - The generated password is never printed and never passed on a command line;
#     it goes into the SSM parameter (SecureString) and nowhere else.
#   - Re-running rotates the password and stores the new one in the same pass, so
#     the account and the parameter cannot drift apart. SKIP_ACCOUNT=1 does neither,
#     for the same reason: it is for the case where we cannot alter the account.
#   - The verification step attempts a CREATE TABLE as the new account and only
#     passes when the server refuses it.
#
# WHERE TO RUN IT
#   Anywhere with the environment's credentials and a route to its database — an
#   app host is the usual answer (`cap <stage> rake:invoke` or over SSM). From a
#   laptop the AWS calls work but the database steps cannot reach the host, and
#   the task says so rather than half-finishing.
require "resolv"
require "securerandom"
require "json"
require "aws-sdk-core" # STS
require "aws-sdk-ssm"
require "aws-sdk-iam"
require "aws-sdk-ec2"

module SupportConsoleDbAccess
  module_function

  # env_name => the AWS account it lives in, its default region, and its database.
  # Same account ids as aws_ebs.rake / aws_tls_policy.rake.
  ENVIRONMENTS = {
    "staging.in" => { account: "174852986003", region: "ap-south-1", database: "IRM_staging" },
    "production.in" => { account: "825199636520", region: "ap-south-1", database: "IRM_production" },
    "production.us" => { account: "825199636520", region: "us-east-1", database: "IRM_production" }
  }.freeze

  # SELECT and SHOW VIEW only. The ceilings are enforced by the database, so no
  # session opened with this account can monopolise the replica the app is using.
  MAX_USER_CONNECTIONS = 4
  MAX_QUERIES_PER_HOUR = 20_000
  STATEMENT_TIMEOUT_MS = 30_000

  def execute? = ENV["EXECUTE"].present?

  # The one step this task cannot always do itself: creating the account needs CREATE USER and GRANT
  # OPTION, and on staging the app's own database user holds neither. When a DBA applies the printed
  # SQL by hand, SKIP_ACCOUNT=1 finishes the rest — it does not generate a password, does not write
  # the parameter and does not touch the database as an admin, so the account and the stored password
  # cannot drift apart.
  def skip_account? = ENV["SKIP_ACCOUNT"].present?

  # Symbols chosen to satisfy MySQL's validate_password plugin (its MEDIUM policy wants lower, upper,
  # digit and special) while staying safe inside an `IDENTIFIED BY '...'` literal: no quote, no
  # backslash, no backtick. Staging refused a purely alphanumeric password, which is what this fixes.
  PASSWORD_SYMBOLS = "!@#%^*_-+=:.?".freeze

  def generate_password
    alphabet = [*"a".."z", *"A".."Z", *"0".."9", *PASSWORD_SYMBOLS.chars]
    loop do
      password = Array.new(32) { alphabet.sample(random: SecureRandom) }.join
      next unless password.match?(/[a-z]/) && password.match?(/[A-Z]/) && password.match?(/[0-9]/)
      next unless PASSWORD_SYMBOLS.chars.any? { |c| password.include?(c) }

      return password
    end
  end

  # The host part of the account: the support machine's own private address, so only that box can
  # log in with the password — not any 10.x host, the writer included (the account replicates there).
  # DB_ACCOUNT_HOST overrides it, e.g. for a machine made some other way. Set by the task from the
  # running machine (machine_account_host!); a recreated machine has a new address, so re-run then.
  def account_host
    ENV["DB_ACCOUNT_HOST"].presence || @machine_ip ||
      abort("❌ no support machine found — run support_console:machine first (it waits for the parameter " \
            "this task writes), or set DB_ACCOUNT_HOST to the machine's private address")
  end

  # @return [String, nil] the machine's private address, remembered for account_host
  def machine_account_host!(env_name, config)
    @machine_ip = SupportConsoleMachine.find_instance(env_name, config)&.private_ip_address
  end

  # The account an earlier run created for every 10.x host. Dropped once the per-machine account exists,
  # or it would keep its password and its SELECT.
  LEGACY_ACCOUNT_HOST = "10.%".freeze

  # Set just before the access-denied hand-off: the DBA then applies the SQL with the password already
  # stored, so that parameter must be kept.
  def handed_to_dba? = @handed_to_dba == true

  def ro_user = ENV.fetch("DB_USER_RO", "support_ro")

  def parameter_name(env_name) = ENV.fetch("SUPPORT_CONSOLE_DB_PARAM", "/irm/support-console/#{env_name}/replica")

  # Every mutating call funnels through here so DRY RUN cannot mutate.
  def act(description)
    if execute?
      puts "  → #{description}"
      yield
    else
      puts "  · would #{description}"
      nil
    end
  end

  def env!(env_name)
    config = ENVIRONMENTS[env_name]
    abort "❌ unknown env '#{env_name}' — expected one of #{ENVIRONMENTS.keys.join(', ')}" if config.nil?

    config
  end

  # X32 — production.in and production.us share one AWS account, so assert_account! cannot tell them
  # apart: only the region does. A REGION override on production would quietly write one region's
  # parameters (an IN database password, the Claude token) into the other, so it is refused unless it
  # names the environment's own region. Staging keeps the override for experiments.
  def region(config)
    override = ENV["REGION"].presence
    return config[:region] if override.nil? || override == config[:region]

    env_name = ENVIRONMENTS.key(config)
    if env_name.to_s.start_with?("production")
      abort "❌ REGION=#{override} on #{env_name}, whose region is #{config[:region]} — production.in and production.us " \
            "share an AWS account, so the region is all that keeps them apart. Unset REGION."
    end
    override
  end

  # That environment's credentials, not this process's: the task is usually run
  # with RAILS_ENV=development from a checkout.
  def credentials(env_name)
    @credentials ||= {}
    @credentials[env_name] ||= begin
      key_path = Rails.root.join("config/credentials/#{env_name}.key")
      config_path = Rails.root.join("config/credentials/#{env_name}.yml.enc")
      abort "❌ #{config_path} is missing — this needs that environment's credentials" unless config_path.exist?
      abort "❌ #{key_path} is missing — this needs that environment's key" unless key_path.exist? || ENV["RAILS_MASTER_KEY"]

      ActiveSupport::EncryptedConfiguration.new(
        config_path: config_path, key_path: key_path,
        env_key: "RAILS_MASTER_KEY", raise_if_missing_key: true
      ).config
    end
  end

  def credential!(env_name, key)
    value = credentials(env_name)[key].to_s
    abort "❌ #{key} is not in config/credentials/#{env_name}.yml.enc" if value.empty?

    value
  end

  def assert_account!(env_name, config)
    account = begin
      sts(env_name, config).get_caller_identity.account
    rescue Aws::Errors::ServiceError, Aws::Errors::MissingCredentialsError, Seahorse::Client::NetworkingError => e
      abort "❌ could not call STS with #{env_name}'s credentials: #{e.message}\n   " \
            "Expected AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY in " \
            "config/credentials/#{env_name}.yml.enc, or exported in the shell."
    end
    if account == config[:account]
      # Same account for both production regions: say which region this run acts in, every time.
      puts "AWS account #{account} · region #{region(config)}"
      return
    end

    abort "❌ #{env_name} lives in account #{config[:account]} but these credentials are account " \
          "#{account} — export the right env's AWS keys before re-running"
  end

  # SDK clients, not the `aws` CLI: the app servers where this runs (they are the hosts with a route
  # to the database) have no CLI installed, and aws_utils.rb and the other infrastructure tasks use
  # the SDK too.
  #
  # The keys come from the environment's own credentials — AWS_ACCESS_KEY_ID and
  # AWS_SECRET_ACCESS_KEY, the same pair backup_db_xtra.rake reads — so there is nothing to export.
  # Already-exported keys win, for anyone using a role or SSO.
  def aws_options(env_name, config)
    options = { region: region(config) }
    if ENV["AWS_ACCESS_KEY_ID"].present? && ENV["AWS_SECRET_ACCESS_KEY"].present?
      # Exported keys from a role or SSO are temporary, and are useless without their session token.
      options[:credentials] = Aws::Credentials.new(ENV.fetch("AWS_ACCESS_KEY_ID", nil), ENV.fetch("AWS_SECRET_ACCESS_KEY", nil),
                                                   ENV["AWS_SESSION_TOKEN"].presence)
      return options
    end

    creds = credentials(env_name)
    key = creds[:AWS_ACCESS_KEY_ID].presence
    secret = creds[:AWS_SECRET_ACCESS_KEY].presence
    options[:credentials] = Aws::Credentials.new(key, secret) if key && secret
    options
  end

  def sts(env_name, config) = @sts ||= Aws::STS::Client.new(**aws_options(env_name, config))
  def ssm(env_name, config) = @ssm ||= Aws::SSM::Client.new(**aws_options(env_name, config))
  def iam(env_name, config) = @iam ||= Aws::IAM::Client.new(**aws_options(env_name, config))
  def ec2(env_name, config) = @ec2 ||= Aws::EC2::Client.new(**aws_options(env_name, config))

  # --- database ----------------------------------------------------------------------------------

  def db_port = Integer(ENV.fetch("DB_PORT", 3306))

  def mysql_client(host:, username:, password:, database: nil)
    require "mysql2"
    Mysql2::Client.new(host: host, port: db_port, username: username, password: password,
                       database: database, connect_timeout: 8, read_timeout: 30)
  end

  def reachable?(host, username, password)
    mysql_client(host: host, username: username, password: password).close
    true
  rescue StandardError
    false
  end

  def create_account!(env_name, writer, admin_user, admin_pass, database, password)
    statements = [
      "CREATE USER IF NOT EXISTS '#{ro_user}'@'#{account_host}' IDENTIFIED BY '#{password}'",
      "ALTER USER '#{ro_user}'@'#{account_host}' IDENTIFIED BY '#{password}'",
      # Revoke before granting: an account that already exists — hand-made, or from a run against a
      # different database — keeps whatever it held otherwise, and on a real replica the write probe
      # cannot reveal it, because read_only refuses the statement whatever the grants say.
      #
      # This form takes no ON clause — `REVOKE ALL PRIVILEGES, GRANT OPTION ON *.*` is a syntax error,
      # and the clauseless form is the one that clears database and table grants as well as global
      # ones. It succeeds on an account holding only USAGE, so a fresh account is fine.
      "REVOKE ALL PRIVILEGES, GRANT OPTION FROM '#{ro_user}'@'#{account_host}'",
      "GRANT SELECT, SHOW VIEW ON `#{database}`.* TO '#{ro_user}'@'#{account_host}'",
      # Replica status only (SHOW REPLICA STATUS), so the console can show how fresh the data is.
      "GRANT REPLICATION CLIENT ON *.* TO '#{ro_user}'@'#{account_host}'",
      "ALTER USER '#{ro_user}'@'#{account_host}' WITH " \
      "MAX_USER_CONNECTIONS #{MAX_USER_CONNECTIONS} MAX_QUERIES_PER_HOUR #{MAX_QUERIES_PER_HOUR}",
      # The older any-10.x account (earlier runs) goes once this machine has its own.
      ("DROP USER IF EXISTS '#{ro_user}'@'#{LEGACY_ACCOUNT_HOST}'" unless account_host == LEGACY_ACCOUNT_HOST),
      "FLUSH PRIVILEGES"
    ].compact
    act("create or update '#{ro_user}'@'#{account_host}' on #{writer} with SELECT, SHOW VIEW on #{database}") do
      current = "the connection"
      begin
        # The connect is inside the rescue too: "access denied" can come from either the connection or
        # the first statement, depending on how the account is restricted.
        client = mysql_client(host: writer, username: admin_user, password: admin_pass)
        statements.each do |sql|
          current = sql
          client.query(sql)
        end
      rescue Mysql2::Error => e
        if e.message.match?(/password.*polic/i)
          abort "❌ #{writer} refused the generated password: #{e.message}\n   " \
                "It is 32 characters with upper, lower, digits and symbols, so this server's policy " \
                "is stricter than validate_password MEDIUM. Check: SHOW VARIABLES LIKE 'validate_password%'"
        end
        raise unless e.message.match?(/Access denied|command denied/i)

        @handed_to_dba = true
        abort <<~MESSAGE
          ❌ #{admin_user} cannot create or grant on #{database}: #{e.message}

             It failed on: #{current.sub(/IDENTIFIED BY '[^']*'/, "IDENTIFIED BY '<the password>'")}

             Creating the account needs CREATE USER; granting needs the privilege **with GRANT OPTION**,
             which the app's own database user does not always hold. On staging it holds CREATE USER but
             not GRANT OPTION, so the account gets created and the GRANT is what fails. To see who can:

               SELECT CURRENT_USER(); SHOW GRANTS FOR CURRENT_USER();
               SELECT user, host FROM mysql.user WHERE Grant_priv = 'Y';

             Those accounts are usually @localhost, which means the statements have to be run **on the
             database host itself**, not from an app server. Either re-run here with an account that can:

               DB_ADMIN_USER=<dba> DB_ADMIN_PASS=<password> EXECUTE=1 \\
                 bundle exec rake "support_console:provision_db_access[#{env_name}]"

             or run these on #{writer} as one of those accounts, with the password already waiting in
             #{parameter_name(env_name)}
             (aws ssm get-parameter --name #{parameter_name(env_name)} --with-decryption \\
                --query Parameter.Value --output text):

          #{statements.map { |sql| "     #{sql.sub(/IDENTIFIED BY '[^']*'/, "IDENTIFIED BY '<that password>'")};" }.join("\n")}

             If the account already exists — this run reached the GRANT, so it does — only the last
             four are left (the two GRANTs, the limits, FLUSH), and none of them contains a password.

             Then finish the remaining steps — they need no database privileges, and this leaves the
             stored password exactly as it is:

               SKIP_ACCOUNT=1 EXECUTE=1 bundle exec rake "support_console:provision_db_access[#{env_name}]"
        MESSAGE
      end
      grants = client.query("SHOW GRANTS FOR '#{ro_user}'@'#{account_host}'").to_a.map(&:values).flatten
      client.close
      grants.each { |g| puts "      #{g}" }
      extra = grants.grep(/\b(ALL PRIVILEGES|INSERT|UPDATE|DELETE|CREATE|DROP|ALTER|GRANT OPTION)\b/i)
      abort "❌ #{ro_user} still holds more than SELECT after the grant: #{extra.join('; ')}" if extra.any?
    end
  end

  # --- the parameter -----------------------------------------------------------------------------

  # A SecureString in Parameter Store, in the same /irm namespace as the Pulumi
  # passphrase. The value is the JSON the support machine merges into its own credentials.
  def store_parameter!(env_name, config, replica, database, password)
    name = parameter_name(env_name)
    # The keys are the machine's own environment names (support_console/machine/lib/db.js).
    payload = JSON.generate({ "SUPPORT_DB_HOST" => replica, "SUPPORT_DB_NAME" => database,
                              "SUPPORT_DB_USER" => ro_user, "SUPPORT_DB_PASSWORD" => password,
                              "SUPPORT_DB_PORT" => db_port.to_s })
    act("store #{name} (SecureString) with the replica endpoint, database and account") do
      ssm(env_name, config).put_parameter(
        name: name, value: payload, type: "SecureString", overwrite: true,
        description: "Support Console read-only access to the #{env_name} replica " \
                     "(openspec/changes/support-console/design.md (card ⑦))"
      )
    rescue Aws::SSM::Errors::ServiceError => e
      abort "❌ could not write #{name}: #{e.message}"
    end
    name
  end

  # @return [String, nil] the parameter's current raw value, to put back if the new password is never applied
  def previous_parameter_value(env_name, config)
    return nil unless execute?

    ssm(env_name, config).get_parameter(name: parameter_name(env_name), with_decryption: true).parameter.value
  rescue Aws::SSM::Errors::ParameterNotFound
    nil
  end

  # Puts the parameter back as it was (or removes it, if this run created it), so the running machine
  # keeps a password its account actually has.
  def restore_parameter!(env_name, config, previous)
    name = parameter_name(env_name)
    act(previous ? "put #{name} back to its previous value" : "remove #{name}, which this run created") do
      if previous
        ssm(env_name, config).put_parameter(name: name, value: previous, type: "SecureString", overwrite: true)
      else
        ssm(env_name, config).delete_parameter(name: name)
      end
    rescue Aws::SSM::Errors::ServiceError => e
      warn "❌ could not restore #{name}: #{e.message} — the machine's lookups will fail until it is fixed"
    end
  end

  # The parameter as the support machine itself will read it. Both SKIP_ACCOUNT and support_console:db_access_check
  # need the stored password without rotating it.
  def read_parameter!(env_name, config)
    name = parameter_name(env_name)
    JSON.parse(ssm(env_name, config).get_parameter(name: name, with_decryption: true).parameter.value)
  rescue Aws::SSM::Errors::ParameterNotFound
    abort "❌ #{name} does not exist — run support_console:provision_db_access[#{env_name}] without " \
          "SKIP_ACCOUNT first, which creates it"
  rescue JSON::ParserError
    abort "❌ #{name} does not hold the JSON this task writes — re-run without SKIP_ACCOUNT to rewrite it"
  rescue Aws::SSM::Errors::ServiceError => e
    abort "❌ could not read #{name}: #{e.message}"
  end

  def parameter_arn(env_name, config)
    name = parameter_name(env_name)
    "arn:aws:ssm:#{region(config)}:#{config[:account]}:parameter#{name}"
  end

  # --- IAM and the network -----------------------------------------------------------------------

  def grant_parameter_access!(env_name, config)
    role = ENV["SUPPORT_CONSOLE_ROLE"].to_s
    if role.empty?
      # support_console:machine's own instance policy already grants this read, so a machine made by that task
      # needs nothing here. SUPPORT_CONSOLE_ROLE is for a machine made some other way.
      puts "  · SUPPORT_CONSOLE_ROLE not set — skipping; a machine from support_console:machine already has " \
           "ssm:GetParameter on #{parameter_name(env_name)}"
      return
    end

    policy = JSON.generate(
      Version: "2012-10-17",
      Statement: [
        { Effect: "Allow", Action: %w[ssm:GetParameter], Resource: parameter_arn(env_name, config) },
        # Only this parameter decrypts, whatever else the role can GetParameter.
        { Effect: "Allow", Action: %w[kms:Decrypt], Resource: "*",
          Condition: { StringEquals: { "kms:ViaService" => "ssm.#{region(config)}.amazonaws.com",
                                       "kms:EncryptionContext:PARAMETER_ARN" => parameter_arn(env_name, config) } } }
      ]
    )
    act("attach ssm:GetParameter on #{parameter_name(env_name)} to #{role}") do
      iam(env_name, config).put_role_policy(role_name: role, policy_name: "support-console-read-replica-parameter",
                                            policy_document: policy)
    rescue Aws::IAM::Errors::ServiceError => e
      abort "❌ could not attach the policy to #{role}: #{e.message}"
    end
  end

  # The machine's group, by the name support_console:machine gives it (lib/tasks/support_console/machine.rake).
  def machine_security_group(env_name, config)
    return ENV["SUPPORT_CONSOLE_SG"] if ENV["SUPPORT_CONSOLE_SG"].present?

    ec2(env_name, config).describe_security_groups(
      filters: [{ name: "group-name", values: [SupportConsoleMachine.machine_name(env_name)] }]
    ).security_groups.first&.group_id
  end

  # The replica's group: the groups on the network interface that holds its address. An RDS endpoint is
  # a name and resolves to one; an EC2 host is already an address. Rules are a union across a
  # interface's groups, so authorising on the first is enough — and it is printed, not assumed.
  def replica_security_group(env_name, config, replica)
    return ENV["DB_SG"] if ENV["DB_SG"].present?

    groups = interface_groups(env_name, config, replica)
    puts "  · the replica (#{replica}) has #{groups.join(', ')}; using the first" if groups.size > 1
    groups.first
  end

  # @return [Array<String>] the security groups on the network interface holding the host's address
  def interface_groups(env_name, config, host)
    address = Resolv.getaddress(host)
    interface = ec2(env_name, config).describe_network_interfaces(
      filters: [{ name: "addresses.private-ip-address", values: [address] }]
    ).network_interfaces.first
    interface&.groups.to_a.map(&:group_id)
  rescue Resolv::ResolvError
    []
  end

  def open_replica_port!(env_name, config, replica, writer)
    machine_sg = machine_security_group(env_name, config)
    db_sg = replica_security_group(env_name, config, replica)
    if machine_sg.blank? || db_sg.blank?
      puts "  · #{machine_sg.blank? ? 'no support machine yet (run support_console:machine first)' : "cannot find #{replica}'s security group"} " \
           "— skipping the security-group rule; set SUPPORT_CONSOLE_SG / DB_SG to name them"
      return
    end

    # The rule opens the whole group. If the writer is in it too, the machine could reach the writer,
    # which production must never allow — refuse rather than change the database servers' groups here.
    # (Staging has no replica: writer and replica are one server, E24.)
    if writer != replica && interface_groups(env_name, config, writer).include?(db_sg)
      message = "#{db_sg} is on the writer (#{writer}) as well as the replica, so this rule would let the support " \
                "machine reach the writer. Give the replica a group of its own and name it with DB_SG."
      abort "❌ #{message}" if env_name.start_with?("production")

      puts "  ⚠ #{message}"
    end

    act("authorise #{machine_sg} → #{db_sg} on TCP #{db_port}") do
      ec2(env_name, config).authorize_security_group_ingress(
        group_id: db_sg,
        ip_permissions: [{
          ip_protocol: "tcp", from_port: db_port, to_port: db_port,
          user_id_group_pairs: [{ group_id: machine_sg, description: "irm-support-console read-only replica access" }]
        }]
      )
    rescue Aws::EC2::Errors::InvalidPermissionDuplicate
      puts "      rule already present"
    rescue Aws::EC2::Errors::ServiceError => e
      abort "❌ could not add the rule: #{e.message}"
    end
  end

  # --- verification ------------------------------------------------------------------------------

  # @return [Mysql2::Client, nil] nil (with an explanation) when the replica cannot be reached from here
  def connect_or_explain(replica, database, password)
    mysql_client(host: replica, username: ro_user, password: password, database: database)
  rescue StandardError => e
    puts "  · could not connect: #{e.message[0, 120]}"
    puts "    Expected from outside the VPC. Re-run support_console:db_access_check from a host that can reach it."
    nil
  end

  # Reads work, writes do not. Run where the replica is reachable; from a laptop
  # this simply cannot connect, which proves nothing either way.
  def verify!(env_name, replica, database, password)
    puts
    puts "Verifying as #{ro_user}@#{replica}/#{database}"
    client = connect_or_explain(replica, database, password)
    return nil unless client

    client.query("SET SESSION max_execution_time = #{STATEMENT_TIMEOUT_MS}")
    puts "  ✓ connected: MySQL #{client.query('SELECT VERSION() AS v').first['v']}"
    flags = client.query("SELECT @@global.read_only AS ro, @@global.super_read_only AS sro").first
    not_a_replica = false
    if flags["ro"].to_i == 1 && flags["sro"].to_i == 1
      puts "  ✓ read_only/super_read_only: 1/1"
    elsif env_name.start_with?("production")
      not_a_replica = true
      puts "  ✗ read_only/super_read_only: #{flags['ro']}/#{flags['sro']} — this is not a replica. " \
           "Point the support machine at a real one."
    else
      puts "  · read_only/super_read_only: #{flags['ro']}/#{flags['sro']} (1/1 on a real replica)"
    end
    puts "  ✓ entities visible: #{client.query('SELECT COUNT(*) AS n FROM entities').first['n']}"

    refused =
      begin
        client.query("CREATE TABLE _support_console_write_probe (id INT)")
        client.query("DROP TABLE IF EXISTS _support_console_write_probe")
        false
      rescue Mysql2::Error => e
        puts "  ✓ writes refused by the server: #{e.message[0, 80]}"
        true
      end
    puts "  ✗ a CREATE TABLE SUCCEEDED — the grants are wrong; do not use this until fixed" unless refused
    client.close
    # A production endpoint that is not read-only fails the check even when the grant refuses the
    # probe: the support machine would be pointed at the writer, which is the thing to catch.
    refused && !not_a_replica
  end

  def hand_off(env_name, parameter)
    puts
    puts "Next — the machine reads #{parameter} at boot; support_console:machine points it there:"
    puts "  EXECUTE=1 bundle exec rake \"support_console:machine[#{env_name}]\"         # if there is no machine yet"
    puts "  bundle exec rake \"support_console:machine_check[#{env_name}]\""
    puts
    puts "  openspec/changes/support-console/design.md (card ⑦) has the rest of the design."
  end
end

namespace :support_console do
  desc "Provision read-only replica access for the support machine: support_console:provision_db_access[staging.in] (EXECUTE=1 to apply)"
  task :provision_db_access, [:env_name] => :environment do |_t, args|
    include SupportConsoleDbAccess

    env_name = args[:env_name].to_s
    config = SupportConsoleDbAccess.env!(env_name)
    SupportConsoleDbAccess.instance_variable_set(:@env_name, env_name)

    puts
    puts "Support Console read-only access · #{env_name} · #{SupportConsoleDbAccess.region(config)} · " \
         "#{SupportConsoleDbAccess.execute? ? 'EXECUTE' : 'DRY RUN'}"
    puts

    SupportConsoleDbAccess.assert_account!(env_name, config)

    writer = SupportConsoleDbAccess.credential!(env_name, :DB_HOST)
    replica = SupportConsoleDbAccess.credential!(env_name, :DB_HOST_REPLICA)
    # Creating an account needs CREATE USER and GRANT OPTION, which the app's own database user does
    # not necessarily hold — on staging it does not. DB_ADMIN_USER/DB_ADMIN_PASS override it for this
    # one step; they are used here and stored nowhere.
    admin_user = ENV["DB_ADMIN_USER"].presence || SupportConsoleDbAccess.credential!(env_name, :DB_USER)
    admin_pass = ENV["DB_ADMIN_PASS"].presence || SupportConsoleDbAccess.credential!(env_name, :DB_PASS)
    database = ENV.fetch("DB_NAME", config[:database])
    SupportConsoleDbAccess.machine_account_host!(env_name, config)

    puts "Writer  (account is created here, grants replicate): #{writer}"
    puts "Replica (what the support machine reads):                    #{replica}"
    puts "Database: #{database}   Account: '#{SupportConsoleDbAccess.ro_user}'@'#{SupportConsoleDbAccess.account_host}'"
    if writer == replica
      puts "⚠ the writer and replica endpoints are identical — the support machine would hold a connection to " \
           "the writer. The account is still SELECT-only. On staging the data tool accepts that when the write " \
           "probe is refused (E24); on production it refuses any server whose read_only flags are off."
    end
    puts

    if env_name.start_with?("production") && SupportConsoleDbAccess.execute?
      puts "This creates an account on PRODUCTION's writer and opens a path to the production replica."
      puts "Do staging first, and use it, before running this here."
      print "Type the word production to continue: "
      abort "Stopped. Nothing was changed." unless $stdin.gets.to_s.strip == "production"
      puts
    end

    parameter = SupportConsoleDbAccess.parameter_name(env_name)
    password = nil

    if SupportConsoleDbAccess.skip_account?
      # The account already exists — a DBA applied the SQL this task printed. Use the password that is
      # already stored instead of generating one: rotating it needs the very privileges we lack — which
      # is why this path exists — and a rotation nobody can apply would leave the parameter holding a
      # password the account never had.
      puts "SKIP_ACCOUNT — the account is assumed to exist; no password is generated, #{parameter} is"
      puts "               read and not written, and the database is not touched as an admin."
      puts
      if SupportConsoleDbAccess.execute?
        details = SupportConsoleDbAccess.read_parameter!(env_name, config)
        password = details["SUPPORT_DB_PASSWORD"].to_s
        if password.empty?
          abort "❌ #{parameter} holds no SUPPORT_DB_PASSWORD — it was not written by this task. Re-run without " \
                "SKIP_ACCOUNT from a host whose account can CREATE USER."
        end

        stored_user = details["SUPPORT_DB_USER"].to_s
        if stored_user != SupportConsoleDbAccess.ro_user
          abort "❌ #{parameter} holds the account '#{stored_user}', not '#{SupportConsoleDbAccess.ro_user}'. " \
                "The support machine uses the stored one, so re-run with DB_USER_RO=#{stored_user}."
        end

        # The support machine reads the stored endpoint and database, so those are what must be verified — and a
        # disagreement with the credentials means the parameter is stale.
        drift = []
        drift << "SUPPORT_DB_HOST is #{details['SUPPORT_DB_HOST']}, credentials say #{replica}" if details["SUPPORT_DB_HOST"].to_s != replica
        drift << "SUPPORT_DB_NAME is #{details['SUPPORT_DB_NAME']}, this run says #{database}" if details["SUPPORT_DB_NAME"].to_s != database
        if drift.any?
          puts "⚠ #{parameter} disagrees with this run: #{drift.join('; ')}"
          puts "  The support machine uses the stored values, so those are what is verified below. Re-run without"
          puts "  SKIP_ACCOUNT once the account can be altered, to rewrite the parameter."
          puts
        end
        replica = details["SUPPORT_DB_HOST"].to_s.presence || replica
        database = details["SUPPORT_DB_NAME"].to_s.presence || database
      else
        puts "  · would read #{parameter} for the account's existing password"
      end
    else
      password = SupportConsoleDbAccess.generate_password

      if SupportConsoleDbAccess.execute? && !SupportConsoleDbAccess.reachable?(writer, admin_user, admin_pass)
        abort "❌ cannot reach #{writer} as #{admin_user}. Run this on an app host (cap " \
              "#{env_name.tr('.', '_')} rake:invoke, or over SSM) — the AWS steps work anywhere, the " \
              "database steps do not — and set DB_ADMIN_USER/DB_ADMIN_PASS if the app's own user " \
              "cannot create accounts."
      end

      # Store before rotating: if storing fails, the account still has its old password and nothing is
      # broken. The other order leaves an account whose password exists only in this process.
      previous = SupportConsoleDbAccess.previous_parameter_value(env_name, config)
      parameter = SupportConsoleDbAccess.store_parameter!(env_name, config, replica, database, password)
      begin
        SupportConsoleDbAccess.create_account!(env_name, writer, admin_user, admin_pass, database, password)
      rescue SystemExit, StandardError
        # The new password never reached the account (refused by policy, server unreachable, …): put the
        # parameter back so the running machine keeps working. Not on the access-denied hand-off, where
        # the DBA applies the SQL with exactly the stored password.
        SupportConsoleDbAccess.restore_parameter!(env_name, config, previous) unless SupportConsoleDbAccess.handed_to_dba?
        raise
      end
    end

    SupportConsoleDbAccess.grant_parameter_access!(env_name, config)
    SupportConsoleDbAccess.open_replica_port!(env_name, config, replica, writer)

    if SupportConsoleDbAccess.execute?
      SupportConsoleDbAccess.verify!(env_name, replica, database, password)
      SupportConsoleDbAccess.hand_off(env_name, parameter)
    else
      puts
      puts "DRY RUN — nothing was changed. Re-run with EXECUTE=1 to apply."
      puts "The security-group rule needs the support machine to exist (support_console:machine) — it is skipped until then."
    end
  end

  desc "Verify the support machine's read-only replica access, changing nothing: support_console:db_access_check[staging.in]"
  task :db_access_check, [:env_name] => :environment do |_t, args|
    env_name = args[:env_name].to_s
    config = SupportConsoleDbAccess.env!(env_name)
    SupportConsoleDbAccess.instance_variable_set(:@env_name, env_name)
    parameter = SupportConsoleDbAccess.parameter_name(env_name)

    details = SupportConsoleDbAccess.read_parameter!(env_name, config)
    puts
    puts "#{parameter} → #{details['SUPPORT_DB_USER']}@#{details['SUPPORT_DB_HOST']}/#{details['SUPPORT_DB_NAME']}"
    ok = SupportConsoleDbAccess.verify!(env_name, details["SUPPORT_DB_HOST"], details["SUPPORT_DB_NAME"], details["SUPPORT_DB_PASSWORD"])
    abort "❌ verification failed" if ok == false
  end
end

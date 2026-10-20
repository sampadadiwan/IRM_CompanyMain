# lib/tasks/support_console/machine.rake
#
# The Support Console machine (openspec/changes/support-console/design.md, cards ④⑤⑦): one small box
# per environment running the relay and the Claude Code CLI — signed in with a Claude subscription
# token or on Bedrock (SUPPORT_CONSOLE_AUTH) — reading the deployed code and the replica. The database side is lib/tasks/support_console/db_access.rake; this is the machine.
#
#   bundle exec rake "support_console:machine_preflight[staging.in]"   # can these credentials do it?
#   bundle exec rake "support_console:machine[staging.in]"             # DRY RUN — prints, changes nothing
#   EXECUTE=1 bundle exec rake "support_console:machine[staging.in]"   # create or converge it
#   EXECUTE=1 bundle exec rake "support_console:claude_token[staging.in]"  # store/rotate the subscription token
#   EXECUTE=1 bundle exec rake "support_console:publish_code[staging.in]"  # REV=<sha>; every deploy does this
#   bundle exec rake "support_console:machine_status[staging.in]"
#   bundle exec rake "support_console:machine_check[staging.in]"       # the ✓/✗ check, run on the machine
#   EXECUTE=1 bundle exec rake "support_console:machine_stop[staging.in]"   # / machine_start
#   TERMINATE=1 EXECUTE=1 bundle exec rake "support_console:machine_down[staging.in]"   # terminate; keeps the bucket
#
# NO HUMAN ACCESS. Support users reach the machine only through the app (design decision: no SSM
# sessions). Its one inbound rule is TCP 4900 from the app servers' security group, and every request
# must be HMAC-signed. Session Manager is enabled only for Run Command (machine_check), by admins.
#
# WHERE THE SETTINGS COME FROM
#   account, region, database   SupportConsoleDbAccess::ENVIRONMENTS + that environment's credentials
#   the subnet                  PRIVATE_SUBNET_ID in .env.<env>
#   the app servers' group      SUPPORT_CONSOLE_APP_SG, else the group of the instances named *AppServer*
#   how Claude signs in         SUPPORT_CONSOLE_AUTH: subscription (default) | bedrock — baked in at launch,
#                               so changing it means machine_down (TERMINATE=1) then machine
#   the subscription token      /irm/support-console/<env>/claude-token, stored by support_console:claude_token
#   the models                  SUPPORT_CONSOLE_MODEL_SONNET / _OPUS, else sonnet / opus (subscription) or
#                               the global Sonnet 5.5 / Opus 5.5 profiles (bedrock)
#   the budget alert emails     SUPPORT_CONSOLE_BUDGET_EMAIL, comma-separated (bedrock only; required with EXECUTE=1)
#
# SAFETY: DRY RUN by default (every mutating call goes through SupportConsoleDbAccess.act); the STS
# account must match the environment's; each step converges, so an interrupted run is finished by the
# next; machine_down on production asks for a typed acknowledgement. IN and US have separate machines,
# buckets, parameters, secrets and budgets, but share one AWS account (825199636520): the region keeps
# them apart, and each budget sees the account's combined Bedrock spend.
require "base64"
require "io/console"
require "json"
require "open3"
require "securerandom"
require "tmpdir"
require "aws-sdk-core"
require "aws-sdk-ec2"
require "aws-sdk-iam"
require "aws-sdk-s3"
require "aws-sdk-ssm"
require "aws-sdk-budgets"

module SupportConsoleMachine
  module_function

  # Shared with lib/tasks/support_console/db_access.rake, so both agree on what "staging.in" means.
  def execute? = SupportConsoleDbAccess.execute?
  def act(description, &) = SupportConsoleDbAccess.act(description, &)
  def region(config) = SupportConsoleDbAccess.region(config)
  def aws_options(env_name, config) = SupportConsoleDbAccess.aws_options(env_name, config)
  def ec2(env_name, config) = SupportConsoleDbAccess.ec2(env_name, config)
  def iam(env_name, config) = SupportConsoleDbAccess.iam(env_name, config)
  def ssm(env_name, config) = SupportConsoleDbAccess.ssm(env_name, config)
  def sts(env_name, config) = SupportConsoleDbAccess.sts(env_name, config)
  def s3(env_name, config) = @s3 ||= Aws::S3::Client.new(**aws_options(env_name, config))

  # Budgets is a global service whose API lives in us-east-1.
  def budgets(env_name, config)
    options = aws_options(env_name, config)
    options[:region] = "us-east-1"
    @budgets ||= Aws::Budgets::Client.new(**options)
  end

  def setup!(env_name)
    config = SupportConsoleDbAccess.env!(env_name)
    SupportConsoleDbAccess.assert_account!(env_name, config)
    config
  end

  RELAY_PORT = 4900
  VOLUME_GB = 40
  BUDGET_USD = 10 # approved 2026-10-16: alert only, per environment per month
  SSM_CORE_POLICY = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore".freeze
  UBUNTU_AMI_PARAMETER = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id".freeze
  SUPERSEDED_TAG = { key: "superseded", value: "true" }.freeze

  def instance_type = ENV.fetch("SUPPORT_CONSOLE_TYPE", "t3.medium")
  def slug(env_name) = env_name.tr(".", "-")
  def machine_name(env_name) = "irm-support-console-#{slug(env_name)}"
  def bucket(env_name) = "irm-support-console-#{slug(env_name)}"
  def budget_name(env_name) = "irm-support-console-bedrock-#{slug(env_name)}"
  def replica_parameter(env_name) = SupportConsoleDbAccess.parameter_name(env_name)
  def secret_parameter(env_name) = "/irm/support-console/#{env_name}/relay-secret"
  def token_parameter(env_name) = "/irm/support-console/#{env_name}/claude-token"
  # A plain String beside the token, not a tag: operators can get/put parameters but not read or write tags.
  def token_expiry_parameter(env_name) = "#{token_parameter(env_name)}-expires-at"

  AUTH_MODES = %w[subscription bedrock].freeze
  # A `claude setup-token` token is valid for a year; machine_check warns this many days before.
  TOKEN_LIFETIME_DAYS = 365
  TOKEN_WARN_DAYS = 30

  # E32 — how Claude Code on the machine signs in: a Claude subscription token (decided 2026-10-19) or Bedrock.
  def auth
    mode = ENV.fetch("SUPPORT_CONSOLE_AUTH", "subscription")
    abort "❌ SUPPORT_CONSOLE_AUTH must be one of #{AUTH_MODES.join(', ')}, not '#{mode}'" unless AUTH_MODES.include?(mode)

    mode
  end

  def subscription? = auth == "subscription"

  # The two models a support user can pick (Sonnet is the default). On a subscription token, Claude
  # Code's own aliases. On Bedrock, GLOBAL cross-region
  # inference profiles: base ids are refused on demand, and in ap-south-1 the apac.* profiles do not
  # offer Sonnet 5.5 / Opus 5.5 (probed on staging, 2026-10-16). Global profiles may run a request in
  # any AWS commercial region — accepted for all environments (decided 2026-10-16).
  # SUPPORT_CONSOLE_MODEL_SONNET / _OPUS override them.
  def models
    return { sonnet: ENV.fetch("SUPPORT_CONSOLE_MODEL_SONNET", "sonnet"), opus: ENV.fetch("SUPPORT_CONSOLE_MODEL_OPUS", "opus") } if subscription?

    { sonnet: ENV.fetch("SUPPORT_CONSOLE_MODEL_SONNET", "global.anthropic.claude-sonnet-5-5"),
      opus: ENV.fetch("SUPPORT_CONSOLE_MODEL_OPUS", "global.anthropic.claude-opus-5-5") }
  end

  def subnet!(env_name)
    file = Rails.root.join(".env.#{env_name}")
    abort "❌ #{file} is missing — that is where PRIVATE_SUBNET_ID lives" unless file.exist?

    value = file.readlines.grep(/^PRIVATE_SUBNET_ID=/).first.to_s.split("=", 2).last.to_s.strip.delete('"')
    abort "❌ PRIVATE_SUBNET_ID is not set in #{file}" if value.empty?

    value
  end

  # --- preflight ---------------------------------------------------------------------------------
  def required_permissions(env_name, config)
    account = config[:account]
    region = region(config)
    role = "arn:aws:iam::#{account}:role/#{machine_name(env_name)}"
    profile = "arn:aws:iam::#{account}:instance-profile/#{machine_name(env_name)}"
    bucket_arn = "arn:aws:s3:::#{bucket(env_name)}"
    instances = "arn:aws:ec2:#{region}:#{account}:instance/*"
    [
      ["the bucket", %w[s3:ListBucket s3:CreateBucket s3:PutBucketPublicAccessBlock s3:PutEncryptionConfiguration
                        s3:PutLifecycleConfiguration], [bucket_arn]],
      ["the bundles", %w[s3:PutObject s3:GetObject s3:PutObjectTagging], ["#{bucket_arn}/*"]],
      ["the instance role", %w[iam:GetRole iam:CreateRole iam:PutRolePolicy iam:AttachRolePolicy iam:PassRole], [role]],
      ["the instance profile", %w[iam:GetInstanceProfile iam:CreateInstanceProfile iam:AddRoleToInstanceProfile], [profile]],
      ["the machine", %w[ec2:DescribeSubnets ec2:DescribeSecurityGroups ec2:DescribeInstances ec2:CreateSecurityGroup
                         ec2:AuthorizeSecurityGroupIngress ec2:RunInstances ec2:CreateTags ec2:StopInstances
                         ec2:StartInstances ec2:TerminateInstances], ["*"]],
      ["the Ubuntu image id", %w[ssm:GetParameter], ["arn:aws:ssm:#{region}::parameter#{UBUNTU_AMI_PARAMETER}"]],
      ["the relay secret", %w[ssm:GetParameter ssm:PutParameter],
       ["arn:aws:ssm:#{region}:#{account}:parameter#{secret_parameter(env_name)}"]],
      ["the subscription token", %w[ssm:GetParameter ssm:PutParameter],
       [token_parameter(env_name), token_expiry_parameter(env_name)].map { |p| "arn:aws:ssm:#{region}:#{account}:parameter#{p}" }],
      ["the machine check (Run Command)", %w[ssm:SendCommand], [instances, "arn:aws:ssm:#{region}::document/AWS-RunShellScript"]],
      ["seeing it", %w[ssm:DescribeInstanceInformation ssm:GetCommandInvocation], ["*"]],
      (["the budget alarm", %w[budgets:ViewBudget budgets:ModifyBudget], ["arn:aws:budgets::#{account}:budget/#{budget_name(env_name)}"]] unless subscription?)
    ].compact
  end

  def principal_arn(caller_arn)
    match = caller_arn.match(%r{\Aarn:aws:sts::(\d+):assumed-role/([^/]+)/})
    match ? "arn:aws:iam::#{match[1]}:role/#{match[2]}" : caller_arn
  end

  def preflight!(env_name, config)
    principal = principal_arn(sts(env_name, config).get_caller_identity.arn)
    puts "Permissions for #{principal}"
    denied = []
    required_permissions(env_name, config).each do |label, actions, resources|
      results = iam(env_name, config).simulate_principal_policy(policy_source_arn: principal, action_names: actions,
                                                                resource_arns: resources).evaluation_results
      missing = results.reject { |r| r.eval_decision == "allowed" }.map(&:eval_action_name)
      puts format("  %-32s %s", label, missing.empty? ? "✓" : "✗ #{missing.join(' ')}")
      missing.each { |action| denied << [action, resources] }
    end
    puts
    return true if denied.empty?

    policy = { Version: "2012-10-17",
               Statement: denied.group_by(&:last).map { |resources, pairs| { Effect: "Allow", Action: pairs.map(&:first).uniq.sort, Resource: resources } } }
    warn "❌ These credentials cannot finish the job. Nothing has been created. Attach this to them, then re-run:\n\n" \
         "#{JSON.pretty_generate(policy)}\n\n   SKIP_PREFLIGHT=1 runs anyway, one exception at a time."
    abort
  rescue Aws::IAM::Errors::AccessDenied, Aws::IAM::Errors::InvalidInput => e
    puts "  · cannot simulate for this principal (#{e.class.name.demodulize}) — continuing unchecked"
    true
  end

  # --- the pieces (each converges) ---------------------------------------------------------------

  def bucket_exists?(env_name, config)
    s3(env_name, config).head_bucket(bucket: bucket(env_name))
    true
  rescue Aws::S3::Errors::NotFound, Aws::S3::Errors::NoSuchBucket
    false
  rescue Aws::S3::Errors::Forbidden
    abort "❌ the bucket #{bucket(env_name)} exists but these credentials cannot see it"
  end

  # Private and encrypted: code/ (the deployed code) and machine/ (relay + tools). Superseded bundles
  # expire after 30 days, so whatever the machine runs never does.
  def ensure_bucket!(env_name, config)
    name = bucket(env_name)
    client = s3(env_name, config)
    if bucket_exists?(env_name, config)
      puts "  · bucket #{name} exists"
    else
      act("create the bucket #{name}") do
        options = { bucket: name }
        options[:create_bucket_configuration] = { location_constraint: region(config) } if region(config) != "us-east-1"
        client.create_bucket(**options)
      end
    end
    act("apply the public-access block, encryption and expiry of superseded bundles to #{name}") do
      client.put_public_access_block(bucket: name, public_access_block_configuration: {
                                       block_public_acls: true, ignore_public_acls: true, block_public_policy: true, restrict_public_buckets: true
                                     })
      client.put_bucket_encryption(bucket: name, server_side_encryption_configuration: {
                                     rules: [{ apply_server_side_encryption_by_default: { sse_algorithm: "AES256" } }]
                                   })
      client.put_bucket_lifecycle_configuration(bucket: name, lifecycle_configuration: {
                                                  rules: %w[code machine].map do |prefix|
                                                    { id: "expire-superseded-#{prefix}", status: "Enabled",
                                                      filter: { and: { prefix: "#{prefix}/", tags: [SUPERSEDED_TAG] } }, expiration: { days: 30 } }
                                                  end
                                                })
    end
  end

  # The relay's HMAC secret: generated once, kept in Parameter Store; Rails gets the same value in its
  # credentials (SUPPORT_CONSOLE_RELAY_SECRET). Never printed.
  def ensure_secret!(env_name, config)
    name = secret_parameter(env_name)
    ssm(env_name, config).get_parameter(name: name)
    puts "  · relay secret #{name} exists"
  rescue Aws::SSM::Errors::ParameterNotFound
    act("store a new relay secret in #{name} (SecureString)") do
      ssm(env_name, config).put_parameter(name: name, value: SecureRandom.hex(32), type: "SecureString",
                                          description: "Support Console relay HMAC secret (#{env_name})")
    end
  end

  # --- the subscription token (E32) ----------------------------------------------------------------

  # @return [Time, nil] when the stored token expires (its -expires-at parameter); nil when the token was
  #   stored without one
  # @raise [Aws::SSM::Errors::ParameterNotFound] when no token has been stored
  def token_expires_at(env_name, config)
    # Raises ParameterNotFound when there is no token at all
    ssm(env_name, config).get_parameter(name: token_parameter(env_name))
    begin
      Time.zone.parse(ssm(env_name, config).get_parameter(name: token_expiry_parameter(env_name)).parameter.value)
    rescue Aws::SSM::Errors::ParameterNotFound
      # The token exists but its expiry was never recorded (e.g. stored before the expiry parameter existed)
      nil
    end
  end

  # Prints whether the token is stored and when it expires. Converge does not stop without it: the
  # machine's sync retries every 5 minutes, so the token can be stored before or after the machine.
  def report_token(env_name, config)
    expires_at = token_expires_at(env_name, config)
    days = expires_at && ((expires_at - Time.current) / 1.day).floor
    if days.nil?
      puts "  · subscription token #{token_parameter(env_name)} exists (expiry unknown)"
    elsif days < TOKEN_WARN_DAYS
      puts "  ⚠ subscription token expires #{expires_at.to_date} (#{days} days) — renew: claude setup-token, then " \
           "EXECUTE=1 rake \"support_console:claude_token[#{env_name}]\""
    else
      puts "  · subscription token #{token_parameter(env_name)} exists, expires #{expires_at.to_date}"
    end
  rescue Aws::SSM::Errors::ParameterNotFound
    puts "  ⚠ no subscription token yet — on your laptop run `claude setup-token`, then " \
         "EXECUTE=1 rake \"support_console:claude_token[#{env_name}]\" (answers fail until then)"
  rescue Aws::SSM::Errors::ServiceError => e
    # Reporting is advisory: a permission gap here must never stop the token from being stored or the check
    puts "  ⚠ could not read the subscription token's status: #{e.message}"
  end

  # Stores (or rotates) the token as a SecureString, then its expiry beside it. The value is never printed.
  def store_token!(env_name, config, token)
    name = token_parameter(env_name)
    expires_at = TOKEN_LIFETIME_DAYS.days.from_now.utc.iso8601
    act("store #{name} (SecureString), expires #{expires_at.first(10)}") do
      ssm(env_name, config).put_parameter(name: name, value: token, type: "SecureString", overwrite: true,
                                          description: "Support Console Claude subscription token (#{env_name})")
      # Written after the token, so a failure here leaves a working token with "expiry unknown"
      ssm(env_name, config).put_parameter(name: token_expiry_parameter(env_name), value: expires_at, type: "String",
                                          overwrite: true,
                                          description: "When the Support Console Claude token expires (#{env_name})")
    rescue Aws::SSM::Errors::ServiceError => e
      abort "❌ could not store #{name}: #{e.message}"
    end
  end

  ASSUME_ROLE_POLICY = JSON.generate(
    Version: "2012-10-17",
    Statement: [{ Effect: "Allow", Principal: { Service: "ec2.amazonaws.com" }, Action: "sts:AssumeRole" }]
  )

  # Read its bundles, read its parameters, and (on Bedrock) call the two Claude models — nothing else.
  def instance_policy(env_name, config)
    account = config[:account]
    region = region(config)
    bucket_arn = "arn:aws:s3:::#{bucket(env_name)}"
    # E32 — the subscription token is a third parameter; on Bedrock the role calls the models instead.
    parameters = [replica_parameter(env_name), secret_parameter(env_name)]
    parameters << token_parameter(env_name) if subscription?
    parameter_arns = parameters.map { |p| "arn:aws:ssm:#{region}:#{account}:parameter#{p}" }
    statements = [
      { Sid: "Bundles", Effect: "Allow", Action: %w[s3:GetObject], Resource: ["#{bucket_arn}/code/*", "#{bucket_arn}/machine/*"] },
      { Sid: "Parameters", Effect: "Allow", Action: %w[ssm:GetParameter], Resource: parameter_arns },
      # Only these parameters decrypt. AmazonSSMManagedInstanceCore grants ssm:GetParameter on every
      # parameter, so without the encryption-context condition any /irm SecureString would be readable.
      { Sid: "ParametersDecrypt", Effect: "Allow", Action: %w[kms:Decrypt], Resource: "*",
        Condition: { StringEquals: { "kms:ViaService" => "ssm.#{region}.amazonaws.com",
                                     "kms:EncryptionContext:PARAMETER_ARN" => parameter_arns } } }
    ]
    unless subscription?
      statements += [
        { Sid: "Bedrock", Effect: "Allow", Action: %w[bedrock:InvokeModel bedrock:InvokeModelWithResponseStream],
          Resource: bedrock_resources(account, region) },
        # Bedrock refuses Anthropic models (403) unless the calling role can see the account's AWS
        # Marketplace subscription (staging, 2026-10-17). Accepting it is a one-time act an admin does
        # (machine_check says how); the box itself cannot subscribe the account to anything.
        { Sid: "BedrockModelSubscription", Effect: "Allow", Action: %w[aws-marketplace:ViewSubscriptions], Resource: "*" }
      ]
    end
    JSON.generate(Version: "2012-10-17", Statement: statements)
  end

  # The two inference profiles, and the models behind them: a global profile routes a request to any
  # commercial region, so the foundation models are named in every region ("*") and region-less.
  #
  # @return [Array<String>] Bedrock ARNs
  def bedrock_resources(account, region)
    models.values.flat_map do |profile|
      model = profile.sub(/\A(global|us|eu|apac)\./, "")
      ["arn:aws:bedrock:#{region}:#{account}:inference-profile/#{profile}",
       "arn:aws:bedrock:*::foundation-model/#{model}*", "arn:aws:bedrock:::foundation-model/#{model}*"]
    end
  end

  def role_exists?(client, name)
    client.get_role(role_name: name)
    true
  rescue Aws::IAM::Errors::NoSuchEntity
    false
  end

  def ensure_role!(env_name, config)
    name = machine_name(env_name)
    client = iam(env_name, config)
    if role_exists?(client, name)
      puts "  · IAM role #{name} exists"
    else
      act("create the IAM role #{name}") { client.create_role(role_name: name, assume_role_policy_document: ASSUME_ROLE_POLICY) }
    end
    act("attach AmazonSSMManagedInstanceCore and put the support-console policy on #{name}") do
      client.attach_role_policy(role_name: name, policy_arn: SSM_CORE_POLICY)
      client.put_role_policy(role_name: name, policy_name: "support-console", policy_document: instance_policy(env_name, config))
    end
    profile = begin
      client.get_instance_profile(instance_profile_name: name).instance_profile
    rescue Aws::IAM::Errors::NoSuchEntity
      nil
    end
    act("create the instance profile #{name}") { client.create_instance_profile(instance_profile_name: name) } if profile.nil?
    if profile.nil? || profile.roles.none? { |role| role.role_name == name }
      act("put the role #{name} in its instance profile") do
        client.add_role_to_instance_profile(instance_profile_name: name, role_name: name)
        sleep 15 # IAM propagation before RunInstances can use it
      end
    end
    name
  end

  # The app servers' group: SUPPORT_CONSOLE_APP_SG, else the group of the running *AppServer* instances.
  def app_security_group(env_name, config, vpc)
    return ENV["SUPPORT_CONSOLE_APP_SG"] if ENV["SUPPORT_CONSOLE_APP_SG"].present?

    groups = ec2(env_name, config).describe_instances(
      filters: [{ name: "tag:Name", values: ["*AppServer*"] }, { name: "vpc-id", values: [vpc] },
                { name: "instance-state-name", values: %w[running] }]
    ).reservations.flat_map(&:instances).flat_map(&:security_groups).map(&:group_id).uniq
    puts "  · app servers' groups: #{groups.join(', ')}; using #{groups.first}" if groups.size > 1
    groups.first
  end

  def find_security_group(env_name, config, vpc = nil)
    filters = [{ name: "group-name", values: [machine_name(env_name)] }]
    filters << { name: "vpc-id", values: [vpc] } if vpc
    ec2(env_name, config).describe_security_groups(filters: filters).security_groups.first
  end

  # One inbound rule: the relay port, from the app servers only (design card ④).
  def ensure_security_group!(env_name, config, vpc)
    name = machine_name(env_name)
    group_id = find_security_group(env_name, config, vpc)&.group_id
    if group_id
      puts "  · security group #{name} exists (#{group_id})"
    else
      group_id = act("create the security group #{name}") do
        ec2(env_name, config).create_security_group(group_name: name, vpc_id: vpc,
                                                    description: "IRM Support Console #{env_name}: relay from app servers only").group_id
      end
    end

    app_sg = app_security_group(env_name, config, vpc)
    if app_sg.blank?
      puts "  · no app server group found (set SUPPORT_CONSOLE_APP_SG) — skipping the relay rule"
      return group_id
    end
    if group_id.blank?
      puts "  · would allow #{app_sg} (app servers) → the new group on TCP #{RELAY_PORT}"
      return group_id
    end
    act("allow #{app_sg} → #{group_id} on TCP #{RELAY_PORT}") do
      ec2(env_name, config).authorize_security_group_ingress(
        group_id: group_id,
        ip_permissions: [{ ip_protocol: "tcp", from_port: RELAY_PORT, to_port: RELAY_PORT,
                           user_id_group_pairs: [{ group_id: app_sg, description: "Rails to Support Console relay" }] }]
      )
    rescue Aws::EC2::Errors::InvalidPermissionDuplicate
      puts "      rule already present"
    end
    group_id
  end

  # $10/month on Bedrock for this account, alert only (questions are never blocked).
  def ensure_budget!(env_name, config)
    # E32 — a subscription is a flat plan with its own usage limits (X28); there is no Bedrock spend to watch.
    return puts("  · no Bedrock budget alarm: Claude signs in with a subscription token") if subscription?

    # Comma-separated; every address gets both alerts.
    emails = ENV["SUPPORT_CONSOLE_BUDGET_EMAIL"].to_s.split(",").map(&:strip).compact_blank
    if emails.empty?
      abort "❌ SUPPORT_CONSOLE_BUDGET_EMAIL is required to create the budget alarm" if execute?

      puts "  · would create the $#{BUDGET_USD}/month Bedrock budget alarm (set SUPPORT_CONSOLE_BUDGET_EMAIL)"
      return
    end
    name = budget_name(env_name)
    exists = budget_state(env_name, config, name)
    if exists.nil?
      # The preflight already lists budgets:ViewBudget/ModifyBudget as missing; a dry run says so and goes on.
      abort "❌ these credentials cannot read budgets (budgets:ViewBudget) — attach the preflight's policy" if execute?

      puts "  · cannot check the budget #{name} (no budgets:ViewBudget) — would create it for #{emails.join(', ')}"
      return
    end
    if exists
      puts "  · budget #{name} exists"
      return
    end

    act("create the budget #{name}: $#{BUDGET_USD}/month on Amazon Bedrock, alert #{emails.join(', ')} at 80% and 100%") do
      budgets(env_name, config).create_budget(
        account_id: config[:account],
        budget: { budget_name: name, budget_type: "COST", time_unit: "MONTHLY",
                  budget_limit: { amount: BUDGET_USD.to_s, unit: "USD" },
                  cost_filters: { "Service" => ["Amazon Bedrock"] } },
        notifications_with_subscribers: [80, 100].map do |threshold|
          { notification: { notification_type: "ACTUAL", comparison_operator: "GREATER_THAN", threshold: threshold,
                            threshold_type: "PERCENTAGE" },
            subscribers: emails.map { |address| { subscription_type: "EMAIL", address: address } } }
        end
      )
    end
  end

  # @return [Boolean, nil] whether the budget exists; nil when these credentials cannot tell
  def budget_state(env_name, config, name)
    budgets(env_name, config).describe_budget(account_id: config[:account], budget_name: name)
    true
  rescue Aws::Budgets::Errors::NotFoundException
    false
  rescue Aws::Budgets::Errors::AccessDeniedException
    nil
  end

  def find_instance(env_name, config)
    ec2(env_name, config).describe_instances(
      filters: [{ name: "tag:irm-support-console", values: [env_name] },
                { name: "instance-state-name", values: %w[pending running stopping stopped] }]
    ).reservations.flat_map(&:instances).first
  end

  def user_data(env_name, _config)
    template = Rails.root.join("config/support_console/user-data.sh")
    {
      "SUPPORT_CONSOLE_ENV" => env_name,
      "SUPPORT_CONSOLE_BUCKET" => bucket(env_name),
      "SUPPORT_CONSOLE_DB_PARAM" => replica_parameter(env_name),
      "SUPPORT_CONSOLE_SECRET_PARAM" => secret_parameter(env_name),
      "SUPPORT_CONSOLE_AUTH" => auth,
      "SUPPORT_CONSOLE_TOKEN_PARAM" => subscription? ? token_parameter(env_name) : "",
      "SUPPORT_CONSOLE_MODEL_SONNET" => models[:sonnet],
      "SUPPORT_CONSOLE_MODEL_OPUS" => models[:opus],
      # E24 — staging has no read replica, so its machine accepts the writer when the account's write
      # probe is refused. Never production: the data tool also ignores the flag there.
      "SUPPORT_CONSOLE_ALLOW_WRITER" => env_name.start_with?("production") ? "0" : "1"
    }.reduce(template.read) { |script, (key, value)| script.sub(/^#{key}=.*$/) { %(#{key}="#{value}") } }
  end

  def launch_instance!(env_name, config, subnet, security_group, role)
    name = machine_name(env_name)
    act("launch #{instance_type} #{name} in #{subnet} (no public IP, encrypted #{VOLUME_GB}GB root, models #{models.values.join(' / ')})") do
      ami = ssm(env_name, config).get_parameter(name: UBUNTU_AMI_PARAMETER).parameter.value
      attempts = 0
      begin
        attempts += 1
        ec2(env_name, config).run_instances(
          image_id: ami, instance_type: instance_type, min_count: 1, max_count: 1,
          subnet_id: subnet, security_group_ids: [security_group], iam_instance_profile: { name: role },
          metadata_options: { http_tokens: "required", http_put_response_hop_limit: 1, http_endpoint: "enabled" },
          block_device_mappings: [{ device_name: "/dev/sda1",
                                    ebs: { volume_size: VOLUME_GB, volume_type: "gp3", encrypted: true, delete_on_termination: true } }],
          user_data: Base64.strict_encode64(user_data(env_name, config)),
          tag_specifications: [
            { resource_type: "instance", tags: [{ key: "Name", value: name }, { key: "irm-support-console", value: env_name }] },
            { resource_type: "volume", tags: [{ key: "Name", value: name }] }
          ]
        ).instances.first.instance_id
      rescue Aws::EC2::Errors::InvalidParameterValue => e
        raise unless e.message.match?(/Invalid IAM Instance Profile/i) && attempts < 6

        sleep 10
        retry
      end
    end
  end

  # --- bundles ----------------------------------------------------------------------------------

  # Uploads <prefix>/<rev>.tar.gz, then moves <prefix>/current, then tags the previous one superseded,
  # so the machine never fetches half a file.
  def upload_bundle!(env_name, config, prefix, revision, tarball)
    objects = Aws::S3::Resource.new(client: s3(env_name, config)).bucket(bucket(env_name))
    previous = begin
      objects.object("#{prefix}/current").get.body.read.strip
    rescue Aws::S3::Errors::NoSuchKey
      nil
    end
    objects.object("#{prefix}/#{revision}.tar.gz").upload_file(tarball)
    objects.object("#{prefix}/current").put(body: revision)
    return unless previous.present? && previous != revision

    s3(env_name, config).put_object_tagging(bucket: bucket(env_name), key: "#{prefix}/#{previous}.tar.gz",
                                            tagging: { tag_set: [SUPERSEDED_TAG] })
  end

  # code/<rev>: the app code Claude reads. machine/<rev>: the relay, hook and db server with their
  # node_modules installed here, so the machine needs no npm registry.
  def publish_code!(env_name, config, revision)
    sha = SupportConsoleCodeArchive.git("rev-parse", revision).strip
    act("build #{sha.first(12)} and publish code/ and machine/ to s3://#{bucket(env_name)}/") do
      Dir.mktmpdir("support-console-") do |dir|
        SupportConsoleCodeArchive.extract(sha, File.join(dir, "code"))
        system("tar", "-czf", File.join(dir, "code.tar.gz"), "-C", File.join(dir, "code"), ".", exception: true)

        machine = File.join(dir, "machine")
        FileUtils.mkdir_p(machine)
        system("bash", "-o", "pipefail", "-c", "git archive #{sha} support_console/machine | tar -x -C #{machine} --strip-components=2",
               chdir: Rails.root.to_s, exception: true)
        system("npm", "ci", "--omit=dev", "--no-audit", "--no-fund", chdir: machine, exception: true)
        system("tar", "-czf", File.join(dir, "machine.tar.gz"), "-C", machine, ".", exception: true)

        upload_bundle!(env_name, config, "code", sha, File.join(dir, "code.tar.gz"))
        upload_bundle!(env_name, config, "machine", sha, File.join(dir, "machine.tar.gz"))
        puts "      ✓ code/current and machine/current → #{sha.first(12)} (the machine picks it up within 5 minutes)"
      end
    end
  end

  # --- on the machine ------------------------------------------------------------------------------

  def instance_or_abort(env_name, config)
    find_instance(env_name, config) || abort("❌ no Support Console machine for #{env_name} — " \
                                             "EXECUTE=1 bundle exec rake \"support_console:machine[#{env_name}]\"")
  end

  # Runs a shell line through Run Command and prints its output. Admin use only (machine_check).
  def ssm_run!(env_name, config, instance_id, script, timeout: 120)
    client = ssm(env_name, config)
    command_id = client.send_command(instance_ids: [instance_id], document_name: "AWS-RunShellScript",
                                     comment: "support_console:machine_check",
                                     parameters: { "commands" => [script], "executionTimeout" => [timeout.to_s] }).command.command_id
    deadline = Time.current + timeout
    invocation = nil
    loop do
      begin
        invocation = client.get_command_invocation(command_id: command_id, instance_id: instance_id)
      rescue Aws::SSM::Errors::InvocationDoesNotExist
        invocation = nil
      end
      break if invocation && %w[Pending InProgress Delayed].exclude?(invocation.status)

      abort "❌ the check did not finish within #{timeout}s" if Time.current > deadline

      sleep 5
    end
    puts invocation.standard_output_content
    warn invocation.standard_error_content if invocation.standard_error_content.present?
    invocation.status == "Success"
  end

  def delete_role!(env_name, config)
    name = machine_name(env_name)
    client = iam(env_name, config)
    profile = begin
      client.get_instance_profile(instance_profile_name: name).instance_profile
    rescue Aws::IAM::Errors::NoSuchEntity
      nil
    end
    if profile
      act("delete the instance profile #{name}") do
        profile.roles.each { |role| client.remove_role_from_instance_profile(instance_profile_name: name, role_name: role.role_name) }
        client.delete_instance_profile(instance_profile_name: name)
      end
    end
    return unless role_exists?(client, name)

    act("delete the role #{name} and its policies") do
      client.list_role_policies(role_name: name).policy_names.each { |policy| client.delete_role_policy(role_name: name, policy_name: policy) }
      client.list_attached_role_policies(role_name: name).attached_policies.each do |policy|
        client.detach_role_policy(role_name: name, policy_arn: policy.policy_arn)
      end
      client.delete_role(role_name: name)
    end
  end

  # The replica's rule for this group (support_console:provision_db_access) goes with the machine.
  def delete_security_group!(env_name, config, group_id)
    client = ec2(env_name, config)
    client.describe_security_groups(filters: [{ name: "ip-permission.group-id", values: [group_id] }]).security_groups.each do |group|
      group.ip_permissions.each do |permission|
        next if permission.user_id_group_pairs.none? { |pair| pair.group_id == group_id }

        act("revoke #{group.group_id}'s #{permission.ip_protocol}/#{permission.from_port} rule for #{group_id}") do
          client.revoke_security_group_ingress(group_id: group.group_id, ip_permissions: [{
                                                 ip_protocol: permission.ip_protocol, from_port: permission.from_port,
                                                 to_port: permission.to_port, user_id_group_pairs: [{ group_id: group_id }]
                                               }])
        end
      end
    end
    act("delete the security group #{group_id}") do
      attempts = 0
      begin
        attempts += 1
        client.delete_security_group(group_id: group_id)
      rescue Aws::EC2::Errors::DependencyViolation
        raise if attempts >= 12

        sleep 10
        retry
      end
    end
  end
end

namespace :support_console do
  desc "Check every AWS permission the Support Console machine needs, changing nothing: support_console:machine_preflight[staging.in]"
  task :machine_preflight, [:env_name] => :environment do |_t, args|
    env_name = args[:env_name].to_s
    config = SupportConsoleMachine.setup!(env_name)
    SupportConsoleMachine.preflight!(env_name, config)
  end

  desc "Create or converge the Support Console machine: support_console:machine[staging.in] (EXECUTE=1 to apply)"
  task :machine, [:env_name] => :environment do |_t, args|
    env_name = args[:env_name].to_s
    config = SupportConsoleMachine.setup!(env_name)
    puts "\nSupport Console machine · #{env_name} · #{SupportConsoleMachine.region(config)} · #{SupportConsoleMachine.execute? ? 'EXECUTE' : 'DRY RUN'}\n\n"
    SupportConsoleMachine.preflight!(env_name, config) if ENV["SKIP_PREFLIGHT"].blank?

    subnet = SupportConsoleMachine.subnet!(env_name)
    vpc = SupportConsoleMachine.ec2(env_name, config).describe_subnets(subnet_ids: [subnet]).subnets.first.vpc_id
    puts "Subnet #{subnet} in #{vpc}\n\n"

    SupportConsoleMachine.ensure_bucket!(env_name, config)
    SupportConsoleMachine.ensure_secret!(env_name, config)
    puts "  · Claude signs in with #{SupportConsoleMachine.subscription? ? 'a subscription token' : 'Bedrock'} (SUPPORT_CONSOLE_AUTH)"
    SupportConsoleMachine.report_token(env_name, config) if SupportConsoleMachine.subscription?
    role = SupportConsoleMachine.ensure_role!(env_name, config)
    group = SupportConsoleMachine.ensure_security_group!(env_name, config, vpc)
    SupportConsoleMachine.ensure_budget!(env_name, config)

    instance = SupportConsoleMachine.find_instance(env_name, config)
    if instance
      puts "  · machine #{instance.instance_id} exists (#{instance.state.name}, #{instance.private_ip_address})"
    else
      SupportConsoleMachine.launch_instance!(env_name, config, subnet, group, role)
    end

    puts
    if SupportConsoleMachine.execute?
      puts "Next:"
      puts "  1. EXECUTE=1 bundle exec rake \"support_console:publish_code[#{env_name}]\"   # every deploy does this too"
      puts "  2. EXECUTE=1 bundle exec rake \"support_console:provision_db_access[#{env_name}]\"  # account for this machine's IP; opens the replica to #{group}"
      puts "  3. Add to config/credentials/#{env_name}.yml.enc (the app finds the machine by its name tag, so no URL is needed):"
      puts "       SUPPORT_CONSOLE_RELAY_SECRET: <aws ssm get-parameter --name #{SupportConsoleMachine.secret_parameter(env_name)} --with-decryption>"
      puts "  4. bundle exec rake \"support_console:machine_check[#{env_name}]\" and \"support_console:app_machine_check[#{env_name}]\""
    else
      puts "DRY RUN — nothing was changed. Re-run with EXECUTE=1 to apply."
    end
  end

  desc "Publish a revision's code and machine bundles: support_console:publish_code[staging.in] (REV=, EXECUTE=1)"
  task :publish_code, [:env_name] => :environment do |_t, args|
    env_name = args[:env_name].to_s
    # Called after every deploy: an environment without a Support Console is not an error.
    unless SupportConsoleDbAccess::ENVIRONMENTS.key?(env_name)
      puts "  · #{env_name} has no Support Console — nothing to publish"
      next
    end
    config = SupportConsoleMachine.setup!(env_name)
    unless SupportConsoleMachine.bucket_exists?(env_name, config)
      puts "  · #{env_name} has no Support Console bucket — nothing to publish"
      next
    end
    SupportConsoleMachine.publish_code!(env_name, config, ENV.fetch("REV", "HEAD"))
  end

  desc "Where the Support Console machine is: support_console:machine_status[staging.in]"
  task :machine_status, [:env_name] => :environment do |_t, args|
    env_name = args[:env_name].to_s
    config = SupportConsoleMachine.setup!(env_name)
    instance = SupportConsoleMachine.instance_or_abort(env_name, config)
    ping = SupportConsoleMachine.ssm(env_name, config).describe_instance_information(
      filters: [{ key: "InstanceIds", values: [instance.instance_id] }]
    ).instance_information_list.first&.ping_status
    puts "#{instance.instance_id} #{instance.state.name} #{instance.private_ip_address} (SSM: #{ping || 'not registered'})"
  end

  desc "Check the app's own AWS keys can start and stop the machine (Start/Stop buttons, idle stop), " \
       "changing nothing: support_console:app_machine_check[staging.in]"
  task :app_machine_check, [:env_name] => :environment do |_t, args|
    env_name = args[:env_name].to_s
    config = SupportConsoleMachine.setup!(env_name)
    instance = SupportConsoleMachine.instance_or_abort(env_name, config)
    # The keys the app itself runs with (SupportConsoleMachine in app/), not the operator's
    creds = SupportConsoleDbAccess.credentials(env_name)
    app_keys = Aws::Credentials.new(SupportConsoleDbAccess.credential!(env_name, :AWS_ACCESS_KEY_ID),
                                    SupportConsoleDbAccess.credential!(env_name, :AWS_SECRET_ACCESS_KEY))
    region = SupportConsoleMachine.region(config)
    puts "App keys: #{Aws::STS::Client.new(region: region, credentials: app_keys).get_caller_identity.arn}"
    puts "Machine:  #{instance.instance_id} (#{instance.private_ip_address}, #{instance.state.name})"
    # H12, E37 — the app uses SUPPORT_CONSOLE_RELAY_URL when set, otherwise finds this machine by its name tag
    configured = creds[:SUPPORT_CONSOLE_RELAY_URL].presence
    ok = if configured
           relay_host = URI(configured).host
           puts "Relay:    SUPPORT_CONSOLE_RELAY_URL #{configured}#{' — not this machine' if relay_host != instance.private_ip_address}"
           relay_host == instance.private_ip_address
         else
           puts "Relay:    found by name tag #{SupportConsoleMachine.machine_name(env_name)} → http://#{instance.private_ip_address}:#{SupportConsoleMachine::RELAY_PORT}"
           true
         end
    puts "  ✗ SUPPORT_CONSOLE_RELAY_SECRET is missing from config/credentials/#{env_name}.yml.enc" if creds[:SUPPORT_CONSOLE_RELAY_SECRET].blank?
    ok &&= creds[:SUPPORT_CONSOLE_RELAY_SECRET].present?

    ec2 = Aws::EC2::Client.new(region: region, credentials: app_keys)
    # EC2 DryRun: answers DryRunOperation when allowed, UnauthorizedOperation when not — nothing changes
    %i[describe_instances start_instances stop_instances].each do |op|
      ec2.public_send(op, instance_ids: [instance.instance_id], dry_run: true)
      puts "  ✓ #{op}"
    rescue Aws::EC2::Errors::DryRunOperation
      puts "  ✓ #{op}"
    rescue Aws::EC2::Errors::ServiceError => e
      ok = false
      puts "  ✗ #{op}: #{e.message}"
    end
    abort "❌ the app cannot control this machine — grant its IAM user ec2:Describe/Start/StopInstances on it" unless ok
    puts "\nThe app can start and stop #{instance.instance_id}."
  end

  desc "Run the machine check on the Support Console machine: support_console:machine_check[staging.in]"
  task :machine_check, [:env_name] => :environment do |_t, args|
    env_name = args[:env_name].to_s
    config = SupportConsoleMachine.setup!(env_name)
    instance = SupportConsoleMachine.instance_or_abort(env_name, config)
    script = "cd /opt/support-console/current && sudo -u support-console node --env-file=/etc/support-console/machine.env scripts/check.js " \
             "&& curl -fsS http://$(. /etc/support-console/settings; echo $PRIVATE_IP):#{SupportConsoleMachine::RELAY_PORT}/health"
    ok = SupportConsoleMachine.ssm_run!(env_name, config, instance.instance_id, script)
    puts
    if SupportConsoleMachine.subscription?
      # X29 ahead of time: the token's expiry, from its tag.
      SupportConsoleMachine.report_token(env_name, config)
    else
      # The machine's role can see the Marketplace subscription but not accept it (instance_policy).
      puts "Claude models: the account's AWS Marketplace subscription is accepted once, by an admin, not by the machine."
      puts "  If answers fail with a Bedrock 403, sign in as an admin, open Bedrock → Model catalog in " \
           "#{SupportConsoleMachine.region(config)}, and run one prompt on each of #{SupportConsoleMachine.models.values.join(' / ')}"
      puts "  in the playground (the account needs a valid payment method for AWS Marketplace)."
    end
    abort "❌ machine check failed" unless ok
  end

  desc "Store or rotate the Claude subscription token the machine signs in with: support_console:claude_token[staging.in] (EXECUTE=1)"
  task :claude_token, [:env_name] => :environment do |_t, args|
    env_name = args[:env_name].to_s
    config = SupportConsoleMachine.setup!(env_name)
    puts "\nClaude subscription token · #{env_name} · #{SupportConsoleMachine.execute? ? 'EXECUTE' : 'DRY RUN'}\n\n"
    SupportConsoleMachine.report_token(env_name, config)
    unless SupportConsoleMachine.execute?
      puts "  · would read a token from the terminal (hidden) and store it in #{SupportConsoleMachine.token_parameter(env_name)}"
      puts "\nDRY RUN — nothing was changed. Get a token with `claude setup-token`, then re-run with EXECUTE=1."
      next
    end

    # Read hidden from the terminal (or piped in), so it never reaches shell history or process arguments.
    print "Paste the token from `claude setup-token` (hidden): "
    token = ($stdin.tty? ? $stdin.noecho(&:gets) : $stdin.gets).to_s.strip
    puts
    abort "❌ no token given — nothing was changed" if token.empty?
    # setup-token prints sk-ant-oat…; anything else is most likely a paste of the wrong thing.
    abort "❌ that does not look like a Claude token (expected sk-ant-…) — nothing was changed" unless token.start_with?("sk-ant-")

    SupportConsoleMachine.store_token!(env_name, config, token)
    puts "\nStored. The machine picks it up within 5 minutes; then run support_console:machine_check[#{env_name}]."
  end

  %w[stop start].each do |verb|
    desc "#{verb.capitalize} the Support Console machine: support_console:machine_#{verb}[staging.in] (EXECUTE=1)"
    task :"machine_#{verb}", [:env_name] => :environment do |_t, args|
      env_name = args[:env_name].to_s
      config = SupportConsoleMachine.setup!(env_name)
      instance = SupportConsoleMachine.instance_or_abort(env_name, config)
      SupportConsoleMachine.act("#{verb} #{instance.instance_id}") do
        SupportConsoleMachine.ec2(env_name, config).public_send(:"#{verb}_instances", instance_ids: [instance.instance_id])
      end
    end
  end

  desc "Terminate the Support Console machine and remove its role and security group (keeps the bucket, " \
       "secret and budget): support_console:machine_down[staging.in] (TERMINATE=1 EXECUTE=1)"
  task :machine_down, [:env_name] => :environment do |_t, args|
    env_name = args[:env_name].to_s
    config = SupportConsoleMachine.setup!(env_name)
    instance = SupportConsoleMachine.find_instance(env_name, config)
    # Terminating releases the machine's private IP, which the 'support_ro'@'<IP>' account (and any
    # SUPPORT_CONSOLE_RELAY_URL set by hand) is tied to — so it takes a second, explicit flag. machine_stop keeps the IP.
    if instance && SupportConsoleMachine.execute? && ENV["TERMINATE"].blank?
      abort "❌ machine_down terminates #{instance.instance_id} and releases #{instance.private_ip_address}: " \
            "'support_ro'@'#{instance.private_ip_address}' (and any SUPPORT_CONSOLE_RELAY_URL set by hand) would need redoing for " \
            "the next machine. To pause it, use machine_stop (keeps the IP). To terminate anyway, add TERMINATE=1. " \
            "Nothing was changed."
    end
    if env_name.start_with?("production") && SupportConsoleMachine.execute?
      print "This terminates the PRODUCTION Support Console machine. Type the word production to continue: "
      abort "Stopped. Nothing was changed." unless $stdin.gets.to_s.strip == "production"
    end
    if instance
      SupportConsoleMachine.act("terminate #{instance.instance_id}") do
        SupportConsoleMachine.ec2(env_name, config).terminate_instances(instance_ids: [instance.instance_id])
        SupportConsoleMachine.ec2(env_name, config).wait_until(:instance_terminated, instance_ids: [instance.instance_id])
      end
    end
    group = SupportConsoleMachine.find_security_group(env_name, config)
    SupportConsoleMachine.delete_security_group!(env_name, config, group.group_id) if group
    SupportConsoleMachine.delete_role!(env_name, config)
  end
end

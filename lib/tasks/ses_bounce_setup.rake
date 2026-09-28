# lib/tasks/ses_bounce_setup.rake
#
# Wires SES bounce/complaint events through SNS into the app, per environment.
#
#   DRY_RUN=1 bundle exec rake "ses:setup_bounce_tracking[staging.in]"   # show the plan
#   bundle exec rake "ses:setup_bounce_tracking[staging.in]"             # apply it
#   bundle exec rake "ses:verify_bounce_tracking[staging.in]"            # check it is live
#
# Unlike ses:bounce_stats this task WRITES to AWS. It is idempotent - every resource is
# looked up before it is created and re-running only fills in what is missing - but it does
# create an SNS topic, a topic policy, an SES configuration set, an event destination and an
# HTTPS subscription. Run it with DRY_RUN=1 first.
#
# Why this is needed: ApplicationMailer#tag_for_bounce_tracking stamps every notifier-driven
# message with X-CapHive-Tracking-Id, and adds X-SES-CONFIGURATION-SET only when
# SES_CONFIGURATION_SET is set. SES echoes both back inside the SNS payload, which is how
# ProcessSesNotificationJob correlates a bounce to its Noticed::Notification. Without the
# configuration set, SES publishes nothing and email_bounce_events stays empty - the app then
# shows "Sent" for mail that never arrived. See
# docs/operations/troubleshooting/24092026_peercapital_annual_report_email_bounces.md
#
# A CONFIGURATION SET is used deliberately, not identity-level notifications. Identity
# notifications publish events for every message the identity sends, including mail that
# never went through a notifier (magic links, KYC reminders, digests). Those carry no
# tracking id, so ProcessSesNotificationJob records them with a nil notification AND a nil
# entity_id, which makes them invisible in the entity-scoped UI. The configuration set is
# what scopes events to notifier-driven sends.
#
# Headers: configuration-set event publishing always includes mail.headers, so there is no
# "include original headers" toggle to set here. That option belongs to the legacy
# identity-notification path, which this task does not use.
#
# ENV overrides: TOPIC_NAME, CONFIG_SET, ENDPOINT, REGION, DRY_RUN
#
# aws-sdk-sesv2 lives in the Gemfile's :development group, so run this from a developer
# machine with admin AWS credentials. The app's own IAM user cannot create configuration
# sets, and does not need to - it only sends over SMTP.

module SesBounceSetup
  module_function

  ENDPOINT_PATH = "/ses_notifications".freeze
  EVENT_TYPES = %w[BOUNCE COMPLAINT].freeze
  DESTINATION_NAME = "sns-bounce-complaint".freeze

  def dry_run? = ENV["DRY_RUN"].present?

  def say(text) = puts("  #{text}")

  def did(text) = puts("  \e[32m+\e[0m #{text}")

  def skipped(text) = puts("  \e[2m= #{text}\e[0m")

  def planned(text) = puts("  \e[33m~\e[0m would #{text}")

  def rule(title)
    puts "\n\e[1m#{title}\e[0m"
    puts "=" * title.length
  end

  def region = ENV["REGION"].presence || ENV["AWS_REGION"].presence || "ap-south-1"

  # aws:environment has already loaded .env.<env_name>, so HOST is that environment's own
  # hostname. Deriving it rather than asking for it keeps the endpoint and the deployed app
  # in step - a subscription pointing at the wrong host silently never confirms.
  # Aborts rather than falling back. aws:environment only WARNS when .env.<env_name> is
  # missing, so a typo'd env name would otherwise leave HOST as the developer's own - and
  # this task would happily subscribe http://localhost:3000/ses_notifications to a real
  # topic, or report an environment it never actually looked at as "Wired."
  def require_env_file!(env_name)
    return if env_name.blank?

    path = Rails.root.join(".env.#{env_name}")
    return if File.exist?(path)

    abort "No #{path} - refusing to run against an environment whose settings could not be loaded."
  end

  def endpoint
    return ENV["ENDPOINT"] if ENV["ENDPOINT"].present?

    host = ENV["HOST"].presence or raise "HOST is not set for this environment - pass ENDPOINT=https://.../ses_notifications"
    host = "https://#{host}" unless host.start_with?("http")
    "#{host.chomp('/')}#{ENDPOINT_PATH}"
  end

  def slug(env_name) = (env_name.presence || Rails.env).to_s.tr(".", "-")

  def topic_name(env_name) = ENV["TOPIC_NAME"].presence || "caphive-ses-events-#{slug(env_name)}"

  def config_set_name(env_name) = ENV["CONFIG_SET"].presence || "caphive-#{slug(env_name)}"

  # ---- SNS ---------------------------------------------------------------

  # create_topic is itself idempotent (same name returns the existing ARN), but it is still
  # looked up first so a dry run never creates anything.
  def ensure_topic(sns, name)
    existing = find_topic(sns, name)
    if existing
      # "=" not "+": this run did not create it. Reporting a pre-existing resource with the
      # same marker as a created one makes a re-run's log read as though it rebuilt everything.
      skipped "topic exists: #{existing}"
      return existing
    end

    if dry_run?
      planned("create SNS topic #{name}")
      return nil
    end

    arn = sns.create_topic(name:).topic_arn
    did "created SNS topic #{arn}"
    arn
  end

  def find_topic(sns, name)
    token = nil
    loop do
      resp = sns.list_topics(next_token: token)
      hit = resp.topics.map(&:topic_arn).find { |arn| arn.split(":").last == name }
      return hit if hit

      token = resp.next_token
      return nil if token.blank?
    end
  end

  # Without this policy SES cannot publish and the events are dropped with no error anywhere.
  # SourceAccount pins it to this account so another account cannot publish into the topic.
  def ensure_topic_policy(sns, topic_arn, account_id)
    return planned("attach the SES publish policy allowing ses.amazonaws.com to publish") if topic_arn.nil?

    current = sns.get_topic_attributes(topic_arn:).attributes["Policy"].to_s
    if current.include?("ses.amazonaws.com")
      skipped "topic policy already allows ses.amazonaws.com"
      return
    end

    # Merged into whatever is already there, not substituted for it. SetTopicAttributes
    # replaces the document wholesale, so writing a fresh one would silently drop
    # __default_statement_ID (and anything else) - harmless on a topic this task created,
    # destructive if TOPIC_NAME points at a pre-existing shared topic.
    statement = {
      "Sid" => "AllowSESPublish",
      "Effect" => "Allow",
      "Principal" => { "Service" => "ses.amazonaws.com" },
      "Action" => "sns:Publish",
      "Resource" => topic_arn,
      "Condition" => { "StringEquals" => { "AWS:SourceAccount" => account_id } }
    }

    document = begin
      JSON.parse(current)
    rescue JSON::ParserError, TypeError
      { "Version" => "2012-10-17", "Statement" => [] }
    end
    document["Version"] ||= "2012-10-17"
    document["Statement"] = Array(document["Statement"]).reject { |st| st["Sid"] == "AllowSESPublish" } << statement
    policy = document.to_json

    return planned("attach the SES publish policy allowing ses.amazonaws.com to publish") if dry_run?

    sns.set_topic_attributes(topic_arn:, attribute_name: "Policy", attribute_value: policy)
    did "attached SES publish policy"
  end

  def ensure_subscription(sns, topic_arn, url)
    return planned("subscribe #{url}") if topic_arn.nil?

    existing = subscriptions(sns, topic_arn).find { |s| s.endpoint == url }
    if existing && existing.subscription_arn != "PendingConfirmation"
      skipped "subscription exists (confirmed): #{url}"
      return existing
    end

    if existing
      # Re-subscribing is how an unconfirmed endpoint is recovered: SNS re-sends the
      # confirmation. Reporting "exists" and returning would make a re-run a no-op in
      # exactly the state someone re-runs the task to fix.
      say "subscription for #{url} is PENDING CONFIRMATION - re-sending the confirmation"
    end

    return planned("subscribe #{url}") if dry_run?

    sns.subscribe(topic_arn:, protocol: "https", endpoint: url, return_subscription_arn: true)
    did "subscribed #{url}"
    say "SNS has POSTed a SubscriptionConfirmation - SesNotificationsController confirms it"
    say "automatically, so this should flip to confirmed within seconds."
    nil
  end

  def subscriptions(sns, topic_arn)
    results = []
    token = nil
    loop do
      resp = sns.list_subscriptions_by_topic(topic_arn:, next_token: token)
      results.concat(resp.subscriptions)
      token = resp.next_token
      break if token.blank?
    end
    results
  end

  # ---- SES ---------------------------------------------------------------

  def ensure_configuration_set(ses, name)
    sets = configuration_sets(ses)
    if sets == :unreadable
      planned("create configuration set #{name} (could not verify - see above)")
      return false
    end

    if sets.include?(name)
      skipped "configuration set exists: #{name}"
      return true
    end

    if dry_run?
      planned("create configuration set #{name}")
      return false
    end

    ses.create_configuration_set(configuration_set_name: name)
    did "created configuration set #{name}"
    true
  end

  # Returns nil (rather than raising) when SES cannot be read at all, so a dry run still
  # prints the rest of the plan instead of aborting on the first missing permission. The
  # IAM user that sends mail does not need these; whoever runs this task does.
  def configuration_sets(ses)
    names = []
    token = nil
    loop do
      resp = ses.list_configuration_sets(next_token: token)
      names.concat(Array(resp.configuration_sets))
      token = resp.next_token
      break if token.blank?
    end
    names
  rescue Aws::SESV2::Errors::ServiceError => e
    raise unless dry_run?

    planned("read SES, but: #{e.message}")
    :unreadable
  end

  # :unreadable when SES cannot be read at all (dry run with partial IAM), [] when the
  # configuration set genuinely has no destinations yet. These must not be the same value:
  # a freshly created configuration set returns NO event_destinations field at all, so the
  # SDK hands back nil - reading that as "could not verify" silently skipped creating the
  # destination on the very run that created the configuration set.
  def event_destinations(ses, config_set)
    Array(ses.get_configuration_set_event_destinations(configuration_set_name: config_set).event_destinations)
  rescue Aws::SESV2::Errors::NotFoundException
    []
  rescue Aws::SESV2::Errors::ServiceError
    raise unless dry_run?

    :unreadable
  end

  def ensure_event_destination(ses, config_set, topic_arn)
    return planned("publish #{EVENT_TYPES.join('/')} to the topic") if topic_arn.nil?

    existing = event_destinations(ses, config_set)
    return planned("publish #{EVENT_TYPES.join('/')} to the topic (could not verify - see above)") if existing == :unreadable

    destination = { enabled: true, matching_event_types: EVENT_TYPES, sns_destination: { topic_arn: } }
    match = existing.find { |d| d.name == DESTINATION_NAME }

    if match&.enabled && match.sns_destination&.topic_arn == topic_arn &&
       EVENT_TYPES.all? { |t| match.matching_event_types.include?(t) }
      skipped "event destination already publishes #{EVENT_TYPES.join('/')} to the topic"
      return
    end

    return planned("#{match ? 'update' : 'create'} event destination #{DESTINATION_NAME}") if dry_run?

    if match
      ses.update_configuration_set_event_destination(configuration_set_name: config_set,
                                                     event_destination_name: DESTINATION_NAME,
                                                     event_destination: destination)
      did "updated event destination #{DESTINATION_NAME}"
    else
      ses.create_configuration_set_event_destination(configuration_set_name: config_set,
                                                     event_destination_name: DESTINATION_NAME,
                                                     event_destination: destination)
      did "created event destination #{DESTINATION_NAME} -> #{EVENT_TYPES.join(', ')}"
    end
  end

  # ---- drivers -----------------------------------------------------------

  def setup(env_name)
    sns = Aws::SNS::Client.new(region:)
    ses = Aws::SESV2::Client.new(region:)
    account_id = Aws::STS::Client.new(region:).get_caller_identity.account

    name = topic_name(env_name)
    config_set = config_set_name(env_name)
    url = endpoint

    rule "SES bounce tracking setup#{' (DRY RUN - nothing will be written)' if dry_run?}"
    say "account       #{account_id}"
    say "region        #{region}"
    say "topic         #{name}"
    say "config set    #{config_set}"
    say "endpoint      #{url}"

    rule "SNS"
    topic_arn = ensure_topic(sns, name)
    ensure_topic_policy(sns, topic_arn, account_id)
    ensure_subscription(sns, topic_arn, url)

    rule "SES"
    ensure_configuration_set(ses, config_set)
    ensure_event_destination(ses, config_set, topic_arn)

    rule "Last step - the app side"
    if dry_run?
      say "re-run without DRY_RUN=1 to apply."
    else
      say "Add these to .env.#{env_name || Rails.env} and redeploy:"
      puts
      puts "    SES_CONFIGURATION_SET=#{config_set}"
      puts "    SES_SNS_TOPIC_ARN=#{topic_arn || "arn:aws:sns:#{region}:#{account_id}:#{name}"}"
      puts
      say "Without SES_CONFIGURATION_SET, tag_for_bounce_tracking omits the"
      say "X-SES-CONFIGURATION-SET header and SES publishes nothing."
      say "Without SES_SNS_TOPIC_ARN, /ses_notifications rejects everything: a valid SNS"
      say "signature alone does not prove a message came from YOUR topic."
      say ""
      say "Then confirm with:  bundle exec rake \"ses:verify_bounce_tracking[#{env_name}]\""
    end
  rescue Aws::Errors::MissingCredentialsError
    abort "No AWS credentials. Pass an env: bundle exec rake \"ses:setup_bounce_tracking[staging.in]\""
  rescue Aws::Errors::ServiceError => e
    abort "AWS call failed in #{region}: #{e.message}"
  end

  def verify(env_name)
    # verify never writes, so DRY_RUN has no meaning here - and if it leaked into the shell
    # from a setup run (the header tells operators to use it) configuration_sets would return
    # :unreadable and .include? on a Symbol would raise instead of reporting anything.
    ENV.delete("DRY_RUN")

    sns = Aws::SNS::Client.new(region:)
    ses = Aws::SESV2::Client.new(region:)

    name = topic_name(env_name)
    config_set = config_set_name(env_name)
    url = endpoint
    problems = []

    rule "Verifying SES bounce tracking"
    say "region #{region} | topic #{name} | config set #{config_set}"

    topic_arn = find_topic(sns, name)
    problems << "SNS topic #{name} does not exist" if topic_arn.nil?

    if topic_arn
      sub = subscriptions(sns, topic_arn).find { |s| s.endpoint == url }
      if sub.nil?
        problems << "no subscription for #{url}"
      elsif sub.subscription_arn == "PendingConfirmation"
        problems << "subscription for #{url} is still PendingConfirmation - the app never " \
                    "received the confirmation POST (is the host publicly reachable?)"
      else
        did "subscription confirmed: #{url}"
      end

      policy = sns.get_topic_attributes(topic_arn:).attributes["Policy"].to_s
      problems << "topic policy does not allow ses.amazonaws.com to publish" unless policy.include?("ses.amazonaws.com")
    end

    sets = configuration_sets(ses)
    if sets != :unreadable && sets.include?(config_set)
      # Array(): the API omits EventDestinations entirely for a configuration set with none,
      # so the SDK returns nil and a bare .select raises NoMethodError - in the very check
      # whose job is to report that the destination is missing.
      dests = Array(event_destinations(ses, config_set))

      # The destination must point at THE topic resolved above, not merely at some topic.
      # An enabled destination publishing to a different (legacy, hand-made, or stale-region)
      # topic would otherwise be reported as "Wired." while nothing reaches the app - exactly
      # the silent-success failure this task exists to catch.
      live = dests.select { |d| d.enabled && d.sns_destination&.topic_arn == topic_arn }
      problems << "configuration set #{config_set} publishes to a different SNS topic than #{topic_arn}" if live.empty? && dests.any? { |d| d.enabled && d.sns_destination }

      missing = EVENT_TYPES.reject { |t| live.any? { |d| d.matching_event_types.include?(t) } }
      if missing.any?
        problems << "configuration set publishes no #{missing.join('/')} events to #{topic_arn}"
      else
        did "configuration set publishes #{EVENT_TYPES.join(', ')} to the topic"
      end
    elsif sets == :unreadable
      problems << "could not read configuration sets"
    else
      problems << "configuration set #{config_set} does not exist"
    end

    expected_topic = ENV.fetch("SES_SNS_TOPIC_ARN", nil)
    if expected_topic.blank?
      problems << "SES_SNS_TOPIC_ARN is not set - /ses_notifications fails closed and will reject every event"
    elsif topic_arn && expected_topic != topic_arn
      problems << "SES_SNS_TOPIC_ARN is #{expected_topic.inspect} but this topic is #{topic_arn.inspect}"
    elsif expected_topic.present?
      did "SES_SNS_TOPIC_ARN=#{expected_topic}"
    end

    env_value = ENV.fetch("SES_CONFIGURATION_SET", nil)
    if env_value.blank?
      problems << "SES_CONFIGURATION_SET is not set in .env.#{env_name || Rails.env} - messages will carry no configuration set"
    elsif env_value != config_set
      problems << "SES_CONFIGURATION_SET is #{env_value.inspect} but this task configured #{config_set.inspect}"
    else
      did "SES_CONFIGURATION_SET=#{env_value}"
    end

    rule "Result"
    if problems.empty?
      say "\e[32mWired.\e[0m Send a test notification to bounce@simulator.amazonses.com, then:"
      puts
      puts "    EmailBounceEvent.order(created_at: :desc).limit(5)"
      puts "      .pluck(:recipient_email, :bounce_type, :bounce_subtype, :noticed_notification_id)"
      puts
      say "A non-nil noticed_notification_id proves header correlation works end to end."
    else
      problems.each { |p| puts "  \e[31mx\e[0m #{p}" }
      exit 1
    end
  rescue Aws::Errors::ServiceError => e
    abort "AWS call failed in #{region}: #{e.message}"
  end
end

namespace :ses do
  desc "Wire SES bounce/complaint events through SNS for an env (ENV: DRY_RUN, TOPIC_NAME, CONFIG_SET, ENDPOINT, REGION)"
  task :setup_bounce_tracking, [:env_name] => :environment do |_t, args|
    require "aws-sdk-sns"
    require "aws-sdk-sesv2"

    Rake::Task["aws:environment"].reenable
    SesBounceSetup.require_env_file!(args[:env_name])
    Rake::Task["aws:environment"].invoke(args[:env_name])

    SesBounceSetup.setup(args[:env_name])
  end

  desc "Check that SES bounce tracking is actually live for an env"
  task :verify_bounce_tracking, [:env_name] => :environment do |_t, args|
    require "aws-sdk-sns"
    require "aws-sdk-sesv2"

    Rake::Task["aws:environment"].reenable
    SesBounceSetup.require_env_file!(args[:env_name])
    Rake::Task["aws:environment"].invoke(args[:env_name])

    SesBounceSetup.verify(args[:env_name])
  end
end

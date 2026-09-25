# lib/tasks/ses_bounce_stats.rake
#
# Read-only SES bounce/complaint report — recovers delivery truth from AWS for
# windows where the app itself recorded nothing.
#
#   bundle exec rake ses:bounce_stats                       # booted env's credentials
#   bundle exec rake "ses:bounce_stats[production.in]"      # a specific env's AWS account
#     (staging.in / staging.us / production.in / production.us) — env selection via
#     aws:environment, same as aws:cost_audit; quote for zsh brackets
#   CN=413 bundle exec rake "ses:bounce_stats[production.in]"   # + name that
#     CustomNotification's recipients, and derive the window from its own send times
#   SINCE=2026-09-23 UNTIL=2026-09-25 bundle exec rake "ses:bounce_stats[production.in]"
#   REGION=us-east-1 bundle exec rake "ses:bounce_stats[production.us]"
#
# Why this exists: the in-app bounce pipeline (EmailBounceEvent /
# ProcessSesNotificationJob / POST /ses_notifications) is fully implemented, but
# the AWS side was never wired up — SES_CONFIGURATION_SET is absent from
# .env.production.*, so ApplicationMailer#tag_for_bounce_tracking never adds the
# X-SES-CONFIGURATION-SET header, SES never publishes to SNS, and
# email_bounce_events stays empty. Meanwhile `email_sent = true` on a
# Noticed::Notification only means SES's SMTP endpoint returned 250 OK — it says
# nothing about whether the recipient's server accepted the message, so the UI
# shows "Sent" for mail that bounced.
#
# Two AWS surfaces retain the truth anyway, with no configuration set:
#   - CloudWatch AWS/SES   Send/Delivery/Bounce/Complaint/Reject counters
#                          (15 months retention, 5-minute resolution)
#   - Suppression list     the addresses that hard-bounced, with reason and
#                          timestamp — but only if account-level suppression is
#                          enabled, which section 1 reports
#
# AWS credentials come from the aws:environment helper (aws.rake): the optional
# [env_name] rake arg picks .env.<env_name> + config/credentials/<env_name>.yml.enc
# and loads them into the global Aws.config, including AWS_REGION.
#
# CN= reads the LOCAL database this task is booted against (in development, the
# prod-restored MySQL on 33066) while the AWS calls hit [env_name]'s account —
# that pairing is intended: prod rows, prod SES.
#
# SAFETY: strictly read-only — only Get*/List* AWS calls, and only SELECTs
# against the database.
#
# aws-sdk-sesv2 is in the Gemfile's :development group, so this task is intended to be run
# from a developer machine (against the prod-restored dump and the chosen env's AWS account).
# On a server installed with BUNDLE_WITHOUT=development the require below raises LoadError —
# move the gem out of that group if it ever needs to run there.

# Helpers live in a top-level module (not inside the namespace block — defining
# constants in a block trips Lint/ConstantDefinitionInBlock and leaks scope).
module SesBounceStats
  module_function

  METRICS = %w[Send Delivery Bounce Complaint Reject].freeze

  # The console's own Reputation metrics chart draws "Warning" at 5% and
  # "Account at risk" at 10%.
  BOUNCE_RATE_WARNING_PCT = 5.0

  # ---- output -----------------------------------------------------------
  def rule(title)
    puts "\n\e[1m#{title}\e[0m"
    puts "=" * title.length
  end

  def row(label, value) = puts(format("  %-20s %s", label, value))

  def note(text) = puts("  \e[2m#{text}\e[0m")

  # A missing IAM permission or unavailable service must degrade one section,
  # not abort the whole report — the sections are independent, and the operator
  # running this often has partial SES access. Mirrors aws_cost_audit.rake#safe.
  # Returns `fallback` so callers can keep going with an empty result.
  def safe(label, fallback = nil)
    yield
  rescue Aws::Errors::ServiceError => e
    missing = MISSING_PERMISSION.match(e.message)
    if missing
      note "skipped #{label}: this IAM user lacks #{missing[1]}"
    else
      note "skipped #{label}: #{e.message}"
    end
    fallback
  end

  MISSING_PERMISSION = /not authorized to perform:\s*(\S+)/

  # aws:environment overloads AWS_REGION from .env.<env_name>; REGION= overrides.
  def default_region
    ENV["REGION"].presence || ENV["AWS_REGION"].presence || "ap-south-1"
  end

  # ---- window -----------------------------------------------------------
  #
  # Reinterpret an ActiveRecord timestamp as UTC, keeping its wall-clock digits.
  #
  # config.active_record.default_timezone = :local means AR stamps the SYSTEM
  # zone onto the raw DB value without converting it. Production runs UTC, so
  # there it is a no-op — but this task's whole point is to run from a laptop
  # against the prod-restored dump, and on an IST machine AR relabels a UTC
  # 14:51 as "14:51 +0530". Calling .utc on that then shifts the AWS window 5.5h
  # early and silently misses the send it was derived from. Verified against
  # CN 413: the DB reads 14:51, and CloudWatch shows that blast's 411 sends
  # (137 recipients x 3 addresses) in the 14:50-14:55Z buckets.
  def as_utc(time)
    Time.utc(time.year, time.month, time.day, time.hour, time.min, time.sec)
  end

  # A typo'd SINCE/UNTIL should say which variable is wrong, not surface as a bare
  # ArgumentError from deep inside Time.parse.
  def parse_bound(value, name)
    Time.parse(value.to_s).utc
  rescue ArgumentError
    abort "#{name}=#{value.inspect} is not a parseable time (try 2026-09-23 or 2026-09-23T14:00:00Z)"
  end

  def window_for(scope)
    first_at, last_at = scope.pick(Arel.sql("MIN(created_at), MAX(created_at)"))
    return nil if first_at.nil?

    # Pad generously forward: a TRANSIENT bounce is only reported once the
    # receiving server gives up retrying, which for Gmail is hours to days after
    # the send, not minutes. CN 413's bounces landed ~14h later.
    [as_utc(first_at) - 1.hour, as_utc(last_at) + 48.hours]
  end

  def notifications_for(custom_notification_id)
    event_ids = Noticed::Event.where(
      "JSON_UNQUOTE(JSON_EXTRACT(params, '$.custom_notification_id')) = ?",
      custom_notification_id.to_s
    ).select(:id)

    Noticed::Notification.where(event_id: event_ids)
  end

  # ---- 1. account posture ------------------------------------------------
  #
  # suppressed_reasons decides whether section 3 can say anything at all: empty
  # means SES keeps no account-level suppression list, so the per-address
  # history is simply gone.
  def report_account(ses)
    rule "1. Account sending posture"
    acct = safe("account posture") { ses.get_account }
    return if acct.nil?

    reasons = Array(acct.suppression_attributes&.suppressed_reasons)
    row "sending enabled", acct.sending_enabled
    row "enforcement status", acct.enforcement_status
    row "production access", acct.production_access_enabled
    row "max send rate", "#{acct.send_quota.max_send_rate}/sec"
    row "sent (24h)", "#{acct.send_quota.sent_last_24_hours.to_i} of #{acct.send_quota.max_24_hour_send.to_i}"
    row "suppression reasons", reasons.any? ? reasons.join(", ") : "NONE — account-level suppression is OFF"

    note "enforcement is not HEALTHY: SES may be throttling or pausing this account" if acct.enforcement_status != "HEALTHY"
    note "section 3 will be empty — enable this to retain future per-address bounce history" if reasons.empty?
  end

  # ---- 2. CloudWatch -----------------------------------------------------
  #
  # Preferred over SES GetSendStatistics: 5-minute buckets instead of 15, and 15
  # months of retention instead of 14 days, so this still works for an incident
  # found weeks later.
  # GetMetricStatistics refuses any request that would return more than 1440 datapoints, so the
  # period has to scale with the window: 5-minute buckets only fit about 5 days. At the default
  # 14-day window a fixed 300s asks for 4032 and the call fails — and because every AWS call
  # goes through `safe`, that failure would surface as a quiet "skipped CloudWatch metrics"
  # line, leaving the report's headline section blank and easily misread as "no bounces".
  #
  # Periods must also be multiples of 60.
  CLOUDWATCH_MAX_DATAPOINTS = 1440

  # CloudWatch also constrains the period by how old start_time is: any multiple of 60 only
  # within 15 days, a multiple of 300 from 15-63 days, and of 3600 beyond that. Rounding only
  # to 60 produced an InvalidParameterCombination for e.g. SINCE=24.days.ago - and because
  # every AWS call runs inside `safe`, that surfaced as one dim "skipped" line with the
  # report's headline section left blank, which reads as "no bounces".
  def period_for(start_time, end_time)
    seconds = (end_time - start_time).to_i
    age_days = (Time.now.utc - start_time) / 86_400.0
    granularity = if age_days > 63 then 3600
                  elsif age_days > 15 then 300
                  else 60
                  end

    minimum = (seconds.to_f / CLOUDWATCH_MAX_DATAPOINTS / granularity).ceil * granularity
    [300, minimum].max.then { |p| (p.to_f / granularity).ceil * granularity }
  end

  def datapoints(cloudwatch, metric, start_time, end_time)
    cloudwatch.get_metric_statistics(
      namespace: "AWS/SES", metric_name: metric,
      start_time:, end_time:, period: period_for(start_time, end_time), statistics: ["Sum"]
    ).datapoints
  end

  def report_metrics(cloudwatch, start_time, end_time)
    rule "2. CloudWatch AWS/SES"

    # One fetch per metric, reused for both the totals and the spike list below.
    series = safe("CloudWatch metrics") do
      METRICS.index_with { |metric| datapoints(cloudwatch, metric, start_time, end_time) }
    end
    return if series.nil?

    totals = series.transform_values { |points| points.sum { |p| p.sum.to_i } }
    totals.each { |metric, total| row metric, total }

    if totals["Send"].positive?
      pct = (totals["Bounce"] * 100.0 / totals["Send"]).round(2)
      puts
      row "bounce rate", "#{pct}%  (this window only)"
      if pct >= BOUNCE_RATE_WARNING_PCT
        # Deliberately NOT phrased as "your account is at risk". This is a
        # windowed count, not the number SES judges the account on: the console's
        # Historic bounce rate is computed over a long "representative volume" of
        # mail and lags by hours, so a one-day spike barely moves it. Observed on
        # 2026-09-24 — 36% here while the reputation page read 0.01% / Healthy.
        note "high for this window, but SES judges the account on its Historic bounce rate"
        note "(long trailing volume, lags hours) - check Reputation metrics in the console:"
        # default_region, not AWS_REGION: REGION= overrides it, so hardcoding the env var
        # would print a console link for a different region than the metrics above.
        note "https://#{default_region}.console.aws.amazon.com/ses/home?region=#{default_region}#/reputation"
        note "sustained windows like this are what eventually drag that number up"
      end
    end

    # Both Send and Bounce, so a spike can be read against the blast that caused
    # it. Timestamps carry the app's zone too: every timestamp in the database is
    # server-local, so a UTC-only listing is needlessly hard to line up against a
    # send time or a DSN in someone's mailbox.
    bucket = period_for(start_time, end_time)
    %w[Send Bounce].each { |metric| report_spikes(metric, series[metric], bucket) }
  end

  def report_spikes(metric, points, bucket_seconds)
    spikes = points.select { |p| p.sum.to_i.positive? }
    return if spikes.empty?

    puts "\n  peak #{bucket_seconds / 60}-min #{metric} buckets:"
    spikes.sort_by { |p| -p.sum }.first(8).sort_by(&:timestamp).each do |p|
      utc   = p.timestamp.utc
      local = utc.in_time_zone(Time.zone)
      puts "    #{utc.strftime('%m-%d %H:%M')}Z  =  #{local.strftime('%m-%d %H:%M %Z')}   #{p.sum.to_i}"
    end
  end

  # ---- 3. suppression list ----------------------------------------------
  #
  # The actual addresses, and the only retroactive per-address record available
  # while email_bounce_events is empty.
  # :unreadable rather than [] - "the IAM user cannot read this" and "nothing is suppressed"
  # are opposite facts, and reporting the first as the second states something untrue.
  def suppressed_destinations(ses, start_time, end_time)
    safe("suppression list", :unreadable) do
      results = []
      token   = nil

      loop do
        resp = ses.list_suppressed_destinations(
          start_date: start_time, end_date: end_time,
          reasons: %w[BOUNCE COMPLAINT], page_size: 100, next_token: token
        )
        results.concat(Array(resp.suppressed_destination_summaries))
        token = resp.next_token
        break if token.nil?
      end

      results
    end
  end

  def report_suppressed(suppressed, region)
    rule "3. Suppressed destinations (BOUNCE + COMPLAINT)"

    if suppressed == :unreadable
      puts "  \e[33mcould not be read\e[0m - this IAM user lacks ses:ListSuppressedDestinations."
      puts "  This is NOT the same as 'nothing is suppressed'."
      return
    end

    if suppressed.empty?
      puts "  (none in window)"
      return
    end

    puts "  #{suppressed.size} address(es):"
    suppressed.sort_by(&:last_update_time).each do |s|
      puts "    #{s.last_update_time.utc.iso8601}  #{s.reason.ljust(9)}  #{s.email_address}"
    end
    puts
    note "drill in:  aws --region #{region} sesv2 get-suppressed-destination --email-address <addr>"
    note "a suppressed address is silently dropped on every future send until removed with"
    note "aws sesv2 delete-suppressed-destination --email-address <addr>"
  end

  # ---- 4. configuration sets --------------------------------------------
  #
  # Whether any configuration set publishes BOUNCE/COMPLAINT anywhere — i.e. the
  # missing AWS-side wiring that leaves EmailBounceEvent empty.
  def report_configuration_sets(ses)
    rule "4. Configuration sets / event publishing"

    names = safe("configuration sets") do
      found = []
      token = nil
      loop do
        resp = ses.list_configuration_sets(next_token: token)
        found.concat(resp.configuration_sets)
        token = resp.next_token
        break if token.nil?
      end
      found
    end
    return if names.nil?

    if names.empty?
      puts "  No configuration sets exist in this account/region."
      note "=> nothing can publish Bounce/Complaint events to SNS"
      note "=> EmailBounceEvent stays empty no matter what the app does"
      return
    end

    names.each do |name|
      puts "  configuration set: #{name}"
      # Array(): the API omits EventDestinations for a set with none, so the SDK returns nil
      # and .empty? below would raise NoMethodError - which is not an Aws::Errors::ServiceError,
      # so it escapes `safe` and kills the whole report mid-run.
      destinations = Array(safe("event destinations for #{name}", []) do
        ses.get_configuration_set_event_destinations(configuration_set_name: name).event_destinations
      end)
      if destinations.empty?
        puts "    (no event destinations)"
        next
      end
      destinations.each do |d|
        puts "    - #{d.name}  enabled=#{d.enabled}  events=#{d.matching_event_types.join(',')}"
        puts "      sns: #{d.sns_destination.topic_arn}" if d.sns_destination
      end
    end

    puts
    note "for the app to record bounces, one of these must publish BOUNCE + COMPLAINT to an SNS"
    note "topic with a confirmed HTTPS subscription to POST /ses_notifications, and its name"
    note "must be set as SES_CONFIGURATION_SET in"
    note ".env.production.* — see docs/modules/notifications/ses_bounce_handling.md"
  end

  # ---- 5. name the investors --------------------------------------------
  #
  # Which recipients of this CustomNotification are suppressed — i.e. who
  # demonstrably did not receive it.
  def report_custom_notification(custom_notification_id, scope, suppressed)
    rule "5. CustomNotification #{custom_notification_id} recipients vs suppression list"

    sent, skipped, unsent = scope.pick(Arel.sql(<<~SQL.squish))
      SUM(email_sent = 1), SUM(skip_reason IS NOT NULL), SUM(email_sent = 0)
    SQL
    bounced = scope.where.not(bounced_at: nil).count

    row "handed to SES", sent.to_i
    row "never sent", unsent.to_i
    row "skipped", skipped.to_i
    row "bounce recorded", bounced.zero? ? "0  (in-app tracking is dark — see section 4)" : bounced

    # Dedup in SQL rather than pulling every row back — noticed_notifications is large.
    addresses = scope.where.not(email: nil)
                     .distinct
                     .pluck(Arel.sql("JSON_UNQUOTE(JSON_EXTRACT(email, '$.email.to'))"))
                     .compact
                     .flat_map { |v| v.split(",") }
                     .map { |v| v.strip.downcase }
                     .reject(&:empty?)
                     .uniq

    puts
    puts "  #{addresses.size} distinct recipient address(es) on record."

    by_email = suppressed.index_by { |s| s.email_address.downcase }
    matches  = addresses.filter_map { |a| by_email[a] }

    if matches.empty?
      puts "  No overlap — none of these addresses is currently suppressed."
      note "bounces can still have occurred without suppression: TRANSIENT bounces"
      note "(message-too-big, mailbox-full, rate-limited) never enter the suppression list"
      return
    end

    puts "  #{matches.size} of #{addresses.size} are suppressed:"
    matches.sort_by(&:last_update_time).each do |s|
      puts "    #{s.last_update_time.utc.iso8601}  #{s.reason.ljust(9)}  #{s.email_address}"
    end
  end

  def epilogue
    rule "Reading this"
    puts <<~TEXT
      A bounce spike in section 2 with nothing in section 3 usually means TRANSIENT
      bounces — message-too-big or mailbox-full. Those never enter the suppression
      list, so only the DSN in the sender's mailbox carries the SMTP diagnostic.
      Read one: the enhanced status code distinguishes the cause.
        5.3.4 / 5.2.3  message too large for the receiving server
        4.2.2 / 5.2.2  recipient mailbox over quota
        4.7.28         receiving server rate-limiting the sender

      Section 4 empty is the standing gap: until a configuration set publishes
      BOUNCE + COMPLAINT to SNS, none of this reaches EmailBounceEvent and the app
      keeps showing "Sent" for mail that never arrived.

      A "skipped ..." line above is an IAM gap, not an absence of data. This task
      needs these read-only actions on resource "*":
        ses:GetAccount                          ses:ListSuppressedDestinations
        ses:ListConfigurationSets               ses:GetSuppressedDestination
        ses:GetConfigurationSetEventDestinations
        cloudwatch:GetMetricStatistics
    TEXT
  end

  # ---- driver ------------------------------------------------------------
  def run
    region = default_region
    ses    = Aws::SESV2::Client.new(region: region)
    cw     = Aws::CloudWatch::Client.new(region: region)

    custom_notification_id = ENV["CN"].presence
    scope = custom_notification_id ? notifications_for(custom_notification_id) : nil

    if scope
      derived = window_for(scope)
      abort "No notifications found for custom_notification_id=#{custom_notification_id}." if derived.nil?
    end

    since  = ENV["SINCE"].presence
    until_ = ENV["UNTIL"].presence
    start_time = since  ? parse_bound(since, "SINCE")  : (derived&.first || 14.days.ago.utc)
    end_time   = until_ ? parse_bound(until_, "UNTIL") : (derived&.last  || Time.now.utc)
    abort "SINCE (#{start_time.iso8601}) is not before UNTIL (#{end_time.iso8601})" if start_time >= end_time

    rule "SES bounce report"
    row "region", region
    row "window", "#{start_time.iso8601} .. #{end_time.iso8601}  (UTC)"

    report_account(ses)
    report_metrics(cw, start_time, end_time)

    suppressed = suppressed_destinations(ses, start_time, end_time)
    report_suppressed(suppressed, region)
    report_configuration_sets(ses)
    report_custom_notification(custom_notification_id, scope, suppressed) if scope

    epilogue
  rescue Aws::Errors::MissingCredentialsError
    abort "No AWS credentials. Pass an env: bundle exec rake \"ses:bounce_stats[production.in]\""
  rescue Aws::Errors::ServiceError => e
    abort "AWS call failed in #{default_region}: #{e.message}"
  end
end

namespace :ses do
  desc "Read-only SES bounce/complaint report for an env's AWS account (ENV: CN, SINCE, UNTIL, REGION)"
  # `=> :environment` is safe here: there is no ses:environment, so it resolves to
  # the top-level Rails task. (Inside `namespace :aws` it would instead pick up
  # aws:environment and skip Rails initializers — see aws_cost_audit.rake.)
  task :bounce_stats, [:env_name] => :environment do |_t, args|
    require "aws-sdk-sesv2"
    require "aws-sdk-cloudwatch"

    Rake::Task["aws:environment"].reenable
    Rake::Task["aws:environment"].invoke(args[:env_name])

    SesBounceStats.run
  end
end

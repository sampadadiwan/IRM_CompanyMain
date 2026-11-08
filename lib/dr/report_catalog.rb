# frozen_string_literal: true

module Dr
  # Plain names, groups and explanations for every step and check a DR run report shows
  # (openspec dr-drill-report-redesign). The HTML and Markdown reports both read it, so each
  # explanation is written once.
  #
  # Entries are matched by PATTERN against the labels the run prints, because those labels carry
  # per-run parts (IPs, domains). The first match wins. An unrecognised check falls into "Other
  # checks" rather than vanishing, and features/misc/dr_drill_report.feature fails if dr:verify
  # or setup_infra gains a label this catalog does not cover.
  #
  # Pure constants and lookups: nothing here decides pass or fail - dr:verify does.
  module ReportCatalog
    # What CapHive promises clients about recovery - every DR report is measured against these.
    # Source of truth: the security questionnaire, H3 (RPO) and H4 (RTO). Change both together.
    PROMISES = {
      source: "Security questionnaire H3/H4 (docs/gtm/prerequisites/E2_security_questionnaire.md)",
      rpo_minutes: 30,
      rpo_text: "30 minutes, while backup-freshness alerts are green",
      rto_minutes: 10,
      rto_text: "about 10 minutes for a staging-sized dataset, scaling with database size"
    }.freeze

    # Group order is the order the report shows them in
    GROUPS = ["App servers", "Requests through the app", "Data", "Database servers", "Backups", "Other checks"].freeze

    # The steps of setup_infra, matched against its dr_phase titles
    STEPS = [
      { match: /Refresh Pulumi/, name: "Prepare the infrastructure settings",
        does: "Points the DR stack at the newest server images and the DR region.",
        if_fails: "Run rake aws:dr_readiness — usually a missing server image or setting." },
      { match: /Provision infrastructure/, name: "Create servers, network and load balancer",
        does: "Pulumi creates the app servers, the database primary and replica, the load balancer and its certificate.",
        if_fails: "The Pulumi error names the resource. \"Locked\" means another run is in progress." },
      { match: /Rewrite config/, name: "Point the app at the new servers",
        does: "Writes the new database, Redis and search addresses into the app's settings and deploy file, waits for the servers to accept SSH, and removes old backup jobs copied from the live box.",
        if_fails: "A missing address means the Pulumi output is incomplete — re-run; an SSH timeout names the server." },
      { match: /Commit and push/, name: "Save those settings on a recovery branch",
        does: "Commits only those settings to the recovery branch and pushes it, so the servers deploy exactly this code.",
        if_fails: "Check git access to origin and that the working tree had no conflicting edits." },
      { match: /Deploy the application/, name: "Install the app on both servers",
        does: "Installs Ruby, gems and the app on every app server. The longest step after the restore.",
        if_fails: "The Capistrano error names the server and the task that failed." },
      { match: /Take traffic offline/, name: "Take the site offline",
        does: "Maintenance page on; web and background workers stopped, so nothing writes while the database is restored.",
        if_fails: "Check nginx on the named server: sudo nginx -t." },
      { match: /Restore the database/, name: "Restore the database from backups",
        does: "Downloads the newest full backup and its incremental from S3 onto the primary and replica in parallel, then reconnects replication.",
        if_fails: "Look for the [primary] / [replica] lines in the transcript; the backup bucket and key are named there." },
      { match: /Start the search rebuild|Rebuild the search index/, name: "Start the search rebuild (background)",
        does: "Search is not backed up, so a background job is queued to rebuild every search index the live app maintains from the restored database. The site comes back without waiting; search results fill in as the job runs, and the checks below show its progress.",
        if_fails: "The transcript's table names the index and why; re-run one with ONLY=<Index> cap recovery:reindex_search." },
      { match: /Restore traffic and verify/, name: "Bring the site back and verify it",
        does: "Maintenance page off, then every check below runs on every app server. Any failed check fails the recovery.",
        if_fails: "The failed checks are listed under Needs attention, each with what to do." }
    ].freeze

    # Every check dr:verify can print. proves: what a pass means; if_fails: where to look.
    # keep_suffix: keep the label's "(…)" part (an IP or domain) in the shown name.
    CHECKS = [
      # App servers
      { match: /\ANginx active/, group: "App servers", name: "Web server (nginx) running",
        proves: "nginx is up and will hand requests to the app.", if_fails: "sudo nginx -t, then sudo systemctl status nginx." },
      { match: /\APuma process/, group: "App servers", name: "App processes (puma)",
        proves: "The Rails app server is running and can take requests.", if_fails: "sudo systemctl status puma_IRM_<stage>; the puma log names the error." },
      { match: /\ASidekiq workers registered/, group: "App servers", name: "Background jobs (sidekiq)",
        proves: "Sidekiq registered itself in Redis, so emails, documents and reports will be processed.", if_fails: "sudo systemctl status sidekiq_IRM_<stage>; check REDIS_URL points at the new DB box." },
      { match: /\Aprometheus_exporter process/, group: "App servers", name: "Monitoring exporter",
        proves: "Metrics will reach Grafana once monitoring is pointed at these servers.", if_fails: "cap <stage> IRM:start_boot_services." },
      # Requests through the app
      { match: /\AHTTP db_check/, group: "Requests through the app", name: "Database",
        proves: "A request went nginx → app → MySQL and back.", if_fails: "Check DB_HOST in the credentials and that mysqld is active on the primary." },
      { match: /\AHTTP redis_check/, group: "Requests through the app", name: "Cache",
        proves: "The app's cache works. It lives in MySQL (solid_cache), so this does not test Redis; the sidekiq check does.", if_fails: "Same as Database." },
      { match: /\AHTTP elastic_check/, group: "Requests through the app", name: "Search reachable",
        proves: "Elasticsearch answered. It does not prove search has data; \"Search index populated\" does.", if_fails: "Check the elasticsearch container on the DB box and ELASTIC_SEARCH_URL." },
      { match: /\AHTTP disk_check/, group: "Requests through the app", name: "Disk space",
        proves: "The root disk is under 95% full.", if_fails: "df -h / on the server; clear old releases and logs." },
      { match: /\AHTTP xirr_check/, group: "Requests through the app", name: "XIRR service",
        proves: "The Python XIRR container that fund returns use is running.", if_fails: "cap <stage> IRM:start_boot_services." },
      { match: /\AHTTP website apex/, group: "Requests through the app", name: "Public website", keep_suffix: true,
        proves: "The public website is served.", if_fails: "Rebuild and deploy the website (rake website:build)." },
      { match: /\AHTTP website alias/, group: "Requests through the app", name: "Website alias redirect", keep_suffix: true,
        proves: "The www address redirects to the main website.", if_fails: "Check the nginx website config." },
      { match: /\AStatic website/, group: "Requests through the app", name: "Public website",
        proves: "The website checks ran, or were skipped because this stack has no website.", if_fails: "See the detail." },
      # Data
      { match: /\AMigrations current/, group: "Data", name: "Database schema up to date",
        proves: "Every migration newer than the backup was applied.", if_fails: "cap <stage> recovery:migrate." },
      { match: /\ARestored data freshness/, group: "Data", name: "Restored data age",
        proves: "Age of the newest user/document row: the data a real recovery would have lost.", if_fails: "Above ~1 hour, check backups were running before the run (rake s3:check_backup_freshness)." },
      { match: /\ASearch index populated/, group: "Data", name: "Search index populated",
        proves: "Search holds the restored records: either the background rebuild's progress (queued, running, finished) or, with no recent rebuild, every index counted against the database. An incomplete index is a warning: the data is complete, only some search results are missing.", if_fails: "ONLY=<Index> bundle exec cap <stage> recovery:reindex_search." },
      { match: /\AS3 app bucket reachable/, group: "Data", name: "File storage (S3)",
        proves: "The app's own credentials can reach its document bucket.", if_fails: "Check AWS_S3_BUCKET and the app's AWS keys." },
      { match: /\ADrill stack marked/, group: "App servers", name: "Drill servers marked",
        proves: "The drill's servers carry DR_DRILL_STACK: their error mail is tagged and they never page WhatsApp.", if_fails: "Check DR_DRILL_STACK in the drill branch's .env, then redeploy." },
      { match: /\ANot marked as a drill/, group: "App servers", name: "Alerts page as normal",
        proves: "This recovered stack is not marked as a drill, so critical alerts page as normal.", if_fails: "Remove DR_DRILL_STACK from .env and redeploy — a recovered production must page." },
      { match: /\ADrill cannot contact users/, group: "App servers", name: "Drill cannot contact users",
        proves: "On this drill copy no email, WhatsApp, SMS or push can reach a user, and no timed job runs; the count shows what was held back.", if_fails: "Check DR_DRILL_STACK in the drill branch's .env and the boot log line \"DRILL STACK\"; redeploy." },
      { match: /\ADrill marker/, group: "App servers", name: "Drill marker",
        proves: "The drill/real marking of this stack could be read.", if_fails: "See the detail." },
      # Database servers
      { match: /\APrimary mysqld/, group: "Database servers", name: "Primary MySQL", keep_suffix: true,
        proves: "MySQL is running on the primary.", if_fails: "sudo systemctl status mysql on the primary (reach it via an app server)." },
      { match: /\APrimary docker: elasticsearch/, group: "Database servers", name: "Search engine container",
        proves: "The Elasticsearch container is running on the primary.", if_fails: "sudo /usr/local/bin/start_data_containers.sh on the primary." },
      { match: /\APrimary docker: redis/, group: "Database servers", name: "Redis container",
        proves: "The Redis container (background job queue) is running on the primary.", if_fails: "sudo /usr/local/bin/start_data_containers.sh on the primary." },
      { match: /\APrimary docker:/, group: "Database servers", name: "Data container on the primary",
        proves: "A container the app needs is running on the primary.", if_fails: "sudo /usr/local/bin/start_data_containers.sh on the primary." },
      { match: /\APrimary DB box/, group: "Database servers", name: "Primary database server reachable", keep_suffix: true,
        proves: "The app server could reach the primary over SSH to check it.", if_fails: "Check the DB security group and the KEYNAME key on the app server." },
      { match: /\AReplica mysqld/, group: "Database servers", name: "Replica MySQL", keep_suffix: true,
        proves: "MySQL is running on the replica.", if_fails: "sudo systemctl status mysql on the replica." },
      { match: /\AReplica DB box/, group: "Database servers", name: "Replica database server reachable", keep_suffix: true,
        proves: "The app server could reach the replica over SSH to check it.", if_fails: "Check the DB security group and the KEYNAME key on the app server." },
      { match: /\AReplication live round-trip/, group: "Database servers", name: "Replication round trip",
        proves: "A value written to the primary was read back from the replica seconds later.", if_fails: "SHOW REPLICA STATUS on the replica; cap <stage> partial:reset_replication." },
      { match: /\AReplication\z/, group: "Database servers", name: "Replication",
        proves: "This stack has no separate replica, so replication was not checked.", if_fails: "—" },
      # Backups
      { match: /\APrimary backup cron NOT armed \(drill\)/, group: "Backups", name: "Primary not armed (drill)",
        proves: "In a drill the rebuilt database must not write backups: the live box is still writing the same bucket. A real recovery arms it.", if_fails: "sudo rm /etc/db_backup_enabled on the drill primary at once." },
      { match: /\APrimary backup cron armed/, group: "Backups", name: "Primary armed for backups",
        proves: "The recovered primary is allowed to write backups (exactly one database may).", if_fails: "sudo touch /etc/db_backup_enabled on the primary." },
      { match: /\APrimary backup schedule/, group: "Backups", name: "Primary backup schedule",
        proves: "The timetable that runs backups exists, and no second, older backup job sits beside it.", if_fails: "sudo ls /etc/cron.d/irm-db-backup; crontab -l for old backup_db.sh lines." },
      { match: /\APrimary backup cron installed/, group: "Backups", name: "Primary backup schedule",
        proves: "The timetable that runs backups exists.", if_fails: "sudo ls /etc/cron.d/irm-db-backup on the primary." },
      { match: /\ABackup checkpoint fresh/, group: "Backups", name: "Backup checkpoint fresh",
        proves: "The first backup after the restore bases on the restored data, not on a checkpoint copied from the live box — so it can be restored.", if_fails: "sudo rm -rf /var/lib/xtrabackup/lsndir /var/lib/xtrabackup/lsndir-incr on the primary." },
      { match: /\AReplica backup cron disarmed/, group: "Backups", name: "Replica not armed",
        proves: "The replica is not allowed to write backups (one writer per chain).", if_fails: "sudo rm /etc/db_backup_enabled on the replica." },
      { match: /\AReplica has no backup writer/, group: "Backups", name: "Replica has no backup writer",
        proves: "No old backup job on the replica either — it can never write the backup chain.", if_fails: "crontab -l on the replica; remove backup_db.sh lines." }
    ].freeze

    # What an unrecognised check is shown as: visible, ungrouped, unexplained
    OTHER = { group: "Other checks", name: nil, proves: nil, if_fails: nil }.freeze

    module_function

    # [entry, display name] for a check label, e.g. "Primary mysqld (10.0.3.88)" →
    # [Primary MySQL entry, "Primary MySQL (10.0.3.88)"]
    def check(label)
      entry = CHECKS.find { |e| label.match?(e[:match]) }
      return [OTHER, label] unless entry

      # Keep the run-specific "(…)" part where it tells servers or sites apart
      suffix = entry[:keep_suffix] ? label[/\(([^)]*)\)\s*\z/, 0] : nil
      [entry, [entry[:name], suffix].compact.join(" ")]
    end

    # The entry for a setup_infra phase title; a generic one for an unknown title
    def step(title)
      STEPS.find { |e| title.match?(e[:match]) } ||
        { name: title.sub(%r{\APhase \d+/\d+ · }, ""), does: nil, if_fails: nil }
    end
  end
end

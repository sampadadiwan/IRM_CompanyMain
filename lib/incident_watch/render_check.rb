# frozen_string_literal: true

require 'fileutils'
require 'time'
require 'incident_watch/store'
require 'incident_watch/dashboard'

module IncidentWatch
  # Renders the dashboard with one incident in every state, interactive and static.
  #
  # This exists because of a real bug: an "Approve" button was added for the `analysed`
  # state while the helper it called had not been updated to accept its new argument. Rubocop
  # was clean and the parser selftest passed, because neither renders a row - the page only
  # blew up once a real incident reached that state, in the browser, as a 500.
  #
  # Every branch of the row/action/status rendering has to be exercised by something. This is
  # that something. Run it via `bin/incident-watch selftest`.
  class RenderCheck
    # One fixture per state, each carrying the fields that state's rendering path reads.
    def self.fixtures(now)
      base = {
        'exception_class' => 'NoMethodError', 'message' => "undefined method 'x' for nil",
        'location' => 'funds#show', 'occurrences' => 3,
        'culprit' => { 'path' => 'app/x.rb', 'line' => 10 },
        'last_seen' => (now - 120).iso8601
      }
      [
        base.merge('fingerprint' => 'st000new', 'state' => 'new'),
        base.merge('fingerprint' => 'st00disp', 'state' => 'dispatched',
                   'branch' => 'fix/incident-st00disp', 'state_changed_at' => (now - 300).iso8601),
        base.merge('fingerprint' => 'st00anal', 'state' => 'analysed',
                   'branch' => 'fix/incident-st00anal', 'rca_doc' => 'docs/incidents/x.md'),
        base.merge('fingerprint' => 'st00patc', 'state' => 'patching',
                   'branch' => 'fix/incident-st00patc', 'state_changed_at' => (now - 60).iso8601),
        base.merge('fingerprint' => 'st00done', 'state' => 'done',
                   'branch' => 'fix/incident-st00done', 'rca_doc' => 'docs/incidents/x.md'),
        base.merge('fingerprint' => 'st00dnpr', 'state' => 'done',
                   'branch' => 'fix/incident-st00dnpr', 'pr_url' => 'https://example.com/pull/9',
                   'pr_number' => 9),
        base.merge('fingerprint' => 'st00fail', 'state' => 'failed',
                   'branch' => 'fix/incident-st00fail', 'error' => 'no patch was committed'),
        base.merge('fingerprint' => 'st00pupr', 'state' => 'done',
                   'branch' => 'fix/incident-st00pupr', 'pr_error' => 'push failed: denied'),
        base.merge('fingerprint' => 'st00ignr', 'state' => 'ignored',
                   'ignored_reason' => 'bad data', 'ignored_by_rule' => true),
        # Degenerate record: a crash mid-write, or an old record from before a field existed.
        { 'fingerprint' => 'st00bare', 'state' => 'new' }
      ]
    end

    def self.run(repo_root, config, tmp_dir)
      now = Time.now.utc
      dir = File.join(tmp_dir, 'render_check')
      FileUtils.rm_rf(dir)
      store = Store.new(dir)
      fixtures(now).each { |incident| store.write(incident) }

      failures = []
      [true, false].each do |interactive|
        mode = interactive ? 'interactive' : 'static'
        begin
          html = Dashboard.new(repo_root, config, store, interactive: interactive).render
          failures << "#{mode}: rendered nothing" if html.to_s.empty?
          # Every fixture must actually appear - a swallowed exception that dropped a row
          # would otherwise look like a pass.
          fixtures(now).each do |incident|
            unless html.include?(incident['fingerprint'])
              failures << "#{mode}: #{incident['state']} row (#{incident['fingerprint']}) is missing"
            end
          end
        rescue StandardError => e
          failures << "#{mode}: #{e.class}: #{e.message}"
        end
      end

      # The RCA page, both for an approvable incident and a non-approvable one.
      %w[st00anal st00done].each do |fingerprint|
        Dashboard.new(repo_root, config, store, interactive: true)
                 .render_rca(store.find(fingerprint), "# RCA\n\nSome **markdown**.\n")
      rescue StandardError => e
        failures << "rca page #{fingerprint}: #{e.class}: #{e.message}"
      end

      FileUtils.rm_rf(dir)
      failures
    end
  end
end

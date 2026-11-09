# frozen_string_literal: true

require "base64"
require "yaml"
require "active_support/core_ext/enumerable" # index_by

# The extra Prometheus exporters on the data box (MySQL + Redis + Elasticsearch on one host), and
# the pure decisions around installing them — used by `rake observability:data_box_exporters`
# (lib/tasks/observability_exporters.rake) and features/misc/data_box_exporters.feature.
#
# Why: the data box sat at ~85% memory all week (IN, 2026-11-09) and Grafana could not say who
# held it — Prometheus scraped only node_exporter (whole box) and mysqld_exporter. These add:
# - elasticsearch_exporter :9114 — heap used/max, process RSS, index size, cluster health
# - redis_exporter         :9121 — used memory vs maxmemory, RSS, clients, keys
# - mysqld_exporter's perf_schema.memory_events collector — MySQL memory by area
# Both ports are already open from observability-sg in the DB security group
# (IRM-Infra/compute.py); a process-exporter (:9256) is NOT used because that port is not.
#
# Pure: no SSH, no AWS. The rake task fetches text from the boxes and acts on the answers.
module DataBoxExporters
  # One exporter we install as a systemd service from its GitHub release.
  # tag: the release tag; asset_version: how the version appears in the tarball name (the two
  # projects differ — redis_exporter keeps the "v", elasticsearch_exporter drops it).
  Exporter = Data.define(:name, :repo, :tag, :asset_version, :port, :args, :check_metric, :job, :service_url_env) do
    # Release tarball and the directory it unpacks to (both projects: <name>-<version>.linux-amd64)
    def dir = "#{name}-#{asset_version}.linux-amd64"
    def tarball = "#{dir}.tar.gz"
    def release_url = "https://github.com/#{repo}/releases/download/#{tag}"
    # The version string `<binary> --version` prints, without the leading v
    def version = tag.delete_prefix("v")
    def unit_path = "/etc/systemd/system/#{name}.service"
  end

  # Versions pinned on purpose: an upgrade is a repo change, reviewed like any other.
  # Latest releases checked 2026-11-09.
  ELASTICSEARCH = Exporter.new(
    name: "elasticsearch_exporter", repo: "prometheus-community/elasticsearch_exporter",
    tag: "v1.11.0", asset_version: "1.11.0", port: 9114,
    # --es.all: every node (one here); --es.indices: per-index size and doc counts
    args: "--es.uri=http://localhost:9200 --es.all --es.indices --web.listen-address=:9114",
    check_metric: "elasticsearch_jvm_memory_max_bytes", job: "elasticsearch",
    service_url_env: "ELASTIC_SEARCH_URL"
  )
  REDIS = Exporter.new(
    name: "redis_exporter", repo: "oliver006/redis_exporter",
    tag: "v1.97.0", asset_version: "v1.97.0", port: 9121,
    # --redis.addr pinned so a scrape never probes some other local instance
    args: "--redis.addr=redis://localhost:6379 --web.listen-address=:9121",
    check_metric: "redis_memory_used_bytes", job: "redis",
    service_url_env: "REDIS_URL"
  )
  EXPORTERS = [ELASTICSEARCH, REDIS].freeze

  # The Prometheus job names this change adds (and the only ones the push guard lets differ)
  NEW_JOBS = EXPORTERS.map(&:job).freeze

  # mysqld_exporter: the unit setup.sh writes, and the collector that adds MySQL's memory by area
  # (mysql_perf_schema_memory_events_used_bytes{event_name=...}).
  MYSQLD_UNIT_PATH = "/etc/systemd/system/mysqld_exporter.service"
  MEMORY_COLLECTOR = "--collect.perf_schema.memory_events"
  MEMORY_CHECK_METRIC = "mysql_perf_schema_memory_events_used_bytes"
  MYSQLD_EXEC_START = /\AExecStart=\S*mysqld_exporter(\s|\z)/

  # Which repo Prometheus config belongs to which environment. Staging has no Prometheus scraping
  # it, so there the exporters are installed but nothing is pushed.
  PROMETHEUS_FILES = {
    "production.in" => "config/initializers/observability/prometheus.prod.in.yml",
    "production.us" => "config/initializers/observability/prometheus.prod.us.yml"
  }.freeze
  # Where the observability box's Prometheus reads its config (observability.ami.pkr.hcl)
  LIVE_PROMETHEUS_PATH = "/etc/prometheus/prometheus.yml"

  module_function

  # The host a service URL points at: "10.0.3.182:9200" or "redis://10.0.3.182:6379" -> "10.0.3.182".
  def host_of(url)
    url.to_s.strip.sub(%r{\A\w+://}, "").sub(/\A[^@]*@/, "").split(%r{[:/]}).first.to_s
  end

  # The systemd unit for an exporter: its own no-login user, restarted if it dies, read-only
  # view of the system (it only makes HTTP calls to localhost).
  def unit(exporter)
    <<~UNIT
      [Unit]
      Description=#{exporter.name} #{exporter.version} (installed by rake observability:data_box_exporters)
      After=network-online.target docker.service
      Wants=network-online.target

      [Service]
      User=#{exporter.name}
      Group=#{exporter.name}
      ExecStart=/usr/local/bin/#{exporter.name} #{exporter.args}
      Restart=always
      RestartSec=5
      NoNewPrivileges=true
      ProtectSystem=strict
      ProtectHome=true

      [Install]
      WantedBy=multi-user.target
    UNIT
  end

  # A bash condition: does this /metrics endpoint serve a line starting with the metric?
  # NOT `curl | grep -q`: under `set -o pipefail`, grep -q exits at the first match, curl then
  # fails writing the rest (SIGPIPE / exit 23) and the pipeline reports a FOUND metric as missing.
  # elasticsearch_exporter's large /metrics (per-index stats) hit that every time on prod IN
  # (2026-11-09). Plain grep reads all of curl's output, so the pipeline's status is grep's.
  def metric_served(port, metric)
    "curl -fs http://localhost:#{port}/metrics | grep '^#{metric}' >/dev/null"
  end

  # The bash run on the data box (as ubuntu, sudo where needed) to install or upgrade one
  # exporter. Idempotent: the same version already running is left alone (ALREADY) but still
  # verified. The download is checked against the release's sha256sums.txt before anything is
  # installed. Ends by printing OK / ALREADY only once /metrics serves the exporter's check metric.
  def install_script(exporter)
    name = exporter.name
    <<~BASH
      set -euo pipefail
      # 1. Same version already installed and running: skip the install, still verify below
      state=OK
      if [ -x /usr/local/bin/#{name} ] && /usr/local/bin/#{name} --version 2>&1 | grep -F '#{exporter.version}' >/dev/null \\
         && systemctl is-active --quiet #{name}; then
        state=ALREADY
      else
        # 2. Download the release tarball and its checksum list into a scratch dir
        tmp=$(mktemp -d)
        trap 'rm -rf "$tmp"' EXIT
        # --retry covers GitHub's transient 5xx (a 504 on prod US, 2026-11-09) and timeouts
        curl -fsSL --retry 4 --retry-delay 5 -o "$tmp/#{exporter.tarball}" '#{exporter.release_url}/#{exporter.tarball}'
        curl -fsSL --retry 4 --retry-delay 5 -o "$tmp/sha256sums.txt" '#{exporter.release_url}/sha256sums.txt'
        # 3. Verify: the tarball's own line must be in the list and must match (fails the script if not)
        (cd "$tmp" && line=$(awk '$2 == "#{exporter.tarball}" || $2 == "*#{exporter.tarball}"' sha256sums.txt) \\
           && [ -n "$line" ] && echo "$line" | sha256sum -c -)
        # 4. Install the binary
        tar xzf "$tmp/#{exporter.tarball}" -C "$tmp"
        sudo install -m 0755 -o root -g root "$tmp/#{exporter.dir}/#{name}" /usr/local/bin/#{name}
        # 5. A dedicated system user that cannot log in
        id #{name} >/dev/null 2>&1 || sudo useradd --system --user-group --no-create-home --shell /usr/sbin/nologin #{name}
        # 6. The unit (base64 so quoting survives the SSH hops), then (re)start it
        echo #{Base64.strict_encode64(unit(exporter))} | base64 -d | sudo tee #{exporter.unit_path} >/dev/null
        sudo systemctl daemon-reload
        sudo systemctl enable #{name} >/dev/null 2>&1
        sudo systemctl restart #{name}
      fi
      # 7. Prove it: /metrics must serve the check metric within ~30 s
      for _ in $(seq 1 15); do
        if #{metric_served(exporter.port, exporter.check_metric)}; then
          echo "$state #{name} #{exporter.version} on :#{exporter.port}"
          exit 0
        fi
        sleep 2
      done
      echo "FAILED #{name}: :#{exporter.port}/metrics has no #{exporter.check_metric}"
      sudo journalctl -u #{name} -n 15 --no-pager || true
      exit 1
    BASH
  end

  # Adds the memory collector to mysqld_exporter's unit. Changes ONLY the ExecStart line; refuses
  # anything it does not recognise. Returns { status: :changed / :unchanged / :refused, text:, reason: }.
  def add_memory_collector(unit_text)
    lines = unit_text.to_s.lines.map(&:chomp)
    exec_starts = lines.each_index.select { |i| lines[i].match?(MYSQLD_EXEC_START) }

    # Never guess: exactly one ExecStart running mysqld_exporter
    return { status: :refused, text: unit_text, reason: "expected one mysqld_exporter ExecStart line, found #{exec_starts.size}" } unless exec_starts.size == 1

    index = exec_starts.first
    line = lines[index]
    # Run twice: the second run finds the collector already there
    return { status: :unchanged, text: unit_text, reason: "memory collector already enabled" } if line.split.include?(MEMORY_COLLECTOR)

    # Before --web.listen-address when present (reads like setup.sh's line), else at the end
    lines[index] = if line.include?(" --web.listen-address")
                     line.sub(" --web.listen-address", " #{MEMORY_COLLECTOR} --web.listen-address")
                   else
                     "#{line} #{MEMORY_COLLECTOR}"
                   end
    { status: :changed, text: "#{lines.join("\n")}\n", before: line, after: lines[index] }
  end

  # May the repo's Prometheus config replace the live one? Only when the two agree on everything
  # except the jobs this change adds — so a live edit nobody committed is never overwritten.
  # Returns { status: :push / :unchanged / :refused, reason: }.
  def prometheus_push_plan(live_text:, repo_text:)
    live = safe_yaml(live_text)
    repo = safe_yaml(repo_text)
    return { status: :refused, reason: "the live config could not be read as YAML (is Prometheus at #{LIVE_PROMETHEUS_PATH}?)" } unless live.is_a?(Hash)
    return { status: :refused, reason: "the repo config is not valid YAML" } unless repo.is_a?(Hash)

    # Identical already: a re-run after a successful push
    return { status: :unchanged, reason: "live config already matches the repo" } if live == repo

    # Compare with the new jobs taken out of both sides
    if without_new_jobs(live) == without_new_jobs(repo)
      { status: :push, reason: "live config differs only by the #{NEW_JOBS.join(' / ')} jobs" }
    else
      # A job differs when it is on one side only, or its scrape config is not identical
      live_jobs = job_map(live)
      repo_jobs = job_map(repo)
      differing = (live_jobs.keys | repo_jobs.keys).reject { |job| live_jobs[job] == repo_jobs[job] } - NEW_JOBS
      # Name what differs, so the operator can see whether it is a real edit or stray output
      settings = (live.keys | repo.keys).reject { |key| key == "scrape_configs" || live[key] == repo[key] }
      detail = differing.any? ? "jobs #{differing.join(', ')}" : "settings outside scrape_configs (#{settings.join(', ')})"
      { status: :refused, reason: "live config differs from the repo in #{detail} — commit the live change to the repo first" }
    end
  end

  # The scrape targets a repo Prometheus config gives one job, e.g. ["10.0.3.182:9114"].
  def targets_for(config_text, job)
    config = safe_yaml(config_text)
    return [] unless config.is_a?(Hash)

    scrape = Array(config["scrape_configs"]).find { |c| c["job_name"] == job }
    Array(scrape&.dig("static_configs")).flat_map { |s| Array(s["targets"]) }
  end

  def safe_yaml(text)
    YAML.safe_load(text.to_s)
  rescue Psych::Exception
    nil
  end

  # A config with this change's jobs removed (deep copy; the input is left alone)
  def without_new_jobs(config)
    copy = Marshal.load(Marshal.dump(config))
    copy["scrape_configs"] = Array(copy["scrape_configs"]).reject { |c| NEW_JOBS.include?(c["job_name"]) }
    copy
  end

  # { job_name => its scrape config } for naming which jobs differ
  def job_map(config)
    Array(config["scrape_configs"]).index_by { |c| c["job_name"] }
  end
end

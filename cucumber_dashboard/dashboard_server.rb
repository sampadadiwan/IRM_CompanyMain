#!/usr/bin/env ruby
# frozen_string_literal: true

require 'webrick'
require 'json'
require 'fileutils'

# Dashboard server for parallel Cucumber runs. Serves the UI, provides a
# polling endpoint for live progress, and can launch/stop test runs.
class DashboardServer
  PROGRESS_DIR = '/tmp/cucumber_progress'
  PORT = 9777
  DASHBOARD_DIR = File.dirname(__FILE__)
  PROJECT_DIR = File.expand_path('..', DASHBOARD_DIR)

  def initialize
    @server = WEBrick::HTTPServer.new(
      Port: PORT,
      Logger: WEBrick::Log.new('/dev/null'),
      AccessLog: []
    )
    @run_pid = nil
    @run_status = 'idle'

    setup_routes
    trap('INT') { stop_run; @server.shutdown }
    trap('TERM') { stop_run; @server.shutdown }
  end

  def start
    puts "\n  Cucumber Dashboard running at http://localhost:#{PORT}"
    puts "  Project: #{PROJECT_DIR}"
    puts "  Watching #{PROGRESS_DIR}/ for worker progress...\n\n"
    @server.start
  end

  private

  def setup_routes
    @server.mount_proc '/' do |_req, res|
      res['Content-Type'] = 'text/html'
      res.body = File.read(File.join(DASHBOARD_DIR, 'dashboard.html'))
    end

    @server.mount_proc '/poll' do |_req, res|
      res['Content-Type'] = 'application/json'
      res['Cache-Control'] = 'no-cache'

      cursor = parse_cursor(_req.query['cursor'] || '')
      events = []
      new_cursor = {}

      Dir.glob(File.join(PROGRESS_DIR, 'worker_*.jsonl')).sort.each do |f|
        worker_key = File.basename(f)
        pos = cursor[worker_key] || 0

        next unless File.exist?(f)

        size = File.size(f)
        if size > pos
          File.open(f) do |fh|
            fh.seek(pos)
            fh.each_line do |line|
              line = line.strip
              next if line.empty?

              parsed = JSON.parse(line) rescue nil
              events << parsed if parsed
            end
            new_cursor[worker_key] = fh.pos
          end
        else
          new_cursor[worker_key] = pos
        end
      end

      total = read_total_scenarios
      check_run_finished

      res.body = JSON.generate({
        events: events,
        cursor: encode_cursor(new_cursor),
        total_scenarios: total,
        run_status: @run_status,
        run_pid: @run_pid
      })
    end

    @server.mount_proc '/run' do |req, res|
      res['Content-Type'] = 'application/json'

      if @run_status == 'running'
        res.body = JSON.generate({ status: 'error', message: 'A run is already in progress' })
        next
      end

      body = req.body ? JSON.parse(req.body) : {}
      workers = (body['workers'] || 4).to_i.clamp(1, 16)
      feature_path = body['feature_path'] || 'features/'
      send_email = body['send_email'] || false
      email_to = body['email_to'] || ''

      # Check for pending migrations
      pending_check = `cd #{PROJECT_DIR} && RAILS_ENV=development bundle exec rails db:migrate:status 2>&1 | grep '^ *down' | head -5`
      unless pending_check.strip.empty?
        res.body = JSON.generate({ status: 'error',
          message: "Pending migrations found! Run 'bin/rails db:migrate' first.\n#{pending_check.strip}" })
        next
      end

      # Validate paths exist
      missing = feature_path.split(',').map(&:strip).reject do |p|
        File.exist?(File.join(PROJECT_DIR, p))
      end
      unless missing.empty?
        res.body = JSON.generate({ status: 'error', message: "Path not found: #{missing.join(', ')}" })
        next
      end

      # Clean previous progress
      FileUtils.rm_rf(PROGRESS_DIR)
      FileUtils.mkdir_p(PROGRESS_DIR)

      # Count total scenarios
      total = count_scenarios(feature_path)
      if total == 0
        res.body = JSON.generate({ status: 'error', message: 'No scenarios found in the selected paths' })
        next
      end
      File.write(File.join(PROGRESS_DIR, 'total_scenarios'), total.to_s)

      # Save run config for the completion handler
      File.write(File.join(PROGRESS_DIR, 'run_config.json'), JSON.generate({
        workers: workers,
        feature_path: feature_path,
        send_email: send_email,
        email_to: email_to,
        started_at: Time.now.iso8601
      }))

      # Clear previous console output
      File.write('/tmp/cucumber_full_output.txt', '')

      # Normalize comma-separated paths into space-separated for parallel_cucumber
      feature_args = feature_path.split(',').map(&:strip).join(' ')

      # Spawn parallel_cucumber in background
      cmd = "cd #{PROJECT_DIR} && bundle exec parallel_cucumber #{feature_args} -n #{workers}" \
            " -o \"--require features --require #{DASHBOARD_DIR} --format CucumberDashboard::ProgressFormatter --out /dev/null\"" \
            " > /tmp/cucumber_full_output.txt 2>&1"

      env = { 'RAILS_ENV' => 'test', 'RUBYOPT' => '-W0' }
      @run_pid = Process.spawn(env, cmd, pgroup: true)
      @run_status = 'running'
      Process.detach(@run_pid)

      res.body = JSON.generate({
        status: 'started',
        pid: @run_pid,
        workers: workers,
        total_scenarios: total
      })
    end

    @server.mount_proc '/stop' do |_req, res|
      res['Content-Type'] = 'application/json'
      stop_run
      res.body = JSON.generate({ status: 'stopped' })
    end

    @server.mount_proc '/console' do |req, res|
      res['Content-Type'] = 'application/json'
      res['Cache-Control'] = 'no-cache'
      log_file = '/tmp/cucumber_full_output.txt'
      offset = (req.query['offset'] || '0').to_i

      unless File.exist?(log_file)
        res.body = JSON.generate({ content: '', offset: 0 })
        next
      end

      size = File.size(log_file)
      if size > offset
        content = File.open(log_file) { |f| f.seek(offset); f.read }
        res.body = JSON.generate({ content: content, offset: size })
      else
        res.body = JSON.generate({ content: '', offset: offset })
      end
    end

    @server.mount_proc '/rerun_file' do |req, res|
      res['Content-Type'] = 'application/json'
      res['Cache-Control'] = 'no-cache'
      worker = req.query['worker']
      path = File.join(PROGRESS_DIR, "worker_#{worker}_failures.txt")
      if File.exist?(path)
        res.body = JSON.generate({ path: path, content: File.read(path) })
      else
        res.body = JSON.generate({ path: path, content: '' })
      end
    end

    @server.mount_proc '/reset' do |_req, res|
      FileUtils.rm_rf(PROGRESS_DIR)
      FileUtils.mkdir_p(PROGRESS_DIR)
      @run_status = 'idle'
      @run_pid = nil
      res['Content-Type'] = 'application/json'
      res.body = JSON.generate({ status: 'ok' })
    end

    @server.mount_proc '/send_email' do |req, res|
      res['Content-Type'] = 'application/json'

      body = req.body ? JSON.parse(req.body) : {}
      email_to = body['email_to']
      smtp_config = {
        'CUCUMBER_SMTP_USER' => body['smtp_user'],
        'CUCUMBER_SMTP_PASSWORD' => body['smtp_pass'],
        'CUCUMBER_SMTP_ADDRESS' => body['smtp_host']
      }.compact
      summary = body['summary'] || {}
      type = body['type'] || 'completion'

      if email_to.nil? || email_to.empty?
        res.body = JSON.generate({ status: 'error', message: 'No email address provided' })
        next
      end

      case type
      when 'start'
        send_start_email(email_to, body['config'] || {}, smtp_config)
      when 'failure'
        send_failure_email(email_to, body['failure'] || {}, smtp_config)
      else
        send_completion_email(email_to, summary, smtp_config)
      end
      res.body = JSON.generate({ status: 'sent' })
    end
  end

  def stop_run
    # Kill tracked process group if we have one
    if @run_pid
      begin
        Process.kill('-TERM', @run_pid)
        sleep 0.5
        Process.kill('-KILL', @run_pid)
      rescue Errno::ESRCH
        # already gone
      end
    end

    # Kill any remaining parallel_cucumber or cucumber workers
    system("pkill -f 'parallel_cucumber' 2>/dev/null")
    system("pkill -f 'cucumber.*features' 2>/dev/null")

    @run_status = 'stopped'
    @run_pid = nil
  end

  def check_run_finished
    return unless @run_status == 'running' && @run_pid

    begin
      pid, status = Process.waitpid2(@run_pid, Process::WNOHANG)
      if pid
        @run_status = 'finished'
        @run_pid = nil
      end
    rescue Errno::ECHILD
      @run_status = 'finished'
      @run_pid = nil
    end
  end

  def count_scenarios(feature_path)
    paths = feature_path.split(',').map(&:strip)
    count = 0
    paths.each do |p|
      full = File.join(PROJECT_DIR, p)
      files = if File.file?(full)
                [full]
              else
                Dir.glob(File.join(full, '**/*.feature'))
              end
      files.each do |f|
        File.readlines(f).each do |line|
          count += 1 if line.strip.match?(/^Scenario/)
        end
      end
    end
    count
  rescue StandardError
    0
  end

  def send_start_email(to, config, smtp_config = {})
    require_path = File.join(DASHBOARD_DIR, 'completion_mailer.rb')
    script = <<~RUBY
      require '#{PROJECT_DIR}/config/environment'
      require '#{require_path}'
      CucumberDashboard::CompletionMailer.run_started('#{to}', #{config.to_json.inspect}).deliver_now
    RUBY
    pid = Process.spawn(smtp_config, "ruby", "-e", script, chdir: PROJECT_DIR)
    Process.detach(pid)
  rescue StandardError => e
    puts "  Start email send failed: #{e.message}"
  end

  def send_completion_email(to, summary, smtp_config = {})
    require_path = File.join(DASHBOARD_DIR, 'completion_mailer.rb')
    script = <<~RUBY
      require '#{PROJECT_DIR}/config/environment'
      require '#{require_path}'
      CucumberDashboard::CompletionMailer.run_complete('#{to}', #{summary.to_json.inspect}).deliver_now
    RUBY
    pid = Process.spawn(smtp_config, "ruby", "-e", script, chdir: PROJECT_DIR)
    Process.detach(pid)
  rescue StandardError => e
    puts "  Email send failed: #{e.message}"
  end

  def send_failure_email(to, failure, smtp_config = {})
    require_path = File.join(DASHBOARD_DIR, 'completion_mailer.rb')
    script = <<~RUBY
      require '#{PROJECT_DIR}/config/environment'
      require '#{require_path}'
      CucumberDashboard::CompletionMailer.scenario_failed('#{to}', #{failure.to_json.inspect}).deliver_now
    RUBY
    pid = Process.spawn(smtp_config, "ruby", "-e", script, chdir: PROJECT_DIR)
    Process.detach(pid)
  rescue StandardError => e
    puts "  Failure email send failed: #{e.message}"
  end

  def parse_cursor(str)
    return {} if str.nil? || str.empty?

    result = {}
    str.split(',').each do |part|
      key, val = part.split(':', 2)
      result[key] = val.to_i if key && val
    end
    result
  end

  def encode_cursor(hash)
    hash.map { |k, v| "#{k}:#{v}" }.join(',')
  end

  def read_total_scenarios
    path = File.join(PROGRESS_DIR, 'total_scenarios')
    return nil unless File.exist?(path)

    File.read(path).strip.to_i
  rescue StandardError
    nil
  end
end

if __FILE__ == $PROGRAM_NAME
  FileUtils.mkdir_p(DashboardServer::PROGRESS_DIR)
  DashboardServer.new.start
end

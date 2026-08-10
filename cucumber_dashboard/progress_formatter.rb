# frozen_string_literal: true

require 'json'
require 'fileutils'

# Custom Cucumber formatter that writes JSON progress events to a per-worker file.
# Each parallel_cucumber worker gets its own log file under /tmp/cucumber_progress/.
# Failed scenarios are also written to a per-worker text file for easy rerun.
module CucumberDashboard
  class ProgressFormatter
    PROGRESS_DIR = '/tmp/cucumber_progress'

    # @param config [Cucumber::Configuration] cucumber event bus configuration
    def initialize(config)
      @config = config
      @worker_id = ENV.fetch('TEST_ENV_NUMBER', '1')
      @worker_id = '1' if @worker_id.empty?
      @current_feature = nil
      @current_scenario = nil
      @scenario_start_time = nil
      @feature_start_time = nil
      @counts = { passed: 0, failed: 0, skipped: 0, pending: 0 }
      @total_scenarios = 0
      @feature_list = []

      FileUtils.mkdir_p(PROGRESS_DIR)
      @log_file = File.join(PROGRESS_DIR, "worker_#{@worker_id}.jsonl")
      @failures_file = File.join(PROGRESS_DIR, "worker_#{@worker_id}_failures.txt")

      write_event('worker_start', {
        pid: Process.pid,
        started_at: Time.now.iso8601
      })

      config.on_event :test_case_started, &method(:on_test_case_started)
      config.on_event :test_case_finished, &method(:on_test_case_finished)
      config.on_event :test_run_finished, &method(:on_test_run_finished)
    end

    private

    # @param event [Cucumber::Core::Event] test case started event with location and name
    def on_test_case_started(event)
      test_case = event.test_case
      feature_path = test_case.location.file
      scenario_name = test_case.name
      line = test_case.location.line

      if @current_feature != feature_path
        if @current_feature
          write_event('feature_end', {
            feature: @current_feature,
            duration_s: (Time.now - @feature_start_time).round(2)
          })
        end
        @current_feature = feature_path
        @feature_start_time = Time.now
        @feature_list << feature_path

        write_event('feature_start', {
          feature: feature_path,
          feature_name: extract_feature_name(feature_path),
          feature_index: @feature_list.size
        })
      end

      @current_scenario = scenario_name
      @scenario_start_time = Time.now
      @total_scenarios += 1

      write_event('scenario_start', {
        feature: feature_path,
        scenario: scenario_name,
        line: line,
        scenario_number: @total_scenarios
      })
    end

    # @param event [Cucumber::Core::Event] test case finished event with result status
    def on_test_case_finished(event)
      test_case = event.test_case
      result = event.result
      status = result_status(result)
      duration = (Time.now - @scenario_start_time).round(2)

      @counts[status] += 1

      error_msg = status == :failed ? extract_error(result) : nil

      write_event('scenario_end', {
        feature: test_case.location.file,
        scenario: test_case.name,
        line: test_case.location.line,
        status: status.to_s,
        duration_s: duration,
        error: error_msg,
        counts: @counts.transform_keys(&:to_s),
        total_scenarios: @total_scenarios
      })

      write_failure(test_case, error_msg) if status == :failed
    end

    # @param _event [Cucumber::Core::Event] test run finished event
    def on_test_run_finished(_event)
      if @current_feature
        write_event('feature_end', {
          feature: @current_feature,
          duration_s: (Time.now - @feature_start_time).round(2)
        })
      end

      write_event('worker_end', {
        pid: Process.pid,
        finished_at: Time.now.iso8601,
        total_scenarios: @total_scenarios,
        counts: @counts.transform_keys(&:to_s),
        features_run: @feature_list.size
      })
    end

    # @param result [Cucumber::Core::Test::Result] test result object
    # @return [Symbol] :passed, :failed, :skipped, or :pending
    def result_status(result)
      case result
      when Cucumber::Core::Test::Result::Passed then :passed
      when Cucumber::Core::Test::Result::Failed then :failed
      when Cucumber::Core::Test::Result::Skipped then :skipped
      when Cucumber::Core::Test::Result::Pending then :pending
      when Cucumber::Core::Test::Result::Undefined then :pending
      else :skipped
      end
    end

    # @param result [Cucumber::Core::Test::Result] failed test result
    # @return [String, nil] truncated error message or nil
    def extract_error(result)
      return nil unless result.respond_to?(:exception)

      ex = result.exception
      "#{ex.class}: #{ex.message}"[0..300]
    end

    # @param path [String] path to a .feature file
    # @return [String] feature name from the Feature: line, or filename as fallback
    def extract_feature_name(path)
      File.read(path).each_line do |line|
        if line.strip.start_with?('Feature:')
          return line.strip.sub('Feature:', '').strip
        end
      end
      File.basename(path, '.feature')
    rescue StandardError
      File.basename(path, '.feature')
    end

    # @param type [String] event type (e.g. 'worker_start', 'scenario_end')
    # @param data [Hash] event payload to serialize as JSON
    def write_event(type, data)
      event = {
        type: type,
        worker: @worker_id.to_i,
        timestamp: Time.now.iso8601(3),
        **data
      }
      File.open(@log_file, 'a') { |f| f.puts(JSON.generate(event)) }
    rescue StandardError
      # Never crash the test run because of formatter errors
    end

    # @param test_case [Cucumber::Core::Test::Case] the failed test case
    # @param error_msg [String, nil] error message to include in the rerun file
    def write_failure(test_case, error_msg)
      location = "#{test_case.location.file}:#{test_case.location.line}"
      File.open(@failures_file, 'a') do |f|
        f.puts "#{location} # Scenario: #{test_case.name}"
        f.puts "  #{error_msg}" if error_msg
        f.puts ""
      end
    rescue StandardError
      # Never crash the test run because of formatter errors
    end
  end
end

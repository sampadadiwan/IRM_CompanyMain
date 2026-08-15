# frozen_string_literal: true

require 'yaml'

module IncidentWatch
  # Rules for exceptions that should never open a branch - typically bad data in production
  # rather than a defect in the code.
  #
  # These live in their own file rather than in config/incident_watch.yml because the CLI
  # rewrites them (`ignore --rule`), and round-tripping YAML through Psych would strip every
  # comment out of the main config.
  #
  # A rule is a set of matchers that must ALL hold, plus a reason:
  #
  #   - reason: Legacy investors imported without a country; data fix tracked in OPS-412
  #     exception_class: ActiveRecord::RecordInvalid
  #     location: investors#update
  #     message: Country can't be blank
  #
  # Every matcher is a case-insensitive regular expression matched against the incident, so
  # `location: investors#` covers every action on that controller. Matching on the incident
  # rather than on the fingerprint matters: a fingerprint changes the moment the culprit line
  # moves, and a rule you have to re-add after every refactor is a rule you will stop
  # trusting.
  class IgnoreRules
    # Fields a rule may match on, mapped to how to read them off a parsed incident.
    MATCHERS = {
      'exception_class' => ->(incident) { incident['exception_class'] },
      'location' => ->(incident) { incident['location'] },
      'message' => ->(incident) { incident['message'] },
      'culprit_path' => ->(incident) { incident.dig('culprit', 'path') }
    }.freeze

    def self.load(path, logger: nil)
      raw = File.exist?(path) ? (YAML.safe_load_file(path) || []) : []
      new(raw, path: path, logger: logger)
    end

    def initialize(rules, path: nil, logger: nil)
      @path = path
      @logger = logger
      @rules = Array(rules).select { |rule| valid?(rule) }
    end

    attr_reader :rules, :path

    # The first rule that matches, or nil. Returning the rule rather than a boolean lets the
    # caller record *why* something was ignored, which is the whole point - an unexplained
    # muted incident is indistinguishable from a bug in the matcher.
    def match(incident)
      @rules.find { |rule| matches?(rule, incident) }
    end

    def add(rule)
      @rules << rule
      File.write(@path, <<~HEADER + YAML.dump(@rules).sub(/\A---\n/, ''))
        # Exceptions that must never open a branch - see lib/incident_watch/ignore_rules.rb
        #
        # Every field except `reason` is a case-insensitive regular expression, and all the
        # fields present in a rule must match. Managed by:
        #   bin/incident-watch ignore <fingerprint> --reason "..." --rule
        #   bin/incident-watch ignore --list
      HEADER
      rule
    end

    private

    def matches?(rule, incident)
      MATCHERS.all? do |field, reader|
        pattern = rule[field]
        # A field the rule does not mention is not a constraint.
        next true if pattern.nil? || pattern.to_s.empty?

        value = reader.call(incident).to_s
        Regexp.new(pattern.to_s, Regexp::IGNORECASE).match?(value)
      rescue RegexpError => e
        warn_about("rule #{rule['reason'].inspect} has an invalid #{field} pattern: #{e.message}")
        false
      end
    end

    # A rule with no matchers would silently mute every incident the system ever sees, which
    # is the worst possible failure for this feature. Refuse to load it.
    def valid?(rule)
      unless rule.is_a?(Hash)
        warn_about("ignoring malformed rule (expected a mapping): #{rule.inspect}")
        return false
      end

      if MATCHERS.keys.none? { |field| rule[field].to_s != '' }
        warn_about("ignoring rule with no matchers - it would mute everything: #{rule.inspect}")
        return false
      end

      true
    end

    def warn_about(message)
      @logger ? @logger.call("[ignore] #{message}") : warn("[ignore] #{message}")
    end
  end
end

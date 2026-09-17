# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'time'

module IncidentWatch
  # On-disk record of every incident we have seen, one JSON file per fingerprint.
  #
  # Two layers of deduplication live here, and both matter because a single production bug
  # can generate hundreds of emails in a minute:
  #
  #   1. Message-level - a seen-ids file records every Gmail message id already ingested,
  #      so re-polling the same mailbox never double-counts. This is what lets the IMAP
  #      poller leave the inbox untouched (no \Seen flag, no label) and still be idempotent.
  #   2. Incident-level - emails sharing a fingerprint collapse into one incident, and only
  #      the first transition to "new" dispatches an RCA run.
  class Store
    # Incident lifecycle. Only "new" is eligible for dispatch.
    #
    # "ignored" is a terminal state for exceptions caused by bad data rather than a defect.
    # Ignored incidents are still recorded and still count occurrences - you want to know it
    # is still happening - they are simply never analysed.
    # The pipeline is two-staged and stops in the middle for a human:
    #
    #   new        -> queued, nothing has looked at it yet
    #   dispatched -> stage 1 running: analysing, writing the RCA
    #   analysed   -> RCA committed, WAITING FOR YOU. No code has been changed.
    #   patching   -> stage 2 running: you approved, it is writing the fix
    #   done       -> patch committed and the draft PR is open
    #   failed     -> a stage did not produce what it should have
    #   ignored    -> bad data, not a defect; never analysed
    STATES = %w[new dispatched analysed patching done failed ignored].freeze

    def initialize(root)
      @root = File.expand_path(root)
      @incidents_dir = File.join(@root, 'incidents')
      @seen_path = File.join(@root, 'seen_message_ids.json')
      FileUtils.mkdir_p(@incidents_dir)
    end

    attr_reader :root, :incidents_dir

    # --- message-level dedupe ---------------------------------------------------------

    def seen_message_ids
      @seen_message_ids ||= File.exist?(@seen_path) ? JSON.parse(File.read(@seen_path)) : []
    end

    def seen?(message_id)
      message_id && seen_message_ids.include?(message_id)
    end

    def mark_seen(message_id)
      return if message_id.nil? || seen?(message_id)

      seen_message_ids << message_id
      # Keep the file bounded - we only need enough history to cover the poll window.
      @seen_message_ids = seen_message_ids.last(5000)
      atomic_write(@seen_path, JSON.pretty_generate(@seen_message_ids))
    end

    # --- incident-level dedupe --------------------------------------------------------

    def path_for(fingerprint)
      File.join(@incidents_dir, "#{fingerprint}.json")
    end

    def find(fingerprint)
      path = path_for(fingerprint)
      File.exist?(path) ? JSON.parse(File.read(path)) : nil
    end

    def all
      Dir[File.join(@incidents_dir, '*.json')].filter_map do |path|
        JSON.parse(File.read(path))
      rescue JSON::ParserError
        nil # a half-written file from a killed run should not break `list`
      end
    end

    # Record a parsed email. Returns [incident, :created | :repeated].
    #
    # A repeat bumps the occurrence count and last_seen but deliberately does NOT reset the
    # state - an incident already dispatched or fixed must not re-trigger a second RCA run
    # just because production is still throwing the same error while the fix is unreviewed.
    def record(parsed)
      fingerprint = parsed['fingerprint']
      existing = find(fingerprint)
      now = Time.now.utc.iso8601

      if existing
        existing['occurrences'] = existing['occurrences'].to_i + 1
        existing['last_seen'] = now
        # Keep a bounded sample of source emails for the RCA to cross-reference.
        existing['source_messages'] = ((existing['source_messages'] || []) + [parsed['source']]).last(20)
        write(existing)
        [existing, :repeated]
      else
        incident = parsed.merge(
          'state' => 'new',
          'occurrences' => 1,
          'first_seen' => now,
          'last_seen' => now,
          'source_messages' => [parsed['source']].compact
        )
        write(incident)
        [incident, :created]
      end
    end

    # Move an incident through its lifecycle, merging in whatever the caller learned
    # (branch name, RCA path, failure reason).
    def update_state(fingerprint, state, extra = {})
      raise ArgumentError, "unknown state #{state}" unless STATES.include?(state)

      incident = find(fingerprint) or raise ArgumentError, "no incident #{fingerprint}"
      incident['state'] = state
      incident['state_changed_at'] = Time.now.utc.iso8601
      incident.merge!(extra)
      write(incident)
      incident
    end

    def write(incident)
      atomic_write(path_for(incident['fingerprint']), JSON.pretty_generate(incident))
      incident
    end

    private

    # Write via a temp file + rename so a crashed or concurrent run can never leave a
    # truncated JSON file behind for the next poll to choke on.
    def atomic_write(path, contents)
      tmp = "#{path}.tmp#{Process.pid}"
      File.write(tmp, contents)
      FileUtils.mv(tmp, path)
    end
  end
end

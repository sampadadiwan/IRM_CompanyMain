# frozen_string_literal: true

require 'json'

module IncidentWatch
  # Reads back what a headless RCA run actually did.
  #
  # There are three separate logs, and they answer different questions:
  #
  #   1. log/incident_watch.log        - the dispatcher's own lines (cron output). Which
  #                                      incident, which worktree, which command, what
  #                                      outcome. Start here.
  #   2. tmp/incident_watch/logs/<fp>.log - stdout+stderr of the `claude -p` process, teed
  #                                      as it ran. Mostly the final JSON envelope.
  #   3. ~/.claude/projects/<worktree>/*.jsonl - Claude Code's own turn-by-turn transcript:
  #                                      every thought, tool call and tool result. This is
  #                                      the one you want when asking "what is it doing
  #                                      right now" or "why did it make that change".
  #
  # This class renders (3), because raw JSONL is unreadable and it is the only log that
  # exists while a run is still in flight.
  class RunLog
    def initialize(repo_root, store)
      @repo_root = repo_root
      @store = store
    end

    # Claude Code namespaces transcripts by working directory, with the path flattened:
    # every separator becomes a dash. The RCA runs in the worktree, so that is the key.
    def transcript_path(fingerprint)
      worktree = File.join(@repo_root, '.claude', 'worktrees', "incident-#{fingerprint}")
      slug = worktree.gsub(%r{[/.]}, '-')
      dir = File.join(Dir.home, '.claude', 'projects', slug)
      return nil unless File.directory?(dir)

      # Newest session wins - a re-run of the same incident starts a fresh transcript.
      Dir[File.join(dir, '*.jsonl')].max_by { |f| File.mtime(f) }
    end

    def run_log_path(fingerprint)
      path = File.join(@store.root, 'logs', "#{fingerprint}.log")
      File.exist?(path) ? path : nil
    end

    # Turn the JSONL transcript into readable lines. Returns an array of strings.
    #
    # `thinking` blocks are skipped by default: they are the bulk of the bytes and are
    # reasoning, not actions. Pass show_thinking to include them when you are trying to
    # understand *why* a run reached a conclusion.
    def render_transcript(fingerprint, show_thinking: false, tail: nil)
      path = transcript_path(fingerprint)
      return ["no transcript found for #{fingerprint}"] unless path

      lines = []
      File.foreach(path) do |raw|
        entry = begin
          JSON.parse(raw)
        rescue JSON::ParserError
          next
        end

        content = entry.dig('message', 'content')
        next unless content.is_a?(Array)

        content.each do |block|
          next unless block.is_a?(Hash)

          case block['type']
          when 'text'
            text = block['text'].to_s.strip
            lines << "\n#{text}" unless text.empty?
          when 'thinking'
            next unless show_thinking

            lines << "\n[thinking] #{truncate(block['thinking'], 2000)}"
          when 'tool_use'
            lines << "  -> #{block['name']} #{describe_tool_input(block['name'], block['input'])}"
          when 'tool_result'
            lines << "     #{truncate(flatten_result(block['content']), 220)}"
          end
        end
      end

      lines = lines.last(tail) if tail
      lines
    end

    private

    # Show the part of each tool call that identifies what it touched, rather than dumping
    # whole file contents into the log.
    def describe_tool_input(name, input)
      return '' unless input.is_a?(Hash)

      case name
      when 'Bash' then input['command'].to_s.lines.first.to_s.strip
      when 'Read', 'Write' then input['file_path'].to_s.sub("#{@repo_root}/", '')
      when 'Edit' then "#{input['file_path'].to_s.sub("#{@repo_root}/", '')} " \
                       "(#{truncate(input['old_string'].to_s.lines.first.to_s.strip, 60)})"
      when 'Grep', 'Glob' then "#{input['pattern']} #{input['path']}".strip
      else truncate(input.to_json, 140)
      end
    end

    def flatten_result(content)
      case content
      when String then content
      when Array
        content.filter_map { |c| c.is_a?(Hash) ? c['text'] : c.to_s }.join(' ')
      else content.to_s
      end
    end

    def truncate(value, max)
      str = value.to_s.gsub(/\s+/, ' ').strip
      str.length > max ? "#{str[0, max]}..." : str
    end
  end
end

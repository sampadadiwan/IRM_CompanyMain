# frozen_string_literal: true

require 'digest'
require 'time'

module IncidentWatch
  # Turns the plain-text body of an ExceptionNotifier email into a structured incident Hash.
  #
  # exception_notification 5.0.1 renders one of two text templates:
  #
  #   * exception_notification.text.erb            - web requests, via the Rack middleware
  #     configured in config/application.rb
  #   * background_exception_notification.text.erb - background jobs, via the Sidekiq
  #     error handler in config/initializers/exception_notification.rb
  #
  # Both share the same shape: a headline, an indented block holding the exception message
  # and the top backtrace frame, then a run of sections separated by a 31-dash rule that
  # comes from the gem's _title.text.erb partial:
  #
  #   -------------------------------
  #   Request:
  #   -------------------------------
  #
  #     * URL        : https://app.example.com/funds/12
  #
  # Everything here is pure string work against stdlib only, so the poller can run from
  # cron without booting Rails.
  class Parser
    # The gem's _title.text.erb draws exactly 31 dashes above and below each section name.
    SECTION_RULE = /^-{31}[ \t]*\r?\n[ \t]*(.+?):[ \t]*\r?\n-{31}[ \t]*\r?\n/

    # "A NoMethodError occurred in funds#show:" - the web-request headline. The controller
    # name is blank when the exception escaped before a controller was resolved, because the
    # gem substitutes its MissingController null object.
    WEB_HEADLINE = %r{\AAn? ([A-Za-z0-9_:]+) occurred in ([\w/]*)#(\w*):}

    # "A NoMethodError occurred in background at 2026-08-15 09:14:22 UTC :"
    # The trailing $ matters: the timestamp itself contains colons, so without anchoring to
    # end-of-line the lazy capture would stop at "2026-08-15 03".
    BACKGROUND_HEADLINE = /\AAn? ([A-Za-z0-9_:]+) occurred in background at (.+?)\s*:\s*$/

    # A backtrace frame, in either the Ruby <= 3.3 form ("...:in `method'") or the
    # Ruby >= 3.4 form ("...:in 'Class#method'"). The path may be repo-relative (Rails'
    # backtrace cleaner strips Rails.root) or absolute (gem and stdlib frames).
    FRAME = /^\s*(?<path>[^\s:][^:]*?):(?<line>\d+):in\s+[`'](?<method>.*?)'?\s*$/

    # Frames we consider "ours" - these are what an RCA should point at. Rails' cleaner
    # leaves application frames repo-relative, so a leading app/ or lib/ is the signal.
    APP_FRAME = %r{^(app|lib|config|db)/}

    # The Environment section is huge (every Rack env key). We keep only the handful that
    # help an RCA and drop the rest, so incident files stay small and free of noise.
    ENV_KEYS_OF_INTEREST = %w[
      HTTP_HOST HTTP_REFERER HTTP_USER_AGENT REQUEST_METHOD REQUEST_URI PATH_INFO
      QUERY_STRING REMOTE_ADDR SERVER_NAME rack.url_scheme action_dispatch.request_id
    ].freeze

    def self.parse(body, meta = {})
      new(body, meta).parse
    end

    def initialize(body, meta = {})
      # Normalise line endings first - Gmail hands back CRLF, and every regex below
      # assumes \n so that section splitting stays predictable.
      @body = body.to_s.gsub(/\r\n?/, "\n")
      @meta = meta
    end

    def parse
      incident = {
        # Provenance: which email this came from, so we never re-process it.
        'source' => {
          'message_id' => @meta[:message_id],
          'subject' => @meta[:subject],
          'from' => @meta[:from],
          'received_at' => @meta[:date]
        }.compact
      }

      incident.merge!(parse_headline)
      incident['sections'] = sections
      incident['backtrace'] = backtrace
      incident['app_backtrace'] = incident['backtrace'].select { |f| f['path'].match?(APP_FRAME) }
      incident['culprit'] = incident['app_backtrace'].first || incident['backtrace'].first
      incident['request'] = parse_request
      incident['job'] = parse_job
      incident['environment'] = parse_environment
      incident['fingerprint'] = fingerprint(incident)
      incident['raw_body'] = @body
      incident
    end

    private

    # --- headline -------------------------------------------------------------------

    # The first paragraph carries the exception class, where it happened, the message and
    # the top frame. The message can span several lines (ActiveRecord::StatementInvalid
    # embeds the failing SQL, for example), so we do not assume "second line is the frame":
    # instead we take the last frame-shaped line in the block and treat the rest as message.
    def parse_headline
      # split() on a pattern with a capture group interleaves the captures into the result,
      # so no limit here - the first element is always the text before the first rule.
      header = @body.split(SECTION_RULE).first.to_s.strip
      result = { 'kind' => nil, 'exception_class' => nil, 'message' => nil }

      if (m = header.match(WEB_HEADLINE))
        result['kind'] = 'web'
        result['exception_class'] = m[1]
        # Blank controller/action means the gem's MissingController stood in for a real one.
        result['controller'] = m[2].empty? ? nil : m[2]
        result['action'] = m[3].empty? ? nil : m[3]
        location = [result['controller'], result['action']].compact.join('#')
        result['location'] = location.empty? ? nil : location
      elsif (m = header.match(BACKGROUND_HEADLINE))
        result['kind'] = 'background'
        result['exception_class'] = m[1]
        result['occurred_at'] = m[2]
        result['location'] = 'background'
      end

      # Drop the headline line itself, then split what remains into message vs top frame.
      body_lines = header.split("\n")[1..] || []
      last_frame_index = body_lines.rindex { |line| line.match?(FRAME) }
      # Dedent every line, not just the block: the template indents each message line by
      # two spaces, and a multi-line message (embedded SQL, for instance) would otherwise
      # keep that indentation on every line but the first.
      if last_frame_index
        result['message'] = dedent(body_lines[0...last_frame_index])
        result['top_frame'] = body_lines[last_frame_index].strip
      else
        result['message'] = dedent(body_lines)
      end

      result
    end

    def dedent(lines)
      lines.map(&:strip).reject(&:empty?).join("\n")
    end

    # --- sections -------------------------------------------------------------------

    # Split the body on the dash rules into { "Request" => "...", "Backtrace" => "..." }.
    # String#split with a capturing group interleaves the captured titles with the text
    # that follows them, so we walk the array in pairs.
    def sections
      return @sections if defined?(@sections)

      parts = @body.split(SECTION_RULE)
      parts.shift # everything before the first rule is the headline block, already parsed
      @sections = {}
      parts.each_slice(2) do |title, content|
        next if title.nil?

        @sections[title.strip] = content.to_s.strip
      end
      @sections
    end

    # --- backtrace ------------------------------------------------------------------

    def backtrace
      raw = sections['Backtrace'].to_s
      raw.split("\n").filter_map do |line|
        next unless (m = line.match(FRAME))

        { 'path' => m[:path].strip, 'line' => m[:line].to_i, 'method' => m[:method], 'raw' => line.strip }
      end
    end

    # --- request / job / environment ------------------------------------------------

    # The Request section is a list of "* Key : value" lines from _request.text.erb.
    def parse_request
      return nil unless sections.key?('Request')

      bullets(sections['Request']).transform_keys { |k| k.downcase.gsub(/[^a-z0-9]+/, '_') }
    end

    # The Data section only exists for background jobs. Our Sidekiq handler passes the
    # Sidekiq context hash (job_class, args, jid, queue), pretty-printed by PP.
    def parse_job
      return nil unless sections.key?('Data')

      raw = sections['Data'].sub(/\A\*\s*data:\s*/, '').strip
      {
        'raw' => raw,
        # Pull the job class out of the pretty-printed hash for a readable label; the full
        # payload stays in "raw" for the RCA to read.
        'job_class' => raw[/"?(?:job_)?class"?\s*(?:=>|:)\s*"?([A-Za-z0-9_:]+)"?/, 1],
        'jid' => raw[/"?jid"?\s*(?:=>|:)\s*"([a-f0-9]+)"/, 1],
        'queue' => raw[/"?queue"?\s*(?:=>|:)\s*"([^"]+)"/, 1]
      }.compact
    end

    def parse_environment
      return nil unless sections.key?('Environment')

      all = bullets(sections['Environment'])
      all.slice(*ENV_KEYS_OF_INTEREST)
    end

    # Parse "* Key : value" bullet lists. Keys are padded with spaces in _request.text.erb
    # and _environment.text.erb, so both sides get squeezed. The value group is optional so
    # that empty entries (QUERY_STRING on a URL with no query) are captured as "" rather
    # than silently dropped.
    def bullets(text)
      text.split("\n").each_with_object({}) do |line, acc|
        next unless (m = line.match(/^\s*\*\s*(.+?)\s*:(?:[ \t](.*))?$/))

        acc[m[1].strip] = m[2].to_s.strip
      end
    end

    # --- fingerprint ----------------------------------------------------------------

    # Group repeat occurrences of the same bug into one incident. Two emails belong
    # together when they share an exception class, a normalised message and a culprit
    # frame. Normalising strips the parts that vary per request - record ids, uuids,
    # timestamps, memory addresses - so "Couldn't find Fund with 'id'=123" and the same
    # error for id=456 do not open two branches.
    def fingerprint(incident)
      culprit = incident['culprit']
      key = [
        incident['exception_class'],
        normalize_message(incident['message']),
        culprit && "#{culprit['path']}:#{culprit['line']}"
      ].compact.join('|')
      Digest::SHA1.hexdigest(key)[0, 8]
    end

    def normalize_message(message)
      message.to_s
             .gsub(/0x[0-9a-f]+/i, '0xADDR')                      # object addresses
             .gsub(/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i, 'UUID')
             .gsub(/\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}\S*/, 'TIMESTAMP')
             .gsub(/\d+/, 'N')                                    # record ids, counts, ports
             .strip
    end
  end
end

# frozen_string_literal: true

require 'net/imap'
require 'time'

module IncidentWatch
  # Fetches ExceptionNotifier emails straight from Gmail over IMAP.
  #
  # This is the unattended path. The Gmail MCP connector is the nicer interface, but it is
  # authenticated interactively inside Claude Code and is not reliably present in a cron
  # or headless run - IMAP with an app password always is. Both sources emit the same
  # shape, so Parser and Store do not care which one produced a message.
  #
  # Non-destructive by default: the mailbox is opened with EXAMINE (read-only), so nothing
  # is marked \Seen and no message moves. Turn on mark_seen/apply_label in
  # config/incident_watch.yml if you would rather have the mail flagged.
  class ImapSource
    Message = Struct.new(:message_id, :subject, :from, :date, :body, keyword_init: true)

    def initialize(config, logger: nil)
      @config = config
      @logger = logger
      @host = ENV.fetch('INCIDENT_WATCH_IMAP_HOST', 'imap.gmail.com')
      @port = ENV.fetch('INCIDENT_WATCH_IMAP_PORT', '993').to_i
      @user = ENV.fetch('INCIDENT_WATCH_IMAP_USER', nil)
      @password = ENV.fetch('INCIDENT_WATCH_IMAP_PASSWORD', nil)
    end

    def available?
      !@user.to_s.empty? && !@password.to_s.empty?
    end

    # Yields a Message for every alert email in the lookback window.
    #
    # Bodies are fetched in two passes on purpose. The sender filter is all IMAP can do
    # server-side, and in a real inbox it matches far more than the exception alerts -
    # monitoring, cron reports, backup notices all come from the same address. Downloading
    # every one of those bodies to throw most of them away is pure waste on a timer, so we
    # pull cheap envelopes first, apply the caller's subject filter, and only then fetch the
    # bodies of the survivors.
    #
    # `accept` receives (subject, from) and returns whether the body is worth fetching.
    def each_message(accept: nil)
      raise Error, credentials_hint unless available?

      # The mail gem ships with Rails and handles MIME/quoted-printable decoding, which we
      # need because Gmail hands back the raw RFC822 source. Required lazily so that
      # `parse`/`list`/`selftest` keep working without bundler.
      require 'mail'

      imap = Net::IMAP.new(@host, port: @port, ssl: true)
      begin
        imap.login(@user, @password)
        # EXAMINE, not SELECT: read-only, so fetching a body cannot set the \Seen flag.
        writable = @config['mark_seen'] || @config['apply_label']
        writable ? imap.select(@config['mailbox']) : imap.examine(@config['mailbox'])

        ids = imap.search(search_criteria)
        log "IMAP search matched #{ids.size} message(s) in the last #{@config['lookback_days']} day(s)"

        # Pass 1 - envelopes only, to decide what is worth downloading.
        wanted = ids
        if accept
          wanted = []
          ids.each_slice(200) do |slice|
            imap.fetch(slice, %w[ENVELOPE]).to_a.each do |item|
              envelope = item.attr['ENVELOPE']
              from = envelope.from&.first
              subject = ::Mail::Encodings.value_decode(envelope.subject.to_s)
              address = from && "#{from.mailbox}@#{from.host}"
              wanted << item.seqno if accept.call(subject, address)
            end
          end
          log "#{wanted.size} of #{ids.size} match the subject filter; fetching those bodies only"
        end

        # Pass 2 - bodies, in slices. An exception storm can match thousands of ids, and
        # asking for every RFC822 body in one command is a good way to get the connection
        # killed.
        wanted.each_slice(25) do |slice|
          imap.fetch(slice, 'RFC822').to_a.each do |item|
            mail = ::Mail.read_from_string(item.attr['RFC822'])
            yield build_message(mail)
          end
        end

        apply_mailbox_side_effects(imap, wanted) if writable
      ensure
        # Best-effort teardown; a dropped connection must not mask the real error.
        begin
          imap.logout
        rescue StandardError
          nil
        end
        begin
          imap.disconnect
        rescue StandardError
          nil
        end
      end
    end

    # Connect, authenticate, and run the real search - but fetch only envelopes, not bodies.
    # This is what `bin/incident-watch check` uses to prove the credentials, the mailbox and
    # the sender filter all work before anything gets scheduled. Returns the match count and
    # a small sample of recent headers so the caller can show what the filters would do.
    def probe
      raise Error, credentials_hint unless available?

      require 'mail'
      imap = Net::IMAP.new(@host, port: @port, ssl: true)
      begin
        imap.login(@user, @password)
        imap.examine(@config['mailbox'])
        ids = imap.search(search_criteria)

        # Fetch envelopes for EVERY match, not just the newest few. Headers are small, and
        # the question the caller is actually asking - "does the subject filter match my
        # real alerts?" - cannot be answered from a sample: a quiet week of exception
        # emails is easily buried under hundreds of monitoring alerts from the same sender.
        headers = []
        ids.each_slice(200) do |slice|
          imap.fetch(slice, %w[ENVELOPE INTERNALDATE]).to_a.each do |item|
            envelope = item.attr['ENVELOPE']
            from = envelope.from&.first
            headers << {
              # Subjects arrive MIME-encoded ("=?UTF-8?B?...?="); decode so the caller can
              # match them against the same pattern the poller uses.
              subject: ::Mail::Encodings.value_decode(envelope.subject.to_s),
              from: from && "#{from.mailbox}@#{from.host}",
              date: item.attr['INTERNALDATE'].to_s
            }
          end
        end

        { matched: ids.size, headers: headers.reverse }
      ensure
        begin
          imap.logout
        rescue StandardError
          nil
        end
        begin
          imap.disconnect
        rescue StandardError
          nil
        end
      end
    end

    private

    # Server-side narrowing. We push down what Gmail handles predictably - a date window and
    # the sender allowlist. Subject matching stays in Ruby, because Gmail tokenises IMAP
    # SUBJECT searches and drops punctuation such as the "[ERROR]" brackets.
    def search_criteria
      since = (Time.now.getlocal - (@config['lookback_days'].to_i * 86_400)).strftime('%d-%b-%Y')
      ['SINCE', since] + sender_criteria
    end

    # IMAP SEARCH uses prefix notation and its OR takes exactly two operands, so a list of
    # senders becomes a right-nested chain:
    #   [a]       -> FROM a
    #   [a, b]    -> OR FROM a FROM b
    #   [a, b, c] -> OR FROM a OR FROM b FROM c
    def sender_criteria
      senders = Array(@config['from']).map { |s| s.to_s.strip }.reject(&:empty?)
      return [] if senders.empty?

      senders.reverse.reduce([]) do |acc, sender|
        acc.empty? ? ['FROM', sender] : ['OR', 'FROM', sender] + acc
      end
    end

    def build_message(mail)
      Message.new(
        message_id: mail.message_id,
        subject: mail.subject.to_s,
        from: Array(mail.from).first,
        date: mail.date&.iso8601,
        body: extract_text_body(mail)
      )
    end

    # The notifier is configured with the gem's default email_format: :text, so these are
    # single-part text/plain mails. The multipart branch is a guard in case someone flips
    # that to :html later - we still want the text alternative, never the HTML.
    def extract_text_body(mail)
      part = mail.multipart? ? (mail.text_part || mail.parts.first) : mail
      body = part&.decoded.to_s
      # Force a clean UTF-8 string: production backtraces occasionally carry bytes that
      # are invalid in the declared charset, and a bad byte would blow up every regex.
      body.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
    end

    def apply_mailbox_side_effects(imap, ids)
      return if ids.empty?

      if @config['apply_label']
        # Gmail exposes labels as IMAP folders; COPY adds the label without moving the mail.
        label = @config['label']
        imap.copy(ids, label)
        log "labelled #{ids.size} message(s) as #{label}"
      end

      return unless @config['mark_seen']

      imap.store(ids, '+FLAGS', [:Seen])
      log "marked #{ids.size} message(s) as read"
    end

    def credentials_hint
      <<~MSG
        IMAP credentials are not set. Export these, then re-run:

          export INCIDENT_WATCH_IMAP_USER='you@gmail.com'
          export INCIDENT_WATCH_IMAP_PASSWORD='<16-char Google app password>'

        Create the app password at https://myaccount.google.com/apppasswords
        (requires 2-Step Verification). Your normal Google password will not work.

        Alternatively use the Gmail MCP path, which needs no app password:
        see docs/technical/incident_rca_system.md
      MSG
    end

    def log(message)
      @logger&.call("[imap] #{message}")
    end
  end

  class Error < StandardError; end
end

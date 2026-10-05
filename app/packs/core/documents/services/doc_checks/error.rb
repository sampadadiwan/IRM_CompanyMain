# Errors raised by Document Checks. Nested so one file holds them all (Zeitwerk loads DocChecks::Error,
# which defines the subclasses with it).
module DocChecks
  class Error < StandardError
    # A record type with no registry entry
    class UnknownRecordType < Error; end

    # A non-trial check is already queued or running for the record
    class AlreadyRunning < Error; end

    # The AI provider failed (connection, timeout, rate limit, auth): the run could not run. The message
    # is safe to show to users.
    class ProviderError < Error; end

    # A value read from a document can't be stored in its field (e.g. an unparseable date)
    class BadValue < Error; end
  end
end

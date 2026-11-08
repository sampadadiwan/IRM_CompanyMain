# frozen_string_literal: true

module Dr
  # Verdicts for the "does it work for a USER" checks at the end of a recovery (2026-11-08):
  # the earlier checks proved each part is up; these prove what a user would actually do works.
  #
  #   1. Through the load balancer: certificate valid for the app host, targets healthy, a
  #      request reaches the app and the database (aws_utils #dr_edge_checks, operator side).
  #   2. Document files: the restored database's documents still have their files in S3.
  #   3. Background jobs run: a job queued now is picked up and finished.
  #   4. Users can sign in: the sign-in page renders, and a signed-in API read answers.
  #   5. PDFs can be made: LibreOffice converts a Word file, the way document generation does.
  #
  # Pure: callers gather the facts (HTTP codes, counts, files), these decide pass/warn/fail.
  module ServingChecks
    # Missing files up to this share of the sample are a warning (the newest uploads may still be
    # replicating in a real recovery from the replica bucket); above it, documents are broken.
    DOCUMENT_MISSING_WARN_RATIO = 0.10
    # A queued job should run within this; Sidekiq polls every few seconds
    JOB_TIMEOUT_SECONDS = 90
    # Text only the sign-in page carries: the form posts user[password]
    SIGN_IN_MARKER = "user[password]"
    # A PDF file starts with these bytes
    PDF_MAGIC = "%PDF"

    module_function

    def grade
      BackupSchedule::Grade
    end

    # 2. checked: how many documents' files were looked up; missing_ids: those not found
    def grade_documents(checked:, missing_ids:)
      return grade.new(:warn, "no stored documents to check") if checked.zero?

      missing = Array(missing_ids)
      return grade.new(:ok, "#{checked} of #{checked} files found in S3 (newest and older documents)") if missing.empty?

      detail = "#{missing.size} of #{checked} files missing in S3 (document ids #{missing.first(10).join(', ')})"
      return grade.new(:fail, "#{detail} — documents will not open") if missing.size > checked * DOCUMENT_MISSING_WARN_RATIO

      grade.new(:warn, "#{detail} — recent uploads may still be replicating; re-check in a few minutes")
    end

    # 3. seconds: how long the job took to run, or nil if it never ran within the timeout
    def grade_job(seconds:, queue:)
      return grade.new(:fail, "a job queued on '#{queue}' did not run within #{JOB_TIMEOUT_SECONDS}s — emails, documents and reports would not be processed") if seconds.nil?

      grade.new(:ok, "a job queued on '#{queue}' ran in #{seconds.round(1)}s")
    end

    # 4a. The sign-in page through nginx → puma: 200 and the real form
    def grade_sign_in(code:, body:)
      return grade.new(:fail, "HTTP #{code} — the sign-in page does not load") unless code.to_s == "200"
      return grade.new(:fail, "HTTP 200 but no sign-in form — an error or maintenance page?") unless body.to_s.include?(SIGN_IN_MARKER)

      grade.new(:ok, "HTTP 200 with the sign-in form")
    end

    # 4b. A signed-in API read with a short-lived token (drill copies only: it writes a token)
    def grade_api_read(code:, body:, path:)
      return grade.new(:fail, "GET #{path} with a token answered HTTP #{code} — signed-in requests fail") unless code.to_s == "200"

      JSON.parse(body.to_s)
      grade.new(:ok, "GET #{path} as a signed-in user: HTTP 200 with JSON")
    rescue JSON::ParserError
      grade.new(:fail, "GET #{path} answered 200 but not JSON — sessions or rendering are broken")
    end

    # 5. The converted file's first bytes (nil when no file was produced)
    def grade_pdf(head:, seconds:, error: nil)
      return grade.new(:fail, "LibreOffice could not convert a Word file: #{error}") if error
      return grade.new(:fail, "LibreOffice produced no PDF — document generation would fail") if head.nil?
      return grade.new(:fail, "the output is not a PDF (starts with #{head[0, 8].inspect})") unless head.start_with?(PDF_MAGIC)

      grade.new(:ok, "a Word file converted to PDF in #{seconds.round(1)}s")
    end

    # 1a. curl's exit code for an HTTPS request to the app host pinned to the load balancer.
    # 51 / 60: the certificate does not match the host or is not trusted.
    def grade_certificate(curl_exit:, host:)
      return grade.new(:ok, "certificate valid for #{host}") if curl_exit.zero?
      return grade.new(:fail, "certificate not valid for #{host} (curl exit #{curl_exit}) — browsers would refuse the site") if [51, 60].include?(curl_exit)

      grade.new(:fail, "could not connect over HTTPS (curl exit #{curl_exit})")
    end

    # 1b. Load balancer target health: every app server must be healthy
    def grade_targets(healthy:, total:)
      return grade.new(:fail, "no app servers registered with the load balancer") if total.zero?
      return grade.new(:ok, "#{healthy} of #{total} app servers healthy") if healthy == total

      grade.new(:fail, "#{healthy} of #{total} app servers healthy — the load balancer sends users only to the healthy ones")
    end

    # 1c / 1d. An HTTP answer through the load balancer
    def grade_edge_http(code:, what:, body: nil, marker: nil)
      return grade.new(:fail, "HTTP #{code} — #{what} does not work through the load balancer") unless code.to_s == "200"
      return grade.new(:fail, "HTTP 200 but not the expected page — #{what}") if marker && body.to_s.exclude?(marker)

      grade.new(:ok, "HTTP 200 — #{what}")
    end

    # Documents to check: the newest few and a spread across older ids, so both "recent uploads
    # replicated" and "old files survive" are covered. Returns target ids to look up at or below.
    def spread_ids(max_id, count: 10)
      return [] if max_id.to_i <= 0

      (1..count).map { |i| (max_id * i / (count + 1.0)).floor }.uniq.select(&:positive?)
    end
  end
end

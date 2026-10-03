# Checks one record's documents for a queued DocCheckRun: reads each document on the record's own list
# (one AI call per document), judges every check, then — in one transaction — stores the results, writes
# the filled-in fields and makes the run current. A provider failure stops the run without storing
# anything, so the earlier results stay current. The only writer of results, and of fields during a run.
#
# Returns the error messages the bulk action collects (empty when the run finished).
# See openspec/changes/document-checks/design.md (card ④ Run). Worked examples H3, E6, E12, E14, E15, X1–X3.
module DocChecks
  class RunJob < ApplicationJob
    queue_as :default
    # Retrying would repeat the AI calls (and their cost); the user has Check again
    sidekiq_options retry: 0

    def perform(run_id)
      @run = DocCheckRun.find_by(id: run_id)
      # Another worker took it, or it was expired: nothing to do (a re-delivered job is harmless)
      return [] unless @run&.queued?

      @record = @run.record
      @entry = Registry.for(@record)
      Chewy.strategy(:sidekiq) { check_documents }
    rescue Error::ProviderError => e
      # The AI service failed: the run couldn't run, nothing changed. Worked example X3.
      could_not_run!(e.message)
    rescue StandardError => e
      # Anything else: never leave the run "running"; tell the user, then let the error tracker see it. A run
      # already stored as done (the failure came after commit, e.g. a toast or journey hook) keeps its results
      # current — marking it "couldn't run" would leave the record with no current run at all.
      could_not_run!(I18n.t("doc_checks.run.went_wrong")) if @run && !@run.reload.done?
      raise e
    end

    private

    def check_documents
      checks = DocCheck.for_record(@record).includes(:entity).to_a
      return could_not_run!(I18n.t("doc_checks.run.no_checks", record_label: @entry.record_label)) if checks.empty?

      groups = documents_in_list_order(checks)
      @run.update!(status: "running", started_at: Time.current, documents_total: groups.size)
      notify(I18n.t("doc_checks.run.started", record: @record.to_s), "info") unless @run.trial
      broadcast

      @writes = []
      results = groups.each_with_index.flat_map do |(name, document_checks), index|
        progress!(name, index)
        read_document(name, document_checks)
      end
      finish!(results)
    end

    # The record's own document names, in its list's order, each with its checks
    def documents_in_list_order(checks)
      by_name = checks.group_by { |check| check.document_name.downcase }
      @entry.document_names_for(@record).filter_map do |name|
        list = by_name[name.downcase]
        [name, list] if list
      end
    end

    # One document's results. A problem with this document becomes its results; other documents still run.
    def read_document(name, checks)
      document = @entry.find_document(@record, name)
      # Worked example E12: on the list, not uploaded
      return checks.map { |check| snapshot(check, outcome: "not_uploaded") } unless document

      read = DocumentReader.call(document:, checks:)
      unless read.success?
        # No AI client at all is the run's problem, not this document's
        raise Error::ProviderError, "the AI service is not configured" if read[:failure] == :no_llm

        # Worked examples X1 (unreadable file), X2 (unreadable reply)
        return checks.map { |check| snapshot(check, outcome: read[:failure].to_s, document:) }
      end

      checks.map { |check| judge(check, read[:readings][check.reply_key], document) }
    end

    def judge(check, reading, document)
      verdict = Judge.call(check:, reading:, record: @record, entry: @entry)
      row = snapshot(check, document:, **verdict.except(:write))
      if verdict[:write]
        field, value = verdict[:write]
        # Applied in memory now, so a later check on the same field sees it; saved in finish!, where the
        # row is adjusted if someone filled the field meanwhile
        @entry.write(@record, field, value)
        @writes << { field:, value:, check:, row: }
      end
      row
    end

    # A result row's attributes, with a snapshot of the check so history renders after the check changes
    def snapshot(check, outcome:, document: nil, note: nil, doc_value: nil, record_value: nil, explanation: nil)
      # Every row carries the same keys (insert_all requires it); a carried-over Mark as OK fills the last four
      { entity_id: @record.entity_id, doc_check_id: check.id, document_name: check.document_name, look_for: check.look_for,
        action: check.action, field_name: check.field_name, document_id: document&.id,
        document_file_id: document&.file&.id, outcome:, note:, doc_value:, record_value:, explanation:,
        resolution: nil, resolved_by_id: nil, resolved_at: nil, resolve_reason: nil }
    end

    def progress!(name, index)
      @run.update_columns(current_document: name, documents_done: index, updated_at: Time.current)
      broadcast
    end

    # Store everything at once. Worked example H3; trials store results but change nothing (H4).
    def finish!(results)
      carry_over_resolutions(results)
      wrote = false
      ActiveRecord::Base.transaction do
        unless @run.trial
          # Fresh row under lock (another run, or a user's edit, may have saved meanwhile), then re-apply
          @record = @record.class.lock.find(@record.id)
          @writes.each { |write| apply_write(write) }
          wrote = @entry.save_details!(@record)
          DocCheckRun.for_record(@record).where(current: true).where.not(id: @run.id).update_all(current: false)
        end
        now = Time.current
        DocCheckResult.insert_all(results.map { |r| r.merge(doc_check_run_id: @run.id, created_at: now, updated_at: now) }) if results.any?
        @run.update!(status: "done", current: !@run.trial, finished_at: now, documents_done: @run.documents_total,
                     current_document: nil, counts: counts(results))
      end
      after_finish(wrote)
      []
    end

    # The "only if empty" rule is decided again on the locked row: a value a person saved while the run was
    # reading documents is kept, and the result says so, exactly as if it had been there from the start
    def apply_write(write)
      current = @entry.read(@record, write[:field])
      if current.present? && !write[:check].replace_existing
        write[:row].merge!(note: "kept", record_value: current.is_a?(Date) ? current.iso8601 : current.to_s)
        return
      end

      @entry.write(@record, write[:field], write[:value])
    end

    # A Mark as OK survives a re-check only if the item reads exactly as when it was marked (row 11 of the
    # design's walkthrough). Use document value needs no carry-over: the values now match.
    def carry_over_resolutions(results)
      previous = DocCheckRun.real.for_record(@record).find_by(current: true)
      return unless previous

      marked = previous.doc_check_results.where(resolution: "marked_ok").index_by(&:doc_check_id)
      results.each do |row|
        old = marked[row[:doc_check_id]]
        next unless old && old.outcome == row[:outcome] && old.doc_value == row[:doc_value] && old.record_value == row[:record_value]

        row.merge!(resolution: "marked_ok", resolved_by_id: old.resolved_by_id, resolved_at: old.resolved_at,
                   resolve_reason: old.resolve_reason)
      end
    end

    def counts(results)
      attention = results.count { |r| r[:outcome] != "ok" && r[:resolution].blank? }
      { "ok" => results.size - attention, "attention" => attention }
    end

    def after_finish(wrote)
      unless @run.trial
        @entry.details_changed!(@record, user: @run.user) if wrote
        @entry.on_assessed(@record, Assessment.new(@record).settled?)
        @record.journey_progress! if @record.respond_to?(:journey_progress!)
        attention = @run.attention_count
        if attention.zero?
          notify(I18n.t("doc_checks.run.all_ok", record: @record.to_s), "success")
        else
          notify(I18n.t("doc_checks.run.need_attention", record: @record.to_s, count: attention), "warning")
        end
      end
      broadcast
    end

    def could_not_run!(reason)
      @run.update!(status: "could_not_run", error_message: reason.to_s.truncate(255), finished_at: Time.current,
                   current: false, current_document: nil)
      notify(I18n.t("doc_checks.run.could_not_run", record: @record.to_s, reason:), "danger") unless @run.trial
      broadcast
      [{ msg: reason, id: @run.record_id }]
    end

    def notify(message, level)
      send_notification(message, @run.user_id, level)
    end

    # Refresh the open tab (or the trial frame) for this record
    def broadcast
      DocChecks::Broadcast.run(@run)
    end
  end
end

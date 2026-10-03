# Everything the KYC tab, the attention list and the journey need to know about a record's Document Checks,
# worked out from its current run and the documents on file now. Read-only.
#
#   a = DocChecks::Assessment.new(kyc)
#   a.groups           # one Group per document of the record's own list that the current run read
#   a.attention_count  # items needing attention, counting every item of a changed document
#   a.settled?         # checked, and nothing needs attention => all documents valid
#
# See openspec/changes/document-checks/design.md (card ⑦ Results). Worked examples E12, E13, E15.
module DocChecks
  class Assessment
    # One document's results. changed: the document was replaced, removed or (when it was missing)
    # uploaded after the run, so its results no longer describe the document on file.
    Group = Struct.new(:name, :results, :document, :changed, keyword_init: true) do
      def attention_count
        changed ? results.size : results.count(&:needs_attention?)
      end

      def ok?
        attention_count.zero?
      end

      # The single line shown for a whole-document problem (not uploaded, unreadable)
      def document_problem
        results.find(&:document_level?)
      end
    end

    attr_reader :record

    def initialize(record)
      @record = record
      @entry = Registry.for(record)
    end

    def current_run
      return @current_run if defined?(@current_run)

      @current_run = DocCheckRun.real.for_record(record).find_by(current: true)
    end

    def checked?
      current_run.present?
    end

    # True when the entity has checks for any document on this record's list
    def checks?
      return @checks if defined?(@checks)

      @checks = DocCheck.for_record(record).exists?
    end

    def results
      @results ||= current_run ? current_run.doc_check_results.to_a : []
    end

    # The record's documents in its own list's order, limited to what the current run read: a document
    # taken off the list since disappears from the tab. Worked example E15.
    def groups
      @groups ||= begin
        by_name = results.group_by { |r| r.document_name.downcase }
        @entry.document_names_for(record).filter_map do |name|
          rows = by_name[name.downcase]
          next unless rows

          document = @entry.find_document(record, name)
          Group.new(name: rows.first.document_name, results: rows, document:, changed: changed?(rows, document))
        end
      end
    end

    def attention_count
      groups.sum(&:attention_count)
    end

    # All documents valid. Worked examples E12 (not uploaded blocks it), H6 (resolved items count as OK).
    def settled?
      checked? && attention_count.zero?
    end

    # A run newer than the current one that couldn't run — the "Couldn't check documents…" banner
    def could_not_run
      return @could_not_run if defined?(@could_not_run)

      scope = DocCheckRun.real.for_record(record).where(status: "could_not_run")
      scope = scope.where("id > ?", current_run.id) if current_run
      @could_not_run = scope.order(id: :desc).first
    end

    # The run being worked on now, if any (an expired one doesn't count)
    def active_run
      return @active_run if defined?(@active_run)

      @active_run = DocCheckRun.real.active.for_record(record).order(id: :desc).to_a.find { |run| !run.expired? }
    end

    # When the current results were last settled: the run, or a later resolution — the journey's evidence time
    def fresh_at
      [current_run&.finished_at, results.filter_map(&:resolved_at).max].compact.max
    end

    private

    # Worked example E13: compares the Shrine file id read with the file on the document now
    def changed?(rows, document)
      read = rows.find(&:document_id)
      # Nothing was on file when checked: changed once something is
      return document.present? unless read
      # The document read was removed, or another one now matches the name
      return true if document.nil? || document.id != read.document_id

      document.file&.id.to_s != read.document_file_id.to_s
    end
  end
end

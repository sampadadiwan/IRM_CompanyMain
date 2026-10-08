# Cucumber stand-in for the AI provider behind DocChecks::DocumentReader (tag @doc_checks_fake_ai).
# The reader still converts the real document and parses a real JSON reply; only the provider call is
# replaced. Readings are set per document and look-for by a step:
#   Given the AI reads from "CML": DP ID=IN303622; PAN=ABCPK1234F; Is it signed by the holder?=yes
# A look-for with no reading comes back as not found.
# See openspec/changes/document-checks/lld.md (Test Plumbing).
module DocChecks
  module FakeReader
    mattr_accessor :active, default: false
    # document name (downcased) => { look_for (downcased) => value }
    mattr_accessor :readings, default: {}
    mattr_accessor :calls, default: []
    mattr_accessor :progress, default: []
    mattr_accessor :provider_error, default: false
    mattr_accessor :garbage_documents, default: []
    # Called on the first AI call — stands for something a person does while the run reads documents
    mattr_accessor :during_read, default: nil

    LINE = /\A(c\d+) \((?:read the value|answer yes or no)\): (.*?)\.(?: Tip: .*)?\z/

    def self.reset!
      self.active = false
      self.readings = {}
      self.calls = []
      self.progress = []
      self.provider_error = false
      self.garbage_documents = []
      self.during_read = nil
    end

    def self.read(document_name, pairs)
      readings[document_name.downcase] = pairs.transform_keys(&:downcase)
    end

    # The reply the provider would give for one prompt
    def self.reply(prompt)
      items = prompt.lines.filter_map { |line| line.strip.match(LINE) }
      ids = items.filter_map { |m| m[1].delete_prefix("c").to_i }
      document_name = DocCheck.where(id: ids).pick(:document_name).to_s
      calls << document_name
      record_progress
      if during_read
        action = during_read
        self.during_read = nil
        action.call
      end
      raise "connection refused (fake provider down)" if provider_error
      return "Sorry, I can't read this document" if garbage_documents.include?(document_name.downcase)

      # "*" readings answer for any document (the AI rules tool's unsaved checks name none)
      values = (readings["*"] || {}).merge(readings[document_name.downcase] || {})
      items.to_h do |m|
        key = m[1]
        look_for = DocCheck.find_by(id: key.delete_prefix("c").to_i)&.look_for || m[2]
        value = values[look_for.downcase]
        [key, { "value" => value.to_s, "found" => value.present?, "explanation" => value.present? ? "Printed on the document" : "Not on the document" }]
      end.to_json
    end

    # What the tab header would say at this moment ("Checking CML (1 of 3)…")
    def self.record_progress
      run = DocCheckRun.where(status: "running").order(:id).last
      progress << [run.current_document, run.documents_done + 1, run.documents_total] if run
    end

    # Prepended to the reader's class methods / instance: only active under the tag
    module ClassPatch
      def llm_call(**kwargs)
        return super unless FakeReader.active

        FakeReader.reply(kwargs[:prompt])
      end
    end

    module InstancePatch
      private

      def initialize_llm(provider, llm_model, temperature)
        return super unless FakeReader.active

        Object.new # a client is required to proceed; the fake never calls it
      end
    end
  end
end

DocChecks::DocumentReader.singleton_class.prepend(DocChecks::FakeReader::ClassPatch)
DocChecks::DocumentReader.prepend(DocChecks::FakeReader::InstancePatch)

Before("@doc_checks_fake_ai") do
  DocChecks::FakeReader.reset!
  DocChecks::FakeReader.active = true
end

After("@doc_checks_fake_ai") do
  DocChecks::FakeReader.reset!
end

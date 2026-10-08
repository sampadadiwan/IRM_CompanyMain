# Which record types Document Checks supports, and the entry describing each: its documents, the
# fields it may fill in or compare, how to read and write them, and its hooks. The engine (run, reader,
# judge, assessment) only ever talks to a record through its entry.
# See openspec/changes/document-checks/design.md (card ② Registry).
module DocChecks
  class Registry
    # Record type => entry class name. Phase 3 record types add a line here.
    ENTRIES = { "InvestorKyc" => "DocChecks::Kyc" }.freeze

    # The entry for a record, a record class, or a record type name.
    # STI subclasses (IndividualKyc, NonIndividualKyc) resolve to their base class's entry.
    def self.for(record_or_type)
      ENTRIES.fetch(record_type_of(record_or_type)) { raise Error::UnknownRecordType, record_or_type.to_s }.constantize
    end

    def self.record_types
      ENTRIES.keys
    end

    # True when the value names a supported record type — checked before any constantize of user input
    def self.supported?(record_type)
      ENTRIES.key?(record_type.to_s)
    end

    def self.record_type_of(record_or_type)
      case record_or_type
      when String, Symbol then record_or_type.to_s
      when Class then record_or_type.base_class.name
      else record_or_type.class.base_class.name
      end
    end
  end
end

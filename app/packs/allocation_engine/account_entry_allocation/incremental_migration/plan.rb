module AccountEntryAllocation
  class IncrementalMigration
    # What one incremental allocation operation would change, as plain data: built by
    # IncrementalMigration#enable_plan / #disable_plan / #describe_plan / #reseed_plan, printed by
    # TextReport (rake), rendered by the fund formula operations page, stored in
    # FundFormulaOperation#plan, and handed back to IncrementalMigration#apply!.
    #
    #   "operation"       enable_incremental | disable_incremental | describe_incremental | reseed_carry_forward
    #   "params"          what the plan was built from, so apply! can build it again (reseed formula ids and date)
    #   "formula_count"   the fund's formula count when planned (reported, not compared)
    #   "already_enabled" enable only: the fund is already on incremental allocation
    #   "audited"         disable/describe only: the migration's audit trail was found
    #   "flag"            the incremental flag apply! sets: true, false, or nil to leave it
    #   "edits"           [{formula_id, sequence, name, pattern, formula_before, formula_after,
    #                       description_before, description_after}] — apply! writes whichever differ
    #   "blockers"        [{formula_id, message}] — apply! refuses while any exist
    #   "warnings"        [{formula_id, message}]
    #   "reseeds"         [{formula_id, sequence, name, date, values: [{capital_commitment_id, old_cents, new_cents}]}]
    #                     old_cents is nil where no entry is stored (left alone). Cents are decimal strings:
    #                     they survive a JSON column exactly, which floats would not.
    #   "values_computed" whether reseed values were computed (they need a full scratch copy)
    class Plan
      attr_reader :data

      def self.from_h(hash) = new(hash)

      def initialize(data = {})
        @data = { "edits" => [], "blockers" => [], "warnings" => [], "reseeds" => [], "params" => {} }
                .merge(data.to_h.deep_stringify_keys.except("fingerprint"))
      end

      %w[operation params formula_count flag edits blockers warnings reseeds].each do |key|
        define_method(key) { data[key] }
      end

      def already_enabled? = data["already_enabled"] == true
      def audited? = data["audited"] == true
      def values_computed? = data["values_computed"] == true
      def blocked? = blockers.any?

      # Anything for apply! to write
      def changes? = edits.any? || reseed_write_count.positive? || !flag.nil?

      def reseed_value_count = reseeds.sum { |r| r["values"].to_a.size }

      # The values apply! writes: those with a stored entry to overwrite
      def reseed_write_count = reseeds.sum { |r| r["values"].to_a.count { |v| v["old_cents"] } }

      # Stable across a round trip through a MySQL JSON column, which reorders object keys
      def fingerprint
        Digest::SHA256.hexdigest(JSON.generate(canonical(data.except("formula_count"))))
      end

      def to_h = data.merge("fingerprint" => fingerprint)

      private

      def canonical(value)
        case value
        when Hash then value.keys.sort.index_with { |k| canonical(value[k]) }
        when Array then value.map { |v| canonical(v) }
        else value
        end
      end
    end
  end
end

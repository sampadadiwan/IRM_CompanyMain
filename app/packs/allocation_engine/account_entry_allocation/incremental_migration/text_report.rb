module AccountEntryAllocation
  class IncrementalMigration
    # Prints a Plan the way lib/tasks/incremental_allocation.rake always has, so the rake tasks stay thin
    # wrappers over the same plans the fund formula operations page shows.
    class TextReport
      def initialize(fund, out = $stdout)
        @fund = fund
        @out = out
      end

      def enable(plan)
        return say("already enabled, nothing to do") if plan.already_enabled?

        say "#{@fund.name}: #{plan.formula_count} formulas"
        say "formula edits: #{plan.edits.size}"
        plan.edits.each do |e|
          say "  seq #{e['sequence']} #{e['name']} [#{e['pattern']}]"
          say "    before: #{e['formula_before'].to_s.squish.truncate(300)}"
          say "    after:  #{e['formula_after'].to_s.squish.truncate(300)}"
          say "    description: #{e['description_after'].to_s.squish.truncate(600)}" if e["description_after"] != e["description_before"].to_s.strip
        end
        say "starting values to correct: #{plan.reseeds.map { |r| "seq #{r['sequence']} on #{r['date']}" }.join(', ').presence || 'none'}"
        plan.warnings.each { |w| say "WARNING #{w['message']}" }
        plan.blockers.each { |b| say "BLOCKER #{b['message']}" }
        say "BLOCKED: #{plan.blockers.size} issue(s) above need a manual formula edit. Nothing changed." if plan.blocked?
      end

      def loading_full_copy
        say "loading a full copy of fund #{@fund.id} to compute starting values..."
      end

      def reseed_values(plan)
        plan.reseeds.each do |reseed|
          say "  starting values for seq #{reseed['sequence']} #{reseed['name']} on #{reseed['date']}:"
          reseed["values"].each do |v|
            old = v["old_cents"] ? format("%.2f", BigDecimal(v["old_cents"]) / 100) : "no stored entry, skipped"
            say format("    commitment %<cc>d: %<old>s -> %<new>.2f", cc: v["capital_commitment_id"], old:, new: BigDecimal(v["new_cents"]) / 100)
          end
        end
      end

      def enabled(plan)
        say "ENABLED: #{plan.edits.size} formula edit(s), #{plan.reseed_write_count} starting value(s) corrected, flag on"
      end

      def disable(plan)
        say "flag #{plan.params['enabled'] ? 'on' : 'already off'}; #{plan.edits.size} formula(s) to restore from the audit trail"
        plan.edits.each { |e| say "  seq #{e['sequence']} #{e['name']}\n    restore: #{e['formula_after'].to_s.squish.truncate(300)}" }
        plan.warnings.each { |w| say "WARNING #{w['message']}" }
        say "  (tracking formula fixes are kept: they are correct with or without the flag)" if plan.audited?
        say "  WARNING: no migration audit found for this fund's formulas; edited formulas are left as they are" unless plan.audited?
      end

      def disabled(plan)
        say "DISABLED: #{plan.edits.size} formula(s) restored, flag off"
      end

      def describe(plan)
        plan.warnings.each { |w| say "  #{w['message']}" }
        say "#{plan.edits.size} edited formula(s) without a migration description"
        plan.edits.each { |e| say "  seq #{e['sequence']} #{e['name']}\n    description: #{e['description_after'].to_s.squish.truncate(600)}" }
      end

      def described(plan)
        say "DESCRIBED: #{plan.edits.size} formula(s)"
      end

      # Unprefixed, as the reseed_carry_forward task always printed it
      def reseed(plan, applied:, updated:)
        missing = 0
        plan.reseeds.each do |reseed|
          @out.puts "\n#{reseed['sequence']} #{reseed['name']}"
          reseed["values"].each do |v|
            if v["old_cents"].nil?
              missing += 1
              @out.puts "  commitment #{v['capital_commitment_id']}: no stored entry on #{reseed['date']}, left alone"
            else
              @out.puts format("  commitment %<cc>d: %<old>.2f -> %<new>.2f", cc: v["capital_commitment_id"],
                                                                              old: BigDecimal(v["old_cents"]) / 100, new: BigDecimal(v["new_cents"]) / 100)
            end
          end
        end
        plan.warnings.each { |w| @out.puts "  #{w['message']}" }
        @out.puts "\n#{'DRY RUN, nothing written. ' unless applied}updated=#{updated} missing=#{missing}"
      end

      private

      def say(message)
        @out.puts("[fund #{@fund.id}] #{message}")
        nil
      end
    end
  end
end

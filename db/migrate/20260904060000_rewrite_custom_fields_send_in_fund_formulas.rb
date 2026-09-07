class RewriteCustomFieldsSendInFundFormulas < ActiveRecord::Migration[8.1]
  # Security review 1 (#1538, 2026-07-10) added `send` / `__send__` / `public_send` to
  # ApplicationRecord::SAFE_EVAL_REGEX, because reflective dispatch defeats the rest of the
  # denylist (`send("sys" + "tem", ...)`). The same change made AllocationBaseOperation run
  # safe_eval! at evaluation time, so every pre-existing formula that reads a commitment's
  # custom field dynamically with
  #
  #   capital_commitment.custom_fields.send(custom_field_key.to_s)
  #
  # now fails at run time with "Refusing to evaluate an unsafe expression". Those rows were
  # saved before the token was denylisted, so FundFormula#formula_kosher? never rejected them.
  #
  # CustomFieldsProxy supports hash-style lookup (`custom_fields[key]`, string or symbol, see
  # docs/technical/custom_fields_proxy.md), which is the documented pattern for dynamic keys
  # and is not on the denylist. This migration rewrites the receiver/argument pair in place:
  #
  #   custom_fields.send(ARG)      -> custom_fields[ARG]
  #   custom_fields&.send(ARG)     -> custom_fields&.[](ARG)
  #   (also __send__ / public_send)
  #
  # ARG is kept verbatim so the diff is mechanical and reviewable. Behaviour is identical for a
  # present key. For a missing/blank key `[]` returns nil (so `.to_d` gives 0) where `send("")`
  # would have raised -- strictly more lenient, never wrong.
  #
  # Rows are written with update_columns: the goal is to fix the stored text, not to re-run
  # validations, callbacks or the Elasticsearch update_index hook for a formula whose other
  # attributes may pre-date later validations. Soft-deleted rows are included (unscoped) so a
  # restored formula does not resurface the problem.

  # Matches `custom_fields.send(ARG)` (and the &. / __send__ / public_send variants). ARG allows
  # one level of nested parentheses, e.g. `send(key.parameterize(separator: '_'))`.
  SEND_PATTERN = /
    custom_fields(?<safe_nav>&)?\.\s*
    (?:__send__|public_send|send)\s*
    \((?<arg>[^()]*(?:\([^()]*\)[^()]*)*)\)
  /x

  def up
    rewritten = 0
    still_unsafe = []

    # The LIKE pre-filter keeps the Ruby-side scan to candidate rows only; the regex above is
    # the real test. `unscoped` lifts the acts_as_paranoid default scope.
    FundFormula.unscoped.where("formula LIKE ?", "%send%").find_each do |fund_formula|
      original = fund_formula.formula.to_s
      updated = original.gsub(SEND_PATTERN) do
        m = Regexp.last_match
        m[:safe_nav] ? "custom_fields&.[](#{m[:arg]})" : "custom_fields[#{m[:arg]}]"
      end
      next if updated == original

      # Sanity check: the rewritten formula must still be valid Ruby before we store it.
      Parser::CurrentRuby.parse(updated)

      fund_formula.update_columns(formula: updated, updated_at: Time.current)
      rewritten += 1

      # A row can carry other denylisted tokens (e.g. a bare `send` outside custom_fields);
      # those still need a manual fix, so surface them rather than silently moving on.
      still_unsafe << fund_formula.id if updated.downcase.match?(ApplicationRecord::SAFE_EVAL_REGEX)
    rescue Parser::SyntaxError => e
      # Leave the row untouched; a broken formula is a manual-fix job, not a migration failure.
      say "FundFormula##{fund_formula.id}: rewrite would not parse (#{e.message}); left unchanged", true
    end

    say "Rewrote custom_fields.send(...) -> custom_fields[...] in #{rewritten} fund formula(s)"
    say "Still failing SAFE_EVAL_REGEX after rewrite, fix by hand: #{still_unsafe.inspect}", true if still_unsafe.any?
  end

  # Not reversible on purpose: the hash-lookup form works on every version of the code (the
  # proxy has supported `[]` since CustomFieldsProxy replaced OpenStruct), while restoring
  # `.send(...)` would reinstate formulas that the runtime guard rejects. There is nothing to
  # go back to.
  def down
    raise ActiveRecord::IrreversibleMigration, "custom_fields[...] is valid on all code versions; restoring .send(...) would recreate the unsafe-expression failure"
  end
end

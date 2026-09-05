class NormalizeCapitalCallClosePercentagesEncoding < ActiveRecord::Migration[8.1]
  # `capital_calls.close_percentages` is a native `json` column (see
  # db/migrate/archive/20240911114520_add_close_percentages_to_capital_calls.rb), but
  # CapitalCall used to also declare `serialize :close_percentages, type: Hash` on top of
  # it. Every write that went through that declaration double-encoded the value: the YAML
  # coder dumped the Hash to a YAML string first, then the json column type JSON-encoded
  # that string, so the column ended up holding a JSON string literal wrapping YAML text,
  # e.g. `"--- !ruby/hash:ActiveSupport::HashWithIndifferentAccess\nFirst Close: '10'\n"`.
  # That round-tripped fine as long as the same `serialize` declaration stayed on the
  # model to reverse it on read.
  #
  # A separate set of rows was written with a plain JSON hash in the column instead (no
  # `serialize` involved) — most likely from a period, or code path, that assigned the
  # attribute without going through the coder. Those rows crashed on read with "no
  # implicit conversion of Hash into String": the `serialize` coder's YAML loader was
  # handed an already-deserialized Hash and tried to parse it as if it were text.
  #
  # The `serialize` declaration has been removed from CapitalCall (it was always
  # redundant on a `json` column — the column type alone gives Hash semantics on
  # read/write). That fixes the plain-JSON rows but leaves every double-encoded legacy
  # row returning a raw YAML string instead of a Hash, breaking `.present?`/`.each`
  # call sites in the capital call views. This migration rewrites those legacy rows in
  # place so every row in the column holds a plain JSON hash, matching what the
  # `json` column type produces on its own.
  def up
    rewritten = 0
    failed = []

    # `unscoped` lifts the acts_as_paranoid default scope so a soft-deleted capital call
    # does not resurface the problem if it is ever restored.
    CapitalCall.unscoped.where.not(close_percentages: nil).find_each do |capital_call|
      value = capital_call.close_percentages
      # Already a Hash: either a plain-JSON row (nothing to do) or already rewritten.
      next unless value.is_a?(String)

      decoded = YAML.unsafe_load(value)
      unless decoded.is_a?(Hash)
        failed << capital_call.id
        say "CapitalCall##{capital_call.id}: decoded close_percentages was a #{decoded.class}, expected Hash; left unchanged", true
        next
      end

      # update_columns skips callbacks/validations/timestamps-on-save (we still bump
      # updated_at explicitly) -- the goal is to fix the stored encoding, not to re-run
      # business logic for a row that may pre-date later validations.
      capital_call.update_columns(close_percentages: decoded.stringify_keys, updated_at: Time.current)
      rewritten += 1
    rescue Psych::SyntaxError => e
      failed << capital_call.id
      say "CapitalCall##{capital_call.id}: close_percentages would not parse as YAML (#{e.message}); left unchanged", true
    end

    say "Rewrote double-encoded close_percentages on #{rewritten} capital call(s)"
    say "Left unchanged, needs a manual look: #{failed.inspect}" if failed.any?
  end

  # Not reversible on purpose: a plain JSON hash is valid on every version of the code
  # (it is what the `json` column type produces natively), while re-encoding it back to
  # a YAML-string-in-JSON would only recreate the original double-encoding bug.
  def down
    raise ActiveRecord::IrreversibleMigration, "plain JSON hashes are valid on all code versions; there is nothing to revert to"
  end
end

# Locks a ready statement set: copies every figure, the rendered statements (with comparatives),
# the mapping and the check results into frozen_data, records who and when, and locks the
# statements run. Re-locking after an unlock overwrites the frozen copy (E26).
# Worked examples H15, E26, X8, X9 — openspec/changes/fund-financial-statements/design.md#worked-examples
class FinancialStatementLock
  class Refused < StandardError; end

  def self.call(statement, user:)
    statement.with_lock do
      # Checked again under the row lock: a Regenerate may have started since the page loaded
      lockable, reason = statement.lockable_with_reason
      raise Refused, reason unless lockable

      # H15: the published truth (E26: re-locking after an unlock overwrites the previous copy): figures for comparatives/drift, rendered statements for the locked view
      # and downloads, the mapping and checks as they were
      frozen = {
        "figures" => statement.figures.transform_keys(&:to_s).transform_values { |f| f.transform_values(&:to_s) },
        "statements" => FinancialStatementPresenter.new(statement).statements,
        "mapping" => FinancialStatementMappingRule.where(fund_id: statement.fund_id).includes(:account)
                                                  .map { |r| { "rule" => r.key_label, "target" => r.target_label } },
        "checks" => statement.checks_list,
        "locked_at" => Time.current.iso8601
      }
      statement.update!(status: "locked", frozen_data: frozen, locked_at: Time.current, locked_by: user)
      # Locking the statements run makes an unlock of the period go through the warning (⑦). Only the
      # flag is set (no validations): the default rule "allocation_run_already_locked" blocks any save
      # of a run whose locked is true, which would refuse the lock itself
      statement.statements_allocation_run&.update_column(:locked, true)
    end
    statement
  end
end

# Replaces the two separate FK columns (fund_ratio_run_id, portfolio_scenario_id) with a
# single polymorphic parent: computation_context_type + computation_context_id.
#
# Both columns were mutually exclusive (a FundRatio belongs to at most one parent), so the
# backfill is unambiguous. See docs/modules/funds/fund_ratios/fund_ratio_run.md — "polymorphic computation_context".
class AddComputationContextToFundRatios < ActiveRecord::Migration[7.2]
  def up
    # Step 1: add the two polymorphic columns. Guards prevent errors on re-run
    # if a previous failed attempt partially applied the migration.
    add_column :fund_ratios, :computation_context_type, :string  unless column_exists?(:fund_ratios, :computation_context_type)
    add_column :fund_ratios, :computation_context_id,   :bigint  unless column_exists?(:fund_ratios, :computation_context_id)
    unless index_exists?(:fund_ratios, %i[computation_context_type computation_context_id], name: "index_fund_ratios_on_computation_context")
      add_index :fund_ratios, %i[computation_context_type computation_context_id],
                name: "index_fund_ratios_on_computation_context"
    end

    # Step 2: backfill from the two old FK columns (separate execute calls — MySQL
    # does not allow multiple statements in a single execute).
    # Guards protect against environments where the source column was never added
    # (e.g. the archived migration 20250909095052 was skipped on a fresh DB).
    if column_exists?(:fund_ratios, :fund_ratio_run_id)
      execute <<~SQL
        UPDATE fund_ratios
           SET computation_context_type = 'FundRatioRun',
               computation_context_id   = fund_ratio_run_id
         WHERE fund_ratio_run_id IS NOT NULL
      SQL
    end

    if column_exists?(:fund_ratios, :portfolio_scenario_id)
      execute <<~SQL
        UPDATE fund_ratios
           SET computation_context_type = 'PortfolioScenario',
               computation_context_id   = portfolio_scenario_id
         WHERE portfolio_scenario_id IS NOT NULL
      SQL
    end

    # Step 3: drop the now-redundant FK columns and their indexes.
    # remove_reference handles dropping the FK constraint and the index together.
    remove_reference :fund_ratios, :fund_ratio_run,    foreign_key: true if column_exists?(:fund_ratios, :fund_ratio_run_id)
    remove_reference :fund_ratios, :portfolio_scenario, foreign_key: true if column_exists?(:fund_ratios, :portfolio_scenario_id)
  end

  def down
    add_reference :fund_ratios, :fund_ratio_run,    foreign_key: true, null: true
    add_reference :fund_ratios, :portfolio_scenario, foreign_key: true, null: true

    execute <<~SQL
      UPDATE fund_ratios
         SET fund_ratio_run_id = computation_context_id
       WHERE computation_context_type = 'FundRatioRun'
    SQL

    execute <<~SQL
      UPDATE fund_ratios
         SET portfolio_scenario_id = computation_context_id
       WHERE computation_context_type = 'PortfolioScenario'
    SQL

    remove_index  :fund_ratios, name: "index_fund_ratios_on_computation_context"
    remove_column :fund_ratios, :computation_context_type
    remove_column :fund_ratios, :computation_context_id
  end
end

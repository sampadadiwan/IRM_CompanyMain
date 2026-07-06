class AddTemplateToFundRatioRuns < ActiveRecord::Migration[7.2]
  def change
    add_reference :fund_ratio_runs, :fund_ratio_run_template, null: true, foreign_key: true
  end
end

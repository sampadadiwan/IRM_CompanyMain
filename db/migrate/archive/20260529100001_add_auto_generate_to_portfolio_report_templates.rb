class AddAutoGenerateToPortfolioReportTemplates < ActiveRecord::Migration[7.2]
  def change
    add_column :portfolio_report_templates, :auto_generate_enabled,    :boolean, default: false, null: false
    # frequency: "monthly" | "quarterly"
    add_column :portfolio_report_templates, :auto_generate_frequency,  :string
    # day_of_month on which the job fires (1-28)
    add_column :portfolio_report_templates, :auto_generate_day,        :integer, default: 1
    add_column :portfolio_report_templates, :auto_generate_last_run_at, :datetime
  end
end

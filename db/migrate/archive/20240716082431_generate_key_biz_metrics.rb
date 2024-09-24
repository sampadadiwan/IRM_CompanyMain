class GenerateKeyBizMetrics < ActiveRecord::Migration[7.1]
  def change
    # (0..12).each do |month|
    #   date = Date.today.beginning_of_month - (12 - month).months
    #   KeyBizMetricsJob.perform_now(date)
    #   (1..3).each do |week|
    #     KeyBizMetricsJob.perform_now(date + week.weeks)
    #   end
    # end

    # KeyBizMetricsJob.perform_now(Date.today)
    # (1..7).each do |day|
    #   KeyBizMetricsJob.perform_now(Date.today - day.days)
    # end    
  end
end

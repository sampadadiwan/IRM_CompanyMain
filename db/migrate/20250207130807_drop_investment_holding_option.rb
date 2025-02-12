class DropInvestmentHoldingOption < ActiveRecord::Migration[7.2]


  def change
    execute "SET FOREIGN_KEY_CHECKS = 0;"
    
    drop_table :whatsapp_logs
    drop_table :vesting_schedules
    drop_table :share_transfers    
    drop_table :investment_snapshots    
    drop_table :option_pools

    drop_table :investments    
    drop_table :aggregate_investments    
    drop_table :excercises    
    drop_table :holdings    

    execute "SET FOREIGN_KEY_CHECKS = 1;"    
  end
end

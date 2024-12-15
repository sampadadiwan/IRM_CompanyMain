class CreateTickerFeeds < ActiveRecord::Migration[7.2]
  def change
    create_table :ticker_feeds do |t|
      t.string :ticker, limit: 10
      t.decimal :price_cents, precision: 20, scale: 2
      t.string :name, limit: 100
      t.string :source, limit: 10
      t.date :for_date
      t.datetime :for_time
      t.string :price_type, limit: 3
      t.string :currency, limit: 3

      t.timestamps
    end
  end
end

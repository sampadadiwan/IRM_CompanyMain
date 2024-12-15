json.extract! ticker_feed, :id, :ticker, :price_cents, :name, :source, :for_date, :for_time, :price_type, :created_at, :updated_at
json.url ticker_feed_url(ticker_feed, format: :json)

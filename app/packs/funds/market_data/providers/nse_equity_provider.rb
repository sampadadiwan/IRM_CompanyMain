# NSE cash-market daily bhavcopy (UDiFF common format, zipped CSV). Keys are NSE tickers; the value
# is the closing price (ClsPric). Worked examples H8, E43, E44, X15 — fund-market-data.
class NseEquityProvider < MarketDataProvider
  def url(date)
    "https://nsearchives.nseindia.com/content/cm/BhavCopy_NSE_CM_0_0_0_#{date.strftime('%Y%m%d')}_F_0000.csv.zip"
  end

  def label
    "NSE"
  end

  def fetch(keys, date)
    body = http_get(url(date), headers: BROWSER_HEADERS.merge("Referer" => "https://www.nseindia.com/"))
    closes_by_ticker(unzip_first(body), keys)
  rescue Error => e
    # No file for a holiday / not yet published → nothing loaded (the runner lists every key missing)
    raise unless e.message.include?("HTTP 404")

    {}
  end

  private

  def closes_by_ticker(csv_text, keys)
    wanted = keys.to_set
    udiff_rows(csv_text).each_with_object({}) do |row, quotes|
      ticker = row["TckrSymb"]
      next unless wanted.include?(ticker)
      # Prefer the EQ series when a symbol trades in several
      next if quotes[ticker] && row["SctySrs"] != "EQ"

      quotes[ticker] = Quote.new(value: BigDecimal(row["ClsPric"].to_s), label:)
    end
  end
end

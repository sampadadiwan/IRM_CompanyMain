# NSE F&O daily bhavcopy (UDiFF common format, zipped CSV). Keys are contract symbols as NSE prints
# them in FinInstrmNm (e.g. NIFTY26NOV24000PE); the value is the settlement price (SttlmPric).
# Worked example H13 — openspec/changes/fund-market-data/business-rules.md
class NseFoProvider < MarketDataProvider
  def url(date)
    "https://nsearchives.nseindia.com/content/fo/BhavCopy_NSE_FO_0_0_0_#{date.strftime('%Y%m%d')}_F_0000.csv.zip"
  end

  def label
    "NSE F&O"
  end

  def fetch(keys, date)
    wanted = keys.to_set
    body = http_get(url(date), headers: BROWSER_HEADERS.merge("Referer" => "https://www.nseindia.com/"))
    udiff_rows(unzip_first(body)).each_with_object({}) do |row, quotes|
      symbol = row["FinInstrmNm"]
      next unless wanted.include?(symbol)

      quotes[symbol] = Quote.new(value: BigDecimal(row["SttlmPric"].to_s), label:)
    end
  rescue Error => e
    raise unless e.message.include?("HTTP 404")

    {}
  end
end

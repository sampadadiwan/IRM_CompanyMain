# BSE cash-market daily bhavcopy (UDiFF common format, plain CSV). Keys are BSE tickers; value is
# the closing price. Worked example H8 — fund-market-data.
class BseEquityProvider < NseEquityProvider
  def url(date)
    "https://www.bseindia.com/download/BhavCopy/Equity/BhavCopy_BSE_CM_0_0_0_#{date.strftime('%Y%m%d')}_F_0000.CSV"
  end

  def label
    "BSE"
  end

  def fetch(keys, date)
    body = http_get(url(date), headers: BROWSER_HEADERS.merge("Referer" => "https://www.bseindia.com/"))
    closes_by_ticker(body, keys)
  rescue Error => e
    raise unless e.message.include?("HTTP 404")

    {}
  end
end

# NSE corporate actions (the public JSON used by nseindia.com; needs the site's cookies, so it is
# best-effort). Returns splits, bonuses and dividends for the given tickers with an ex-date in the
# window. Parsed from the action's subject text. Worked examples H10, E46, E47 — fund-market-data.
class NseCorporateActionsProvider < MarketDataProvider
  HOME = "https://www.nseindia.com/".freeze
  API = "https://www.nseindia.com/api/corporates-corporateActions".freeze

  Action = Struct.new(:ticker, :kind, :ex_date, :ratio, :amount_per_share, :subject, :ref, keyword_init: true)

  def label
    "NSE"
  end

  def actions(tickers, from, to)
    wanted = tickers.to_set
    rows = JSON.parse(fetch_json(from, to))
    rows.filter_map do |row|
      next unless wanted.include?(row["symbol"])

      parse(row)
    end
  rescue JSON::ParserError => e
    raise Error, "NSE corporate actions: unreadable response (#{e.message})"
  end

  # Turns NSE's subject into a kind and numbers, e.g.
  #   "Face Value Split (Sub-Division) - From Rs 10/- Per Share To Rs 2/- Per Share" → split 5
  #   "Bonus 1:1" → bonus, ratio 2 (each share becomes two)
  #   "Dividend - Rs 1.50 Per Share" → dividend 1.50
  def parse(row)
    subject = row["subject"].to_s
    ex_date = parse_date(row["exDate"])
    return nil unless ex_date

    base = { ticker: row["symbol"], ex_date:, subject: }
    if (m = subject.match(%r{From Rs\.?\s*([\d.]+)/?-?\s*Per Share To Rs\.?\s*([\d.]+)}i)) && subject.match?(/split/i)
      Action.new(**base, kind: "split", ratio: (BigDecimal(m[1]) / BigDecimal(m[2])).round(8), ref: ref(row, "split"))
    elsif (m = subject.match(/Bonus\s*(\d+)\s*:\s*(\d+)/i))
      Action.new(**base, kind: "bonus", ratio: ((BigDecimal(m[1]) + BigDecimal(m[2])) / BigDecimal(m[2])).round(8), ref: ref(row, "bonus"))
    elsif (m = subject.match(/Dividend.*?Rs\.?\s*([\d.]+)/i))
      Action.new(**base, kind: "dividend", amount_per_share: BigDecimal(m[1]), ref: ref(row, "dividend"))
    end
  end

  private

  def parse_date(text)
    Date.strptime(text.to_s, "%d-%b-%Y")
  rescue Date::Error
    nil
  end

  def ref(row, kind)
    "nse:#{row['symbol']}:#{kind}:#{row['exDate']}"
  end

  def fetch_json(from, to)
    conn = Faraday.new(request: { open_timeout: 10, timeout: 30 })
    cookies = conn.get(HOME, nil, BROWSER_HEADERS).headers["set-cookie"].to_s.split(/,\s*(?=[^;]+=)/).map { |c| c.split(";").first }.join("; ")
    url = "#{API}?index=equities&from_date=#{from.strftime('%d-%m-%Y')}&to_date=#{to.strftime('%d-%m-%Y')}"
    response = conn.get(url, nil, BROWSER_HEADERS.merge("Cookie" => cookies, "Referer" => "https://www.nseindia.com/companies-listing/corporate-filings-actions"))
    raise Error, "NSE corporate actions: HTTP #{response.status}" unless response.success?

    response.body
  rescue Faraday::Error => e
    raise Error, "NSE corporate actions: #{e.message}"
  end
end

# AMFI daily NAV file for mutual funds (semicolon-separated). Keys are ISINs; the value is the NAV
# when the file's date matches the run date. Worked example E42 — fund-market-data.
class AmfiProvider < MarketDataProvider
  URL = "https://portal.amfiindia.com/spages/NAVAll.txt".freeze

  def label
    "AMFI"
  end

  def fetch(keys, date)
    wanted = keys.to_set
    http_get(URL, headers: BROWSER_HEADERS).each_line.with_object({}) do |line, quotes|
      # NAVAll.txt rows are "Scheme Code;ISIN Growth;ISIN Reinvestment;Scheme Name;NAV;Date" (6
      # columns). Read NAV and date from the end so an extra descriptive column never shifts them.
      cols = line.strip.split(";")
      next unless cols.size >= 6

      nav = cols[-2].to_s
      next unless nav_date(cols[-1]) == date

      [cols[1], cols[2]].each do |isin|
        next unless wanted.include?(isin)

        quotes[isin] = Quote.new(value: BigDecimal(nav), label:) if nav.match?(/\A[\d.]+\z/)
      end
    end
  end

  private

  def nav_date(text)
    Date.strptime(text.to_s, "%d-%b-%Y")
  rescue Date::Error
    nil
  end
end

# ECB euro foreign exchange reference rates (free, public; published on TARGET business days).
# The ECB file gives EUR→X; a pair not involving EUR (e.g. USD→INR) is worked out from the same
# day's table as EUR→INR ÷ EUR→USD and labelled "ECB via EUR". Only the ECB feed is used for FX in
# this change (FBIL has no machine-readable feed — proposal L6).
# Worked examples H4, E14, E73, X6, X7 — openspec/changes/fund-market-data/business-rules.md
class EcbProvider < MarketDataProvider
  # The last 90 days, so a re-run for a recent date still finds its rates
  URL = "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist-90d.xml".freeze

  def fetch(keys, date)
    table = rates_on(date)
    return {} if table.empty?

    keys.each_with_object({}) do |key, quotes|
      from, to = key.split("/")
      next unless table[from] && table[to]

      # X7 — a zero or negative published rate gives an invalid quote (not stored, listed missing)
      value = table[from].positive? && table[to].positive? ? (table[to] / table[from]).round(8) : BigDecimal(0)
      label = from == "EUR" ? "ECB" : "ECB via EUR"
      quotes[key] = Quote.new(value:, label:)
    end
  end

  private

  # { "EUR" => 1, "USD" => 1.1206, "INR" => 108.39, … } for the date, or {} when not published
  def rates_on(date)
    xml = http_get(URL)
    doc = Nokogiri::XML(xml)
    doc.remove_namespaces!
    day = doc.at_xpath("//Cube[@time='#{date.iso8601}']")
    return {} unless day

    day.xpath("./Cube").each_with_object({ "EUR" => BigDecimal(1) }) do |node, table|
      table[node["currency"]] = BigDecimal(node["rate"])
    end
  rescue Nokogiri::XML::SyntaxError => e
    raise Error, "ECB: could not read the rates file (#{e.message})"
  end
end

# Base for feed adapters. An adapter turns a list of keys (currency pairs "USD/INR", tickers, ISINs
# or contract symbols) and a date into quotes; keys it cannot price are simply left out. HTTP or
# parse failures raise MarketDataProvider::Error, which the feed runner records on the run.
# openspec/changes/fund-market-data — design card ② (providers).
class MarketDataProvider
  class Error < StandardError; end

  # value: BigDecimal; label: provider label stored on the row (e.g. "ECB", "ECB via EUR")
  Quote = Struct.new(:value, :label, keyword_init: true)

  RETRIES = 3

  REGISTRY = {
    "ecb" => "EcbProvider",
    "nse" => "NseEquityProvider",
    "bse" => "BseEquityProvider",
    "amfi" => "AmfiProvider",
    "nse_fo" => "NseFoProvider",
    "nse_corp_actions" => "NseCorporateActionsProvider"
  }.freeze

  # Browser-like headers: NSE/BSE archives refuse requests without them
  BROWSER_HEADERS = {
    "User-Agent" => "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Safari/537.36",
    "Accept" => "*/*"
  }.freeze

  def self.for(key)
    REGISTRY.fetch(key.to_s).constantize.new
  end

  # Label shown on stored rows, e.g. "NSE"
  def label
    self.class.name.delete_suffix("Provider").sub("EquityProvider", "").upcase
  end

  # { key => Quote } for the keys this provider can price on the date
  def fetch(_keys, _date)
    raise NotImplementedError
  end

  private

  # Rows of an exchange "UDiFF" common bhavcopy (NSE / BSE, cash and F&O share one layout)
  def udiff_rows(csv_text)
    CSV.parse(csv_text, headers: true)
  rescue CSV::MalformedCSVError => e
    raise Error, "#{self.class.name}: could not read the file (#{e.message})"
  end

  def unzip_first(zip_bytes)
    Zip::InputStream.open(StringIO.new(zip_bytes)) do |io|
      entry = io.get_next_entry
      raise Error, "#{self.class.name}: empty archive" unless entry

      return io.read
    end
  end

  # GET with retries and timeouts; raises Error after the last try. A 404 (holiday / not yet
  # published) is not retried. Each file is downloaded once per URL for 12 hours, so many
  # entities on the same feed share one download.
  def http_get(url, headers: {})
    Rails.cache.fetch("market_data/download/#{Digest::SHA256.hexdigest(url)}", expires_in: 12.hours) do
      attempts = 0
      begin
        attempts += 1
        response = Faraday.new(request: { open_timeout: 10, timeout: 60 }).get(url, nil, headers)
        raise Error, "#{self.class.name}: HTTP #{response.status} for #{url}" unless response.success?

        response.body
      rescue Faraday::Error, Error => e
        retry if attempts < RETRIES && e.message.exclude?("HTTP 404") && sleep(retry_wait(attempts))
        raise Error, e.message
      end
    end
  end

  def retry_wait(attempt)
    Rails.env.test? ? 0 : [2, 8, 30][attempt - 1]
  end
end

module AgentTools
  class WebSearchTool
    def self.search(query)
      start_time = Time.current
      Rails.logger.info "[WebSearchTool] Searching for: #{query}"

      # Use DuckDuckGo HTML search (no API key required)
      encoded_query = CGI.escape(query)
      response = HTTParty.get(
        "https://html.duckduckgo.com/html/",
        query: { q: query },
        headers: { 
          'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        },
        timeout: 15
      )

      duration = (Time.current - start_time).round(2)
      Rails.logger.info "[WebSearchTool] Search completed for '#{query}' in #{duration}s"

      parse_duckduckgo_html(response.body)
    rescue StandardError => e
      Rails.logger.error "[WebSearchTool] Search failed: #{e.message}"
      { error: e.message }
    end

    private

    def self.parse_duckduckgo_html(html)
      require 'nokogiri'
      doc = Nokogiri::HTML(html)

      results = []
      doc.css('.result').first(5).each do |result|
        title = result.css('.result__title')&.text&.strip
        snippet = result.css('.result__snippet')&.text&.strip
        link = result.css('.result__url')&.text&.strip

        results << "#{title}: #{snippet}" if snippet.present?
      end

      Rails.logger.info "[WebSearchTool] Parsed #{results.count} results"

      {
        abstract_text: results.first,
        related_topics: results,
        sources: []
      }
    end
  end
end

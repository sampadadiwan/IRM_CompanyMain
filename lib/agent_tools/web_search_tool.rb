module AgentTools
  class WebSearchTool
    LOG_FILE = Rails.root.join('log', 'web_search_debug.log')

    DEFAULT_OPTIONS = {
      gl: "in",           # Country: India
      hl: "en",           # Language: English
      google_domain: "google.com"
    }.freeze

    def self.search(query, num_results: 5, **options)
      start_time = Time.current
      Rails.logger.info "[WebSearchTool] Searching for: #{query}"

      # DEBUG: Log to file
      log_to_file("=" * 80)
      log_to_file("SEARCH REQUEST")
      log_to_file("Time: #{Time.current}")
      log_to_file("Query: #{query}")
      log_to_file("Search Type: #{options[:tbm] || 'regular'}")
      log_to_file("Time Filter: #{options[:as_qdr] || 'none'}")
      log_to_file("-" * 40)

      api_key = Rails.application.credentials[:SERPAPI_KEY]
      if api_key.blank?
        Rails.logger.error "[WebSearchTool] SerpAPI key not configured in credentials"
        log_to_file("ERROR: SerpAPI key not configured")
        return { error: "SerpAPI key not configured" }
      end

      search_params = DEFAULT_OPTIONS.merge(
        q: query,
        api_key: api_key,
        num: num_results
      ).merge(options)

      log_to_file("Country: #{search_params[:gl]}")
      log_to_file("Language: #{search_params[:hl]}")
      log_to_file("Num Results Requested: #{num_results}")
      Rails.logger.info "[WebSearchTool] Search params: #{search_params.except(:api_key)}"

      search = GoogleSearch.new(search_params)
      data = search.get_hash

      duration = (Time.current - start_time).round(2)
      Rails.logger.info "[WebSearchTool] Search completed for '#{query}' in #{duration}s"
      
      # DEBUG: Log raw response in human-readable format
      log_to_file("-" * 40)
      log_to_file("RAW RESULTS (Duration: #{duration}s)")
      log_to_file("-" * 40)
      log_raw_results_readable(data, options[:tbm])

      result = parse_serpapi_response(data, options[:tbm])

      # DEBUG: Log parsed result
      log_to_file("-" * 40)
      log_to_file("PARSED RESULT SUMMARY")
      log_to_file("-" * 40)
      log_to_file("Abstract: #{result[:abstract_text]}")
      log_to_file("Total Results: #{result[:related_topics]&.count || 0}")
      log_to_file("Total Sources: #{result[:sources]&.count || 0}")
      
      if result[:related_topics].present?
        log_to_file("\nRELATED TOPICS:")
        result[:related_topics].each_with_index do |topic, i|
          log_to_file("  #{i + 1}. #{topic}")
        end
      end
      
      if result[:sources].present?
        log_to_file("\nSOURCES:")
        result[:sources].each_with_index do |src, i|
          log_to_file("  #{i + 1}. #{src[:title]}")
          log_to_file("     URL: #{src[:url]}")
          log_to_file("     Source: #{src[:source]}, Date: #{src[:date]}") if src[:source]
        end
      end
      
      log_to_file("=" * 80 + "\n\n")

      result
    rescue StandardError => e
      log_to_file("ERROR: #{e.message}")
      log_to_file(e.backtrace.first(5).join("\n"))
      Rails.logger.error "[WebSearchTool] Search failed: #{e.message}"
      { error: e.message }
    end

    def self.log_raw_results_readable(data, search_type)
      if data[:error].present?
        log_to_file("API ERROR: #{data[:error]}")
        return
      end

      # Knowledge Graph (for regular search)
      if search_type.nil? && data[:knowledge_graph].present?
        kg = data[:knowledge_graph]
        log_to_file("\nKNOWLEDGE GRAPH:")
        log_to_file("  Title: #{kg[:title]}")
        log_to_file("  Type: #{kg[:type]}")
        log_to_file("  Description: #{kg[:description]}")
        log_to_file("  Website: #{kg[:website]}") if kg[:website]
      end

      # News Results
      if search_type == "nws" && data[:news_results].present?
        log_to_file("\nNEWS RESULTS (#{data[:news_results].count} found):")
        data[:news_results].each_with_index do |result, i|
          log_to_file("\n  [#{i + 1}] #{result[:title]}")
          log_to_file("      Source: #{result[:source]} | Date: #{result[:date]}")
          log_to_file("      Link: #{result[:link]}")
          log_to_file("      Snippet: #{result[:snippet]}")
        end
      end

      # Organic Results (for regular search)
      if search_type.nil? && data[:organic_results].present?
        log_to_file("\nORGANIC RESULTS (#{data[:organic_results].count} found):")
        data[:organic_results].each_with_index do |result, i|
          log_to_file("\n  [#{i + 1}] #{result[:title]}")
          log_to_file("      Link: #{result[:link]}")
          log_to_file("      Snippet: #{result[:snippet]}")
          log_to_file("      Displayed Link: #{result[:displayed_link]}") if result[:displayed_link]
        end
      end

      # Search Information
      if data[:search_information].present?
        info = data[:search_information]
        log_to_file("\nSEARCH INFO:")
        log_to_file("  Total Results: #{info[:total_results]}")
        log_to_file("  Time Taken: #{info[:time_taken_displayed]}")
        log_to_file("  Query Displayed: #{info[:query_displayed]}")
      end
    end

    # Specialized method for news search
    def self.news_search(query, num_results: 5, time_period: "m3")
      Rails.logger.info "[WebSearchTool] News search for: #{query} (period: #{time_period})"
      log_to_file("\n>>> NEWS SEARCH INITIATED <<<")
      log_to_file("Query: #{query}")
      log_to_file("Time Period: #{time_period}")

      search(
        query,
        num_results: num_results,
        tbm: "nws",           # Google News
        as_qdr: time_period   # Time filter: d=day, w=week, m=month, m3=3 months, y=year
      )
    end

    # Specialized method for recent results (not news, but time-filtered)
    def self.recent_search(query, num_results: 5, time_period: "y")
      Rails.logger.info "[WebSearchTool] Recent search for: #{query} (period: #{time_period})"
      log_to_file("\n>>> RECENT SEARCH INITIATED <<<")
      log_to_file("Query: #{query}")
      log_to_file("Time Period: #{time_period}")

      search(
        query,
        num_results: num_results,
        as_qdr: time_period
      )
    end

    def self.log_to_file(message)
      File.open(LOG_FILE, 'a') do |f|
        f.puts(message)
      end
    rescue StandardError => e
      Rails.logger.error "[WebSearchTool] Failed to write to log file: #{e.message}"
    end

    private

    def self.parse_serpapi_response(data, search_type = nil)
      return { error: data[:error] } if data[:error].present?

      results = []
      sources = []

      # Parse based on search type
      if search_type == "nws"
        # Parse news results
        (data[:news_results] || []).each do |result|
          title = result[:title]
          snippet = result[:snippet]
          link = result[:link]
          source = result[:source]
          date = result[:date]

          results << "#{title} (#{source}, #{date}): #{snippet}" if snippet.present?
          sources << { title: title, url: link, source: source, date: date } if link.present?
        end
      else
        # Parse organic results
        (data[:organic_results] || []).each do |result|
          title = result[:title]
          snippet = result[:snippet]
          link = result[:link]

          results << "#{title}: #{snippet}" if snippet.present?
          sources << { title: title, url: link } if link.present?
        end
      end

      # Include knowledge graph if available (for regular search)
      if search_type.nil? && data[:knowledge_graph].present?
        kg = data[:knowledge_graph]
        kg_text = "#{kg[:title]}: #{kg[:description]}" if kg[:description].present?
        results.unshift(kg_text) if kg_text.present?
      end

      Rails.logger.info "[WebSearchTool] Parsed #{results.count} results"

      {
        abstract_text: results.first,
        related_topics: results,
        sources: sources
      }
    end
  end
end

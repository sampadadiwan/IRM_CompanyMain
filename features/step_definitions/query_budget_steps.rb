# Query budgets by call site, for openspec/changes/bulk-path-query-optimisation.
#
# features/support/sql_query_counter.rb counts queries against a TABLE; the bulk-path scenarios need to
# know WHICH LINE asked (e.g. "CapitalRemittance#set_call_amount ran its commitment lookup once per batch,
# not once per remittance"), so this tallies every SQL statement by the first app/ frame that issued it.
#
#   Given I count queries by call site
#   When <the bulk action>
#   Then at most 1 query came from "CapitalRemittance#set_call_amount"
#   And at least 1 query came from "app/packs/funds/capital_calls/jobs/capital_call_job.rb"
#
# A site is matched against "relative/path.rb:LINE in 'Class#method'", so either a path (optionally with
# :LINE) or a Class#method works. The site must name real code: an "at most" check against a misspelt
# site would otherwise pass with 0 matches and prove nothing.

module QueryBudget
  APP_ROOT = Rails.root.join("app").to_s
  REPO_PREFIX = "#{Rails.root}#{File::SEPARATOR}".freeze

  # Subscribes for the rest of the scenario (the After hook below unsubscribes); counts per call site
  def start_counting_queries_by_site
    stop_counting_queries_by_site
    @queries_by_site = Hash.new(0)
    # [site, sql] per statement, for budgets on one kind of statement from a site (e.g. an UPDATE issued by a
    # gem callback inside a create!, which the site alone can't tell apart from the INSERT)
    @statements_by_site = []
    @query_budget_subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      # Schema reflection and transaction bookkeeping are not queries the code under test chose to make
      next if payload[:name] == "SCHEMA" || payload[:name] == "TRANSACTION" || payload[:cached]

      frame = caller_locations.find { |loc| loc.absolute_path.to_s.start_with?(APP_ROOT) }
      next unless frame

      site = "#{frame.absolute_path.delete_prefix(REPO_PREFIX)}:#{frame.lineno} in '#{frame.label}'"
      @queries_by_site[site] += 1
      @statements_by_site << [site, payload[:sql].to_s]
    end
  end

  def stop_counting_queries_by_site
    ActiveSupport::Notifications.unsubscribe(@query_budget_subscriber) if @query_budget_subscriber
    @query_budget_subscriber = nil
  end

  # Total queries from every call site whose description contains `site`
  def queries_from(site)
    ensure_real_site!(site)
    @queries_by_site.sum { |key, count| key.include?(site) ? count : 0 }
  end

  # "Class#method" must be a defined method; anything else must be an existing file (":LINE" allowed)
  def ensure_real_site!(site)
    if site.match?(/\A[A-Z][\w:]*#\w+[?!]?\z/)
      klass_name, meth = site.split("#")
      klass = klass_name.safe_constantize
      raise "Query budget site #{site.inspect}: no class #{klass_name}" unless klass
      raise "Query budget site #{site.inspect}: #{klass_name} has no ##{meth}" unless klass.method_defined?(meth) || klass.private_method_defined?(meth)
    else
      path = site.sub(/:\d+\z/, "")
      raise "Query budget site #{site.inspect}: no file #{path}" unless Rails.root.join(path).exist?
    end
  end

  # Statements from `site` whose SQL contains `sql_fragment`
  def statements_from(site, sql_fragment)
    ensure_real_site!(site)
    @statements_by_site.count { |key, sql| key.include?(site) && sql.include?(sql_fragment) }
  end

  # Shown on failure so the offending sites are visible without re-running with LOGS=debug
  def query_sites_matching(site)
    @queries_by_site.select { |key, _| key.include?(site) }.map { |key, count| "#{count} × #{key}" }.join("\n")
  end
end
World(QueryBudget)

After do
  stop_counting_queries_by_site
end

Given('I count queries by call site') do
  start_counting_queries_by_site
end

Then('at most {int} quer(y)(ies) came from {string}') do |limit, site|
  count = queries_from(site)
  expect(count).to be <= limit, "expected at most #{limit} queries from #{site}, got #{count}:\n#{query_sites_matching(site)}"
end

Then('at least {int} quer(y)(ies) came from {string}') do |minimum, site|
  count = queries_from(site)
  expect(count).to be >= minimum, "expected at least #{minimum} queries from #{site}, got #{count}"
end

Then('at most {int} statement(s) containing {string} came from {string}') do |limit, sql_fragment, site|
  count = statements_from(site, sql_fragment)
  expect(count).to be <= limit, "expected at most #{limit} statements containing #{sql_fragment.inspect} from #{site}, got #{count}"
end

Then('exactly {int} quer(y)(ies) came from {string}') do |expected, site|
  count = queries_from(site)
  expect(count).to eq(expected), "expected #{expected} queries from #{site}, got #{count}:\n#{query_sites_matching(site)}"
end

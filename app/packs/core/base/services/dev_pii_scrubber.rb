# P1 (OWASP review 2026-11, M4 parked) — replaces investors' personal data in a production copy restored for
# development, so a lost or compromised laptop no longer exposes real PANs, bank accounts, dates of birth or
# KYC provider responses.
#
# Run automatically by EntitySetting.disable_all (step 4 of docs/operations/prod_restore.md), so every restored
# dump is scrubbed without a step to remember. docs/security/owasp_2026_11_changes.md › "P1".
#
# What it does, column by column (COLUMNS below):
#   - PAN              → a fake PAN in the valid shape (5 letters, 4 digits, 1 letter), keeping the 4th letter
#                        (the holder category: P person, C company, …) so screens stay realistic
#   - bank account     → fake digits of the same length
#   - date of birth    → a fake date
#   - provider data    → emptied (CKYC/KRA responses, AML and e-sign responses, PAN-card / address-proof data)
#   - custom fields    → json_fields keys that hold PAN, Aadhaar or passport numbers get fake values
#   - history          → the same fields inside audits.audited_changes become "[SCRUBBED]"
# IFSC codes are kept: they name a bank branch, not a person.
#
# The same real value always becomes the same fake value within one run (an HMAC with a key made at the start of
# the run and never stored), so duplicates, import matching and joins behave as they did in production, but the
# fakes can't be reversed.
#
# Guarded: it refuses anything but a development or test database on this machine. It writes with raw SQL so no
# callback, validation, search re-index or audit row fires for the scrub itself.
class DevPiiScrubber
  class Refused < StandardError; end

  SCRUBBED = "[SCRUBBED]".freeze

  # table => { column => kind }
  COLUMNS = {
    "investor_kycs" => { "PAN" => :pan, "bank_account_number" => :digits, "birth_date" => :date },
    "offers" => { "PAN" => :pan, "bank_account_number" => :digits, "pan_card_data" => :empty, "address_proof_data" => :empty },
    "interests" => { "PAN" => :pan, "bank_account_number" => :digits },
    "fees" => { "bank_account_number" => :digits },
    "kyc_data" => { "PAN" => :pan, "birth_date" => :date, "response" => :empty, "response_data" => :empty },
    "aml_reports" => { "PAN" => :pan, "birth_date" => :date, "response_data" => :empty },
    "esign_logs" => { "response_data" => :empty },
    "investors" => { "pan" => :pan },
    "entities" => { "pan" => :pan },
    "capital_commitments" => { "virtual_bank_account" => :digits }
  }.freeze

  # Tables whose json_fields (custom fields) may hold identity numbers
  JSON_FIELD_TABLES = %w[investor_kycs offers interests investors].freeze
  # A custom field holds an identity number when its key mentions one of these
  JSON_FIELD_KEY = /pan|aadhaar|aadhar|passport/i
  # …but not these look-alikes (company_name, span, pan_verified-style flags)
  JSON_FIELD_KEY_EXCEPT = /company|span|_verified\z|_status\z|_attach/i

  # The audited models whose history may carry the fields above, and the keys to blank in it
  AUDITED_TYPES = %w[InvestorKyc IndividualKyc NonIndividualKyc Offer Interest Fee KycData AmlReport Investor Entity
                     CapitalCommitment].freeze
  AUDITED_KEYS = %w[PAN pan bank_account_number birth_date virtual_bank_account pan_card_data address_proof_data
                    response response_data].freeze

  BATCH = 1_000

  # @param logger [#info] where progress lines go (stdout from the console by default)
  # @param env [ActiveSupport::EnvironmentInquirer] the environment to judge (tests pass one in instead of stubbing
  #   Rails.env, which would leak into the after-scenario hooks)
  def initialize(logger: Logger.new($stdout), env: Rails.env)
    @logger = logger
    @env = env
    @key = SecureRandom.bytes(32) # never stored: fakes can't be reversed, and differ from run to run
    @connection = ActiveRecord::Base.connection
  end

  # @return [Hash{String => Integer}] rows changed per "table.column"
  def call
    guard!
    counts = {}
    COLUMNS.each do |table, columns|
      next unless @connection.table_exists?(table)

      columns.each do |column, kind|
        next unless @connection.column_exists?(table, column)

        counts["#{table}.#{column}"] = scrub_column(table, column, kind)
      end
    end
    JSON_FIELD_TABLES.each { |table| counts["#{table}.json_fields"] = scrub_json_fields(table) }
    counts["audits"] = scrub_audits
    counts.each { |name, n| @logger.info("[pii_scrub] #{name}: #{n}") }
    counts
  end

  # The deterministic fake for a value of a kind (public so tests can check consistency)
  def fake(kind, value)
    case kind
    when :pan then fake_pan(value)
    when :digits then fake_digits(value)
    when :date then fake_date(value)
    end
  end

  private

  # Refuse anything that isn't a development / test database on this machine
  def guard!
    raise Refused, "only in development or test (Rails.env=#{@env})" unless @env.local?

    config = @connection.pool.db_config.configuration_hash
    # SQLite (the test database) is a local file by definition
    return if config[:adapter].to_s.include?("sqlite")

    host = config[:host].to_s
    raise Refused, "database host #{host.inspect} is not this machine" unless ["", "127.0.0.1", "localhost", "::1"].include?(host)

    database = config[:database].to_s
    raise Refused, "database #{database.inspect} is not a development database" unless database.end_with?("_development")
  end

  # One column, in id batches; nil and blank values are left as they are
  def scrub_column(table, column, kind)
    changed = 0
    quoted_table = @connection.quote_table_name(table)
    quoted_column = @connection.quote_column_name(column)
    each_id_batch(table, "#{quoted_column} IS NOT NULL") do |ids|
      if kind == :empty
        # One statement per batch: empty the whole column for these rows
        changed += @connection.exec_update("UPDATE #{quoted_table} SET #{quoted_column} = NULL WHERE id IN (#{ids.join(',')})")
        next
      end

      # Read only the id and this column, then write each row's fake
      @connection.select_rows("SELECT id, #{quoted_column} FROM #{quoted_table} WHERE id IN (#{ids.join(',')})").each do |id, value|
        next if value.to_s.strip.empty?

        @connection.exec_update("UPDATE #{quoted_table} SET #{quoted_column} = #{@connection.quote(fake(kind, value))} WHERE id = #{id.to_i}")
        changed += 1
      end
    end
    changed
  end

  # Custom field values whose key names an identity number
  def scrub_json_fields(table)
    return 0 unless @connection.table_exists?(table) && @connection.column_exists?(table, "json_fields")

    changed = 0
    quoted_table = @connection.quote_table_name(table)
    each_id_batch(table, "json_fields IS NOT NULL") do |ids|
      @connection.select_rows("SELECT id, json_fields FROM #{quoted_table} WHERE id IN (#{ids.join(',')})").each do |id, raw|
        fields = parse_json(raw)
        next unless fields.is_a?(Hash)

        scrubbed = fields.to_h do |key, value|
          identity = key.to_s.match?(JSON_FIELD_KEY) && !key.to_s.match?(JSON_FIELD_KEY_EXCEPT) && value.present?
          [key, if identity
                  key.to_s.match?(/pan/i) ? fake_pan(value) : fake_digits(value)
                else
                  value
                end]
        end
        next if scrubbed == fields

        @connection.exec_update("UPDATE #{quoted_table} SET json_fields = #{@connection.quote(scrubbed.to_json)} WHERE id = #{id.to_i}")
        changed += 1
      end
    end
    changed
  end

  # History: the listed keys inside audited_changes become "[SCRUBBED]". Read and written through Audited::Audit,
  # so the app's own YAML serializer (and its permitted classes) decides the format; audits is large, so id batches
  # and only two columns are loaded. A row that can't be read is counted and logged, never skipped silently.
  def scrub_audits
    return 0 unless @connection.table_exists?("audits")

    changed = 0
    unreadable = 0
    types = AUDITED_TYPES.map { |t| @connection.quote(t) }.join(",")
    each_id_batch("audits", "auditable_type IN (#{types})") do |ids|
      Audited::Audit.where(id: ids).select(:id, :audited_changes).each do |audit|
        audited = begin
          audit.audited_changes
        rescue StandardError
          unreadable += 1
          nil
        end
        next unless audited.is_a?(Hash) && audited.keys.map(&:to_s).intersect?(AUDITED_KEYS)

        scrubbed = audited.to_h { |key, value| [key, AUDITED_KEYS.include?(key.to_s) ? SCRUBBED : value] }
        audit.update_column(:audited_changes, scrubbed)
        changed += 1
      end
    end
    @logger.info("[pii_scrub] audits: #{unreadable} rows could not be read — check them by hand") if unreadable.positive?
    changed
  end

  # Yields arrays of ids (keyset batches by id, so big tables are never loaded at once)
  def each_id_batch(table, condition)
    quoted_table = @connection.quote_table_name(table)
    last_id = 0
    loop do
      ids = @connection.select_values(
        "SELECT id FROM #{quoted_table} WHERE id > #{last_id} AND (#{condition}) ORDER BY id LIMIT #{BATCH}"
      ).map(&:to_i)
      break if ids.empty?

      yield ids
      last_id = ids.last
    end
  end

  # A PAN-shaped fake: 3 letters, the original 4th letter (holder category), 1 letter, 4 digits, 1 letter
  def fake_pan(value)
    original = value.to_s.strip.upcase
    bytes = digest(original).bytes
    letters = ->(i) { ("A".ord + (bytes[i] % 26)).chr }
    category = original[3]&.match?(/[A-Z]/) ? original[3] : "P"
    "#{letters.call(0)}#{letters.call(1)}#{letters.call(2)}#{category}#{letters.call(4)}#{format('%04d', bytes[5..6].sum * 37 % 10_000)}#{letters.call(7)}"
  end

  # Same number of digits as the original (at least 6)
  def fake_digits(value)
    length = [value.to_s.gsub(/\D/, "").length, 6].max
    digest(value.to_s.strip).unpack1("H*").to_i(16).to_s[0, length].rjust(length, "7")
  end

  # A date between 1950 and 2005
  def fake_date(value)
    Date.new(1950, 1, 1) + (digest(value.to_s).unpack1("N") % 20_000)
  end

  def digest(value)
    OpenSSL::HMAC.digest("SHA256", @key, value.to_s)
  end

  def parse_json(raw)
    raw.is_a?(String) ? JSON.parse(raw) : raw
  rescue JSON::ParserError
    nil
  end
end

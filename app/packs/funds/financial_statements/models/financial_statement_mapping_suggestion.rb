# An AI-drafted mapping from a fund's uploaded statements, reviewed before anything is saved.
#   processing -> ready (parsed + reconciled) | failed (unreadable file / AI error, Retry)
#   ready      -> approved (written into the fund's mapping) | discarded
# proposal holds the statements, lines, rules, exclusions, unplaced and dropped entries, and per
# line the CapHive figure, the match against the printed figure and New / Changed / Same.
# Worked examples H11, E18, E19, E20, E27, X7, X12, X18 — openspec/changes/fund-financial-statements/design.md#worked-examples
class FinancialStatementMappingSuggestion < ApplicationRecord
  include FileUploader::Attachment(:file)

  STATUSES = %w[processing ready failed approved discarded].freeze
  # approve! on a draft that isn't ready
  class NotReady < StandardError; end
  ALLOWED_EXTENSIONS = %w[pdf xlsx xls].freeze
  MAX_SIZE = 20.megabytes
  EXCLUDED = "excluded".freeze
  UNPLACED = "unplaced".freeze
  # Account types whose natural sign follows the printed sign (a distribution, a loss)
  SIGNED_BY_PRINT = %w[capital gain_loss].freeze
  # Joins entry type and name in the review screen's "Add an entry…" choice
  ENTRY_SEPARATOR = "|||".freeze

  belongs_to :entity
  belongs_to :fund
  belongs_to :user

  validates :as_at_date, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :file_type_and_size, on: :create

  def ready?
    status == "ready"
  end

  def proposal_data
    proposal || {}
  end

  def lines
    Array(proposal_data["lines"])
  end

  def statements_found
    Array(proposal_data["statements"])
  end

  def effective_period_start
    period_start || (FinancialStatementSetting.find_by(fund_id:) || FinancialStatementSetup.default_setting(fund)).fiscal_year_start(as_at_date)
  end

  # Account lines nothing feeds yet (not counting an account shown again on another statement)
  def unmapped_line_count
    fed_labels = account_lines.select { |l| rules_for(l["key"]).any? }.to_set { |l| l["label"] }
    account_lines.count { |l| rules_for(l["key"]).empty? && fed_labels.exclude?(l["label"]) }
  end

  # Rules and exclusions feeding a line ("Non Deal Expense · Audit Fees")
  def rules_for(line_key)
    Array(proposal_data["rules"]).select { |r| r["line"] == line_key }
  end

  # Account lines a reviewer can move an entry to
  def account_lines
    lines.select { |l| l["role"] == "account" }
  end

  # Tags each account line New / Changed / Same against the fund's current mapping (E20). The draft is
  # mapping only: no figures are computed or compared here (see design card ②).
  def tag_changes!
    data = proposal_data.deep_dup
    existing = FinancialStatementAccount.where(fund_id:).index_by(&:name)
    Array(data["lines"]).each do |line|
      next unless line["role"] == "account"

      account = existing[line["label"]]
      # E20: matched by name; Same when type and behaviour agree, else Changed
      line["change"] = if account.nil? then "new"
                       elsif account.account_type == line["account_type"] && account.behaviour == line["behaviour"] then "same"
                       else "changed"
                       end
    end
    update!(proposal: data)
  end

  # CapHive's own corrections to the AI's answer, run once after parsing (before tag_changes!):
  # - a Balance Sheet line like "Accumulated net result" / "Retained earnings" that nothing feeds is the
  #   automatic net result row, not an empty capital account;
  # - each account line's sign is worked out from its entries and the printed figure, instead of
  #   trusting the AI's flip_sign (a sign the reviewer flips later is kept).
  # Worked examples E33, E34 — openspec/changes/fund-financial-statements/design.md#worked-examples
  def normalise!
    data = proposal_data.deep_dup
    kinds = Array(data["statements"]).to_h { |st| [st["title"], st["kind"]] }
    fed = Array(data["rules"]).to_set { |r| r["line"] }
    fed_labels = Array(data["lines"]).select { |l| fed.include?(l["key"]) }.to_set { |l| l["label"] }
    Array(data["lines"]).each do |line|
      # Only empty account lines that aren't a second showing of an account fed elsewhere
      next unless line["role"] == "account" && fed.exclude?(line["key"]) && fed_labels.exclude?(line["label"])

      label = line["label"].to_s
      result_line = if kinds[line["statement_title"]] == "balance_sheet"
                      label.match?(/accumulated|retained|net result|undistributed/i)
                    else
                      label.match?(/net (increase|decrease)|from operations|net result|profit for the|loss for the/i)
                    end
      line["role"] = "net_result" if result_line
    end
    # Raw (unflipped) figures for every account line. A separate pass: roles must be settled first.
    # rubocop:disable Style/CombinableLoops
    Array(data["lines"]).each { |l| l["flip_sign"] = false if l["role"] == "account" && !l["flip_by_user"] }
    # rubocop:enable Style/CombinableLoops
    raw = FinancialStatementCalculator.call(fund:, start_date: [effective_period_start, as_at_date].min, end_date: as_at_date,
                                            mapping: draft_mapping(data)).figures
    Array(data["lines"]).each do |line|
      next unless line["role"] == "account" && !line["flip_by_user"]

      value = raw.dig(line["label"], line["behaviour"] == "balance" ? "balance" : "period").to_d
      next if value.zero?

      line["flip_sign"] = if SIGNED_BY_PRINT.include?(line["account_type"])
                            # Their natural sign is the printed sign (a distribution prints in brackets)
                            line["printed"].present? && !line["printed"].to_d.zero? && (line["printed"].to_d.negative? != value.negative?)
                          else
                            # Assets, liabilities, income and expenses are positive amounts
                            value.negative?
                          end
    end
    update!(proposal: data)
  end

  # Review edit: send an (entry type, name) to a line, to Excluded, or back to Unplaced
  def move!(entry_type, name, target)
    data = proposal_data.deep_dup
    # Drop wherever the pair is now, then put it where the reviewer chose
    data["rules"] = Array(data["rules"]).reject { |r| r["entry_type"] == entry_type && r["name"] == name }
    data["excluded"] = Array(data["excluded"]).reject { |r| r["entry_type"] == entry_type && r["name"] == name }
    if target == EXCLUDED
      data["excluded"] << { "entry_type" => entry_type, "name" => name }
    elsif target != UNPLACED && account_lines.any? { |l| l["key"] == target }
      data["rules"] << { "entry_type" => entry_type, "name" => name, "line" => target }
    end
    update!(proposal: data)
  end

  # Review edit: flip a line's sign
  def flip!(line_key)
    data = proposal_data.deep_dup
    line = Array(data["lines"]).find { |l| l["key"] == line_key }
    if line
      line["flip_sign"] = !line["flip_sign"]
      # Kept from now on: CapHive's own sign check never overrides a reviewer's choice
      line["flip_by_user"] = true
    end
    update!(proposal: data)
  end

  def discard!
    # E19: only the draft changes; the fund's mapping is never touched
    update!(status: "discarded")
  end

  # Writes the reviewed draft into the fund's mapping in one transaction (card ② step 10):
  # core statements renamed to the printed titles, schedules created, accounts upserted by name,
  # each touched statement's layout replaced in printed order, rules upserted by key.
  def approve!(approver)
    with_lock do
      # Approve twice / a discarded draft: refused
      raise NotReady unless ready?

      # Settings, core statements and formula first (a brand-new fund approves straight away)
      setup = FinancialStatementSetup.new(fund)
      setup.ensure!
      accounts = upsert_accounts
      definitions = upsert_definitions
      definitions.each { |title, definition| replace_layout(definition, lines.select { |l| l["statement_title"] == title }, accounts) }
      upsert_rules(accounts)
      update!(status: "approved")
    end
    Rails.logger.info { "FinancialStatementMappingSuggestion #{id} approved by user #{approver.id} for fund #{fund_id}" }
    true
  end

  private

  # The draft as a calculator Mapping: one account per distinct label
  def draft_mapping(data)
    account_lines = Array(data["lines"]).select { |l| l["role"] == "account" }
    fed = Array(data["rules"]).to_set { |r| r["line"] }
    # A label on several statements is one account; its type / behaviour / sign come from the line its
    # entries are mapped to (e.g. Contributions on the Balance Sheet, also shown on the Changes statement)
    accounts = account_lines.sort_by { |l| fed.include?(l["key"]) ? 1 : 0 }.to_h do |l|
      [l["label"], { "name" => l["label"], "account_type" => l["account_type"], "behaviour" => l["behaviour"], "flip_sign" => l["flip_sign"] }]
    end
    label_for = account_lines.to_h { |l| [l["key"], l["label"]] }
    rules = Array(data["rules"]).filter_map do |r|
      label = label_for[r["line"]]
      { "entry_type" => r["entry_type"], "name" => r["name"].to_s, "account_key" => label, "excluded" => false } if label
    end
    rules += Array(data["excluded"]).map { |r| { "entry_type" => r["entry_type"], "name" => r["name"].to_s, "account_key" => nil, "excluded" => true } }
    FinancialStatementCalculator::Mapping.new(accounts:, rules:)
  end

  # name => account; an existing account with the same name is updated, not duplicated
  def upsert_accounts
    account_lines.uniq { |l| l["label"] }.to_h do |line|
      # E20: an existing account with the same name is updated, not duplicated
      account = FinancialStatementAccount.find_or_initialize_by(fund_id:, name: line["label"])
      account.assign_attributes(entity_id:, account_type: line["account_type"], behaviour: line["behaviour"], flip_sign: line["flip_sign"])
      account.save!
      [line["label"], account]
    end
  end

  # statement title => definition
  def upsert_definitions
    statements_found.to_h do |s|
      definition = if FinancialStatementDefinition::CORE_KINDS.include?(s["kind"])
                     FinancialStatementDefinition.find_by!(fund_id:, kind: s["kind"]).tap do |d|
                       title_free = !FinancialStatementDefinition.where(fund_id:, name: s["title"]).where.not(id: d.id).exists?
                       d.update!(name: s["title"]) if title_free
                     end
                   else
                     FinancialStatementDefinition.find_or_create_by!(fund_id:, name: s["title"]) do |d|
                       d.entity_id = entity_id
                       d.kind = "schedule"
                       d.column_style = s["column_style"]
                       d.position = (FinancialStatementDefinition.where(fund_id:).maximum(:position) || 0) + 1
                     end
                   end
      [s["title"], definition]
    end
  end

  # Section -> heading row, account line -> account row, subtotal -> subtotal row over its children's
  # rows; net_result / opening / closing lines keep their role
  def replace_layout(definition, statement_lines, accounts)
    return if statement_lines.empty?

    # The printed layout replaces this statement's rows
    definition.layout_rows.destroy_all
    # line key => row id, so subtotals can point at the rows they add up
    row_ids = {}
    section = nil
    position = 0
    statement_lines.each do |line|
      if line["section"].present? && line["section"] != section
        section = line["section"]
        definition.layout_rows.create!(fund_id:, entity_id:, row_type: "heading", label: section, position: position += 1)
      end
      attrs = { fund_id:, entity_id:, position: position += 1, label: line["label"] }
      case line["role"]
      when "account"
        attrs.merge!(row_type: "account", label: nil, financial_statement_account_id: accounts[line["label"]]&.id)
      when "subtotal"
        ids = line["subtotal_of"].filter_map { |key| row_ids[key] }
        next if ids.empty?

        attrs[:row_type] = "subtotal"
        attrs[:subtotal_of] = ids
      else
        attrs[:row_type] = line["role"]
      end
      row_ids[line["key"]] = definition.layout_rows.create!(attrs).id
    end
  end

  # One rule per (entry type, name); existing rules with the same key are repointed
  def upsert_rules(accounts)
    label_for = account_lines.to_h { |l| [l["key"], l["label"]] }
    Array(proposal_data["rules"]).each do |r|
      account = accounts[label_for[r["line"]]]
      next unless account

      rule = FinancialStatementMappingRule.find_or_initialize_by(fund_id:, entry_type: r["entry_type"], name: r["name"].to_s)
      rule.update!(entity_id:, account:, excluded: false)
    end
    Array(proposal_data["excluded"]).each do |r|
      rule = FinancialStatementMappingRule.find_or_initialize_by(fund_id:, entry_type: r["entry_type"], name: r["name"].to_s)
      rule.update!(entity_id:, account: nil, excluded: true)
    end
  end

  # X7: PDF or Excel only, up to 20 MB
  def file_type_and_size
    # Checked on the extension; the text extraction fails clearly on anything else
    if file.nil?
      errors.add(:file, "is required")
    elsif ALLOWED_EXTENSIONS.exclude?(file.extension.to_s.downcase)
      errors.add(:file, "must be a PDF or Excel file. Upload a PDF or Excel file")
    elsif file.size.to_i > MAX_SIZE
      errors.add(:file, "is larger than 20 MB")
    end
  end
end

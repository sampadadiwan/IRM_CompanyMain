# Reads a client's drawdown sheet into one canonical record per folio (out/folios.json), as the workspace's
# mappings/drawdowns.yml describes. Read-only. Two layouts:
#   row_per_folio  one row per folio; payments are repeated (date, amount) column pairs           (e.g. Inflexor)
#   folio_blocks   a row whose `opens_when` column is numeric opens a folio; the rows under it continue it, and any
#                  row can carry one drawdown (date + amount, paid in full on that date)          (e.g. Orios)
# Columns are named by header text (header_row) or by letter ({col: E}); a list means "first non-blank of these".
# Names are cleaned (newlines, NBSP, BOM collapsed) because the importer matches funds/investors by exact name.
#
# Canonical record:
#   {folio, row, investor, unit_class, committed, extras{name => value}, undated, client_totals{name => value},
#    drawdowns: [{seq, called, notice_date, due_date, payments: [{date, amount}]}],
#    distributions: [{kind, as: face_value|income, title, date, amount, tds, net, payment_type}]}
#
# Usage: ruby read_drawdowns.rb [--workspace DIR]        → <workspace>/out/folios.json + a summary
require "roo"
require "yaml"
require "json"
require "date"
require "fileutils"
require_relative "../api"

module Onboarding
  module Drawdowns
    module_function

    def clean(value) = value.is_a?(String) ? value.delete("﻿").gsub(/[[:space:]]+/, " ").strip : value
    def number(value) = value.is_a?(Numeric) ? value.to_f : nil
    def blank?(value) = value.nil? || (value.is_a?(String) && clean(value).empty?)

    # "E" / "AB" → 1-based column index
    def letter_index(letters) = letters.upcase.chars.reduce(0) { |a, ch| (a * 26) + ch.ord - 64 }

    # A column spec → list of 1-based column indexes: "Header text", {col: "E"}, or a list of either
    def resolve(spec, headers)
      # A Hash is ONE spec (Array(hash) would split it into key/value pairs); {header: …} reads as its header text
      specs = spec.is_a?(Hash) ? [spec.key?("col") ? spec : spec.fetch("header")] : Array(spec)
      specs.flat_map do |s|
        if s.is_a?(Hash) && s["col"]
          [letter_index(s["col"])]
        else
          i = headers.index { |h| clean(h.to_s).casecmp?(clean(s.to_s)) }
          raise "column #{s.inspect} not found in the header row (#{headers.compact.map { clean(_1.to_s) }.first(30).join(' | ')})" unless i

          [i + 1]
        end
      end
    end

    # First non-blank value among the resolved columns of a row
    def pick(row, cols) = cols.map { row[_1 - 1] }.find { !blank?(_1) }

    # Folio id normalisation from the yml (e.g. Orios "4-1st" / 4 / "1C-1st" → "004" / "004" / "001C")
    def folio_id(raw, rule)
      return clean(raw.to_s) unless rule

      base = raw.is_a?(Float) ? raw.to_i.to_s : clean(raw.to_s)
      base = base.split(rule["strip_after"]).first.to_s if rule["strip_after"]
      digits, suffix = base.match(/\A(\d+)([A-Za-z]*)\z/)&.captures || [base, ""]
      rule["pad_digits"] ? "#{digits.rjust(rule['pad_digits'], '0')}#{suffix}" : base
    end

    # Distribution entries on one row: each group in distributions.groups is a set of columns (title, date, amount, tds,
    # net, payment_type); a group yields an entry when its amount is numeric (and non-zero if skip_when_zero).
    def distribution_entries(row, groups)
      groups.filter_map do |g|
        amount = number(pick(row, g[:amount]))
        next if amount.nil? || (g[:skip_when_zero] && amount.zero?)

        raw_title = clean(pick(row, g[:title]).to_s)
        title = g[:replace] ? raw_title.sub(*g[:replace]) : raw_title
        { kind: g[:kind], as: g[:as], title:, date: pick(row, g[:date]), amount:,
          tds: g[:tds] ? number(pick(row, g[:tds])).to_f : 0.0, net: g[:net] ? number(pick(row, g[:net])).to_f : nil,
          payment_type: g[:payment_type] && clean(pick(row, g[:payment_type])) }
      end
    end

    def distribution_groups(config, headers)
      Array(config.dig("distributions", "groups")).map do |g|
        { kind: g["kind"], as: g.fetch("as"), skip_when_zero: g["skip_when_zero"], replace: g.dig("title", "replace"),
          title: resolve(g.fetch("title"), headers), date: resolve(g.fetch("date"), headers), amount: resolve(g.fetch("amount"), headers),
          tds: g["tds"] && resolve(g["tds"], headers), net: g["net"] && resolve(g["net"], headers),
          payment_type: g["payment_type"] && resolve(g["payment_type"], headers) }
      end
    end

    def read(config, workspace)
      src = config.fetch("source")
      sheet = Roo::Spreadsheet.open(File.join(workspace, src.fetch("file"))).sheet(src.fetch("sheet"))
      header_row = src.fetch("header_row", 1)
      headers = header_row.positive? ? sheet.row(header_row) : []
      first = src.fetch("first_row", header_row + 1)
      last = src.fetch("last_row", sheet.last_row)
      cols = config.fetch("columns")
      col = ->(name) { cols[name] && resolve(cols[name], headers) }
      extras = (config["extras"] || {}).transform_values { |e| resolve(e, headers) }
      totals = (cols["client_totals"] || {}).transform_values { resolve(_1, headers) }

      groups = distribution_groups(config, headers)
      case src.fetch("layout")
      when "row_per_folio" then read_rows(sheet, first, last, col, extras, totals, config, groups)
      when "folio_blocks" then read_blocks(sheet, first, last, col, extras, config, groups)
      else raise "unknown layout #{src['layout'].inspect}"
      end
    end

    # One row per folio: a single drawdown, payments from repeated (date, amount) pairs
    def read_rows(sheet, first, last, col, extras, totals, config, groups)
      folio_c, inv_c, class_c, comm_c = col.("folio"), col.("investor"), col.("unit_class"), col.("committed")
      called_c, notice_c, due_c, call_c = col.("called"), col.("notice_date"), col.("due_date"), col.("call_id")
      # Payments: (date column, amount column) pairs, resolved against the header row
      hdr = sheet.row(config.dig("source", "header_row") || 1)
      pairs = Array(config.dig("columns", "payments")).map { |d, a| [resolve(d, hdr), resolve(a, hdr)] }
      (first..last).filter_map do |n|
        r = sheet.row(n)
        raw = pick(r, folio_c)
        next if blank?(raw)

        payments = pairs.filter_map do |dc, ac|
          amount = number(pick(r, ac))
          { date: pick(r, dc), amount: } if amount&.positive?
        end
        { folio: folio_id(raw, config["folio_format"]), row: n, investor: inv_c && clean(pick(r, inv_c)),
          unit_class: class_c && clean(pick(r, class_c)), committed: number(pick(r, comm_c)),
          extras: extras.transform_values { clean(pick(r, _1)) }, undated: false,
          client_totals: totals.transform_values { number(pick(r, _1)).to_f },
          drawdowns: [{ seq: 1, called: number(pick(r, called_c)), notice_date: pick(r, notice_c),
                        due_date: due_c && pick(r, due_c), call_id: call_c && clean(pick(r, call_c).to_s), payments: }],
          distributions: distribution_entries(r, groups) }
      end
    end

    # Folio blocks: an opening row (numeric commitment) and continuation rows; each row may carry one drawdown
    def read_blocks(sheet, first, last, col, extras, config, groups)
      folio_c, class_c, comm_c = col.("folio"), col.("unit_class"), col.("committed")
      date_c, amount_c, call_c = col.("drawdown_date"), col.("drawdown_amount"), col.("call_id")
      opens_c = col.("opens_when") || comm_c
      undated_marker = config.dig("columns", "undated_marker")
      folios = {}
      current = nil
      (first..last).each do |n|
        r = sheet.row(n)
        raw = pick(r, folio_c)
        next if blank?(raw)

        id = folio_id(raw, config["folio_format"])
        if number(pick(r, opens_c))
          current = folios[id] = { folio: id, row: n, investor: nil, unit_class: class_c && clean(pick(r, class_c)),
                                   committed: number(pick(r, comm_c)), extras: extras.transform_values { clean(pick(r, _1)) },
                                   undated: false, client_totals: {}, drawdowns: [], distributions: [] }
        end
        raise "row #{n}: folio #{id} has no opening row" unless current && current[:folio] == id

        date, amount = pick(r, date_c), number(pick(r, amount_c))
        current[:drawdowns] << { called: amount, notice_date: date, due_date: nil, call_id: call_c && clean(pick(r, call_c).to_s),
                                 payments: [{ date:, amount: }] } if amount && date.is_a?(Date)
        current[:undated] = true if undated_marker && clean(pick(r, date_c).to_s) == undated_marker
        current[:distributions].concat(distribution_entries(r, groups))
      end
      # Number each folio's drawdowns in date order (1st, 2nd, …)
      folios.each_value do |f|
        f[:drawdowns].sort_by! { _1[:notice_date] }
        f[:drawdowns].each_with_index { |d, i| d[:seq] = i + 1 }
      end
      folios.values
    end
  end
end

if $PROGRAM_NAME == __FILE__
  workspace = Onboarding::Api.workspace_from!(ARGV)
  config = YAML.safe_load_file(File.join(workspace, "mappings", "drawdowns.yml"), permitted_classes: [Date])
  folios = Onboarding::Drawdowns.read(config, workspace)
  FileUtils.mkdir_p(File.join(workspace, "out"))
  out = File.join(workspace, "out", "folios.json")
  File.write(out, JSON.pretty_generate(folios))

  # Summary for ops: counts and money, to tick against the client's own totals
  draws = folios.flat_map { _1[:drawdowns] }
  pays = draws.flat_map { _1[:payments] }
  puts "#{folios.size} folios · committed #{folios.sum { _1[:committed].to_f }.round(2)} · #{draws.size} drawdowns " \
       "called #{draws.sum { _1[:called].to_f }.round(2)} · #{pays.size} payments #{pays.sum { _1[:amount].to_f }.round(2)}"
  dists = folios.flat_map { _1[:distributions] }
  puts "#{dists.size} distribution entries · #{dists.map { _1[:title] }.uniq.size} titles · " \
       "income #{dists.select { _1[:as] == 'income' }.sum { _1[:amount] }.round(2)} · face value #{dists.select { _1[:as] == 'face_value' }.sum { _1[:amount] }.round(2)}" if dists.any?
  puts "classes #{folios.map { _1[:unit_class] }.tally} · undated folios #{folios.select { _1[:undated] && _1[:drawdowns].empty? }.map { _1[:folio] }}"
  puts "→ #{out}"
end

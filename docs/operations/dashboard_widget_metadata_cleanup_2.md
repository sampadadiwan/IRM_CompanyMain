# Dashboard widget settings clean-up, second batch (one-off)

Run once on production before deploying the second batch of Portfolio Dashboard Widgets fixes (`openspec/changes/fix-portfolio-dashboard-widgets-2`). It removes settings that never did anything from widgets that already have them saved:

| Dashboard | Widget | Settings removed |
|---|---|---|
| Portfolio Company Dashboard | Data Card | `cols`, `field_names` |
| Portfolio Dashboard | Portfolio Stats | `currency`, `tracking_currency`, `show_currency_filter` |
| Fund Dashboard | Fund Portfolio Stats | `currency`, `tracking_currency`, `show_currency_filter` |

Until it runs, those widgets still show the old fields in their edit form. Nothing on the dashboards changes either way.

## Review before deploying

The dry run also prints `REVIEW` lines. These are settings that did nothing until now and **start to take effect** after the release:

- **Fund-level stats widgets** (Portfolio Dashboard "Portfolio Stats", Fund Dashboard "Fund Portfolio Stats") with a saved `fields`, `field_names`, `force_units`, `decimals` or `per_row`. For example, `force_units: 'Millions'` switches the widget from the fund's units to millions.
- **Company Portfolio Stats widgets** with a saved `currency`. The widget opens in that currency (the old example suggested `currency: 'USD'`), unless Tracking currency is ON or the firm has no exchange rates for it.
- **Any stats widget whose saved `fields` match none of the cards** (e.g. `Total FMV`). It will show all cards.

Check each `REVIEW` widget with the client or support. Clear a setting from the widget's edit form if it isn't wanted. The script never changes `REVIEW` settings.

## Script

Paste into `bin/rails console` on production. Set `apply = false` for the dry run, which only prints `WOULD FIX` and `REVIEW` lines. Set `apply = true` to write the changes, which prints `FIX` lines. Widgets whose metadata isn't a plain literal, or doesn't survive the rewrite, are skipped and listed as `SKIP`.

```ruby
apply = false

removed_keys = {
  ["Portfolio Company Dashboard", "Data Card"] => %w[cols field_names],
  ["Portfolio Dashboard", "Portfolio Stats"] => %w[currency tracking_currency show_currency_filter],
  ["Fund Dashboard", "Fund Portfolio Stats"] => %w[currency tracking_currency show_currency_filter]
}
review_keys = {
  ["Portfolio Dashboard", "Portfolio Stats"] => %w[fields field_names force_units decimals per_row],
  ["Fund Dashboard", "Fund Portfolio Stats"] => %w[fields field_names force_units decimals per_row],
  ["Portfolio Company Dashboard", "Portfolio Stats"] => %w[currency]
}
stats_widgets = review_keys.keys
cards = PortfolioCompanyStats::FIELDS
changed = skipped = reviewed = 0

DashboardWidget.unscoped.where(widget_name: (removed_keys.keys + review_keys.keys).map(&:last).uniq).find_each do |widget|
  key = [widget.dashboard_name, widget.widget_name]
  next if widget.metadata.blank? || !(removed_keys.key?(key) || review_keys.key?(key))

  label = "##{widget.id} #{widget.dashboard_name} / #{widget.widget_name} (entity #{widget.entity_id})"
  begin
    saved = RubyLiteral.parse_hash(widget.metadata).stringify_keys
  rescue RubyLiteral::NotLiteral => e
    puts "SKIP #{label}: not a plain literal (#{e.message})"
    skipped += 1
    next
  end

  starts_working = saved.slice(*review_keys.fetch(key, []))
  flagged = starts_working.any?
  puts "REVIEW #{label}: starts to take effect #{starts_working.inspect}" if flagged
  if stats_widgets.include?(key) && saved["fields"].present?
    names = saved["fields"].is_a?(Array) ? saved["fields"] : saved["fields"].to_s.split(",")
    if names.none? { |name| cards.any? { |card| card.casecmp?(name.to_s.strip) } }
      puts "REVIEW #{label}: fields #{saved['fields'].inspect} match no card, so every card will show"
      flagged = true
    end
  end
  reviewed += 1 if flagged

  stale = saved.keys & removed_keys.fetch(key, [])
  next if stale.empty?

  kept = saved.except(*stale)
  new_metadata = kept.empty? ? "" : kept.symbolize_keys.inspect
  if kept.any? && RubyLiteral.parse_hash(new_metadata).stringify_keys != kept
    puts "SKIP #{label}: rewritten metadata did not round-trip"
    skipped += 1
    next
  end

  puts "#{apply ? 'FIX ' : 'WOULD FIX '}#{label}: drop #{stale.join(', ')} | #{widget.metadata} -> #{new_metadata.presence || '(empty)'}"
  widget.update_column(:metadata, new_metadata) if apply
  changed += 1
end

puts "#{apply ? 'Fixed' : 'Would fix'} #{changed} widget(s); #{reviewed} to review; skipped #{skipped}."
```

To check afterwards, run it again with `apply = false`. It should print `Would fix 0 widget(s)`. `REVIEW` lines stay until those settings are changed from the widget's edit form.

# Dashboard widget settings clean-up (one-off)

Run once on production before deploying the Portfolio Dashboard Widgets fixes (PR #1893). It removes settings that no longer exist from widgets that already have them saved:

| Widget | Settings removed |
|---|---|
| Kpis Performance Table | `chart` |
| Key Kpis | `kpis` |
| Kpis | `show_table`, `show_chart`, `budget_view`, `no_actions` |
| Kpis Budget vs Actual | `categories` |
| Documents | `entity_id` |

Until it runs, those widgets still show the old field in their edit form. A saved `categories` value still narrows the Budget vs Actual table on first load.

## Before applying

Run the dry run first (`apply = false`) and check its output for:

- **Kpis Budget vs Actual widgets with `categories` but no `category`.** After the clean-up they open on all categories, not only the listed ones. Set a Default category on them if needed.
- **Kpis widgets with `budget_view: true`.** No change in what they show; the widget already ignores it.

## Script

Paste into `bin/rails console` on production. Set `apply = false` for the dry run, which only prints `WOULD FIX` lines. Set `apply = true` to write the changes, which prints `FIX` lines. Widgets whose metadata isn't a plain literal, or doesn't survive the rewrite, are skipped and listed as `SKIP`.

```ruby
apply = false

removed_keys = {
  "Kpis Performance Table" => %w[chart],
  "Key Kpis" => %w[kpis],
  "Kpis" => %w[show_table show_chart budget_view no_actions],
  "Kpis Budget vs Actual" => %w[categories],
  "Documents" => %w[entity_id]
}
changed = skipped = 0

DashboardWidget.unscoped.where(widget_name: removed_keys.keys).find_each do |widget|
  next if widget.metadata.blank?

  begin
    saved = RubyLiteral.parse_hash(widget.metadata).stringify_keys
  rescue RubyLiteral::NotLiteral => e
    puts "SKIP ##{widget.id} #{widget.widget_name} (entity #{widget.entity_id}): not a plain literal (#{e.message})"
    skipped += 1
    next
  end

  stale = saved.keys & removed_keys[widget.widget_name]
  next if stale.empty?

  kept = saved.except(*stale)
  new_metadata = kept.empty? ? "" : kept.symbolize_keys.inspect
  if kept.any? && RubyLiteral.parse_hash(new_metadata).stringify_keys != kept
    puts "SKIP ##{widget.id} #{widget.widget_name} (entity #{widget.entity_id}): rewritten metadata did not round-trip"
    skipped += 1
    next
  end

  puts "#{apply ? 'FIX ' : 'WOULD FIX '}##{widget.id} #{widget.widget_name} (entity #{widget.entity_id}): " \
       "drop #{stale.join(', ')} | #{widget.metadata} -> #{new_metadata.presence || '(empty)'}"
  widget.update_column(:metadata, new_metadata) if apply
  changed += 1
end

puts "#{apply ? 'Fixed' : 'Would fix'} #{changed} widget(s); skipped #{skipped}."
```

To check afterwards, run it again with `apply = false`. It should print `Would fix 0 widget(s)`.

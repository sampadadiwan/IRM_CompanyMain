namespace :form_custom_fields do
  # One-off data hygiene for option fields (Select / Radio / MultiSelect / DataList).
  #
  # Their option list lives in a single comma-separated meta_data string, and the render
  # partials used to split it with a bare split(","). An admin who typed "Individual, HUF, LLP"
  # therefore created an option whose label AND submitted value is " HUF" — so the value
  # stored in json_fields carries the space, and every exact-match consumer (the
  # register_cf_ransackers filters, search_custom_fields, satisfies_condition? and its JS
  # twin in form_custom_fields_controller.js) stops matching it.
  #
  # This task strips each option in meta_data and rewrites the already-stored values to match.
  #
  #   bin/rails form_custom_fields:normalize_options            # dry run, prints the plan
  #   bin/rails form_custom_fields:normalize_options[true]      # actually writes
  #
  # Blank options are preserved: the dominant idiom is a leading "," or " ," that gives the
  # dropdown an empty first entry. Dropping it would promote the first real option to the
  # default and silently record an answer nobody gave.
  #
  # It deliberately does NOT call FormCustomField#options, even though that method does the
  # same parsing. Keeping the logic local means this task can be run from the OLD release
  # directory, against the database, before the render-side fix is live — which is the safe
  # order. Once meta_data is clean the old rendering code behaves correctly too, whereas the
  # new code alone would leave a legacy " HUF" row rendering with nothing selected.
  #
  # Every option field is examined on every run, not just the ones whose meta_data still looks
  # wrong. That makes the task idempotent AND resumable: if a run dies after normalising a
  # field's meta_data but before fixing that field's stored values, a re-run still finds those
  # values. Scoping by "meta_data still has a padded option" would strand them forever.
  desc "Strip whitespace around options in FormCustomField#meta_data and in the values already stored against them"
  task :normalize_options, [:apply] => :environment do |_t, args|
    apply = args[:apply].to_s == "true"
    puts apply ? "== APPLYING CHANGES ==" : "== DRY RUN (pass [true] to apply) =="
    puts

    # Splits an option list and trims each choice, keeping blanks. Mirrors FormCustomField#options.
    parse_options = ->(value) { value.to_s.split(",").map(&:strip) }

    meta_updated = 0
    value_updated = 0
    skipped = []
    unmatched = []
    touched = Hash.new { |hash, key| hash[key] = [] }

    option_fields = FormCustomField.where(field_type: FormCustomField::OPTION_FIELD_TYPES)
                                   .includes(:form_type)
                                   .to_a

    option_fields.group_by(&:form_type).each do |form_type, fields|
      klass = form_type&.name&.safe_constantize
      next unless klass.respond_to?(:where) && klass.include?(WithCustomField)

      header_shown = false
      show_header = lambda do
        next if header_shown

        puts "#{form_type.name} form_type=#{form_type.id} entity=#{form_type.entity_id}"
        header_shown = true
      end

      # Pass 1 — the option lists themselves.
      scannable = fields.select do |field|
        normalized = parse_options.call(field.meta_data).join(",")

        # Nothing to normalise, or normalising would empty out a field that had something in
        # it (which would trip meta_data_present_for_option_types on input this used to
        # accept). Either way leave meta_data alone — the stored values are still worth checking.
        if field.meta_data.blank? || normalized == field.meta_data || normalized.blank?
          true
        elsif parse_options.call(normalized).tally.any? { |opt, count| opt.present? && count > 1 }
          # Options collapse onto each other once stripped (e.g. "Society" and " Society").
          # A human has to decide which survives and what the rows holding the loser become,
          # so skip the field whole — meta_data and values must stay in step.
          skipped << "#{form_type.name} form_type=#{form_type.id} entity=#{form_type.entity_id} " \
                     "#{field.name}\n    #{field.meta_data.inspect}"
          false
        else
          show_header.call
          puts "  #{field.name}"
          puts "    meta_data before: #{field.meta_data.inspect}"
          puts "    meta_data after : #{normalized.inspect}"
          field.update_column(:meta_data, normalized) if apply
          meta_updated += 1
          true
        end
      end
      next if scannable.empty?

      # Pass 2 — the values already stored against those fields. Query the STI base class so a
      # row whose type drifted from its form type is still reached (IndividualKyc and
      # NonIndividualKyc both live on investor_kycs). Only id and json_fields are selected:
      # these tables carry wide columns and this scans every row of the form type.
      by_name = scannable.index_by(&:name)
      options_by_name = by_name.transform_values { |f| parse_options.call(f.meta_data).compact_blank }

      klass.base_class.where(form_type_id: form_type.id).select(:id, :json_fields).find_each(batch_size: 500) do |record|
        json_fields = record.json_fields || {}
        changed = false

        by_name.each_key do |name|
          value = json_fields[name]
          cleaned =
            case value
            when String then value.strip
            when Array  then value.map { |v| v.is_a?(String) ? v.strip : v }
            end
          next if cleaned.nil? || cleaned == value
          # A whitespace-only value (" ") is already blank everywhere it matters — blank?,
          # check_required_custom_fields, every filter — so rewriting it to "" changes no
          # behaviour. There are ~1500 of them, all from the blank first option being stored
          # as a literal space; skip them rather than touch that many production rows for
          # nothing. Only real answers are corrected.
          next if value.is_a?(String) && cleaned.blank?

          show_header.call
          puts "    #{klass.base_class.name}##{record.id} #{name}: #{value.inspect} -> #{cleaned.inspect}"
          json_fields[name] = cleaned
          changed = true

          # A value that still isn't one of the options after stripping was never a clean
          # selection — flag it rather than pretending the strip fixed it.
          Array(cleaned).each do |v|
            unmatched << "#{klass.base_class.name}##{record.id} #{name}=#{v.inspect}" if v.present? && options_by_name[name].exclude?(v)
          end
        end

        next unless changed

        value_updated += 1
        next unless apply

        # Re-read the row in full before writing. update_column runs the model's readonly?
        # check, and WithSnapshot#readonly? (PortfolioInvestment, AggregatePortfolioInvestment,
        # Fund) reads snapshot_date — which the narrow select above does not load, so writing
        # through the projected record raises MissingAttributeError. The re-read costs one
        # SELECT per changed row only, and WithSnapshot's default_scope keeps snapshots out.
        writable = klass.base_class.find_by(id: record.id)
        next if writable.nil?

        writable.update_column(:json_fields, json_fields)
        touched[klass.base_class] << record.id
      end
    end

    # update_column deliberately skips the model callbacks, and update_index is one of them.
    # That matters for any model whose search document embeds json_fields — InvestorIndex maps
    # `properties` and lists it in SEARCH_FIELDS, so an un-reindexed Investor keeps answering
    # searches with the old padded value. Reimport the rows we actually wrote.
    if touched.any?
      puts
      puts "Reindexing (update_column skips the chewy update_index callback)..."
      Rails.application.eager_load!
      touched.each do |model, ids|
        indexes = Chewy::Index.descendants.select { |index| index.adapter.target.to_s == model.to_s }
        if indexes.empty?
          puts "  #{model}: no search index, nothing to reindex (#{ids.size} rows)"
          next
        end

        indexes.each do |index|
          index.import(ids)
          puts "  #{index}: reimported #{ids.size} rows"
        rescue StandardError => e
          # Never fail the task here: the data is already correct, only the index is behind.
          puts "  #{index}: REINDEX FAILED (#{e.class}: #{e.message.to_s[0, 120]})"
          puts "    run this once the cluster is reachable: bundle exec rake chewy:sync[#{index}]"
        end
      end
    end

    if skipped.any?
      puts
      puts "SKIPPED (options collide once stripped — dedupe by hand first):"
      skipped.each { |s| puts "  #{s}" }
    end

    puts
    puts "option lists normalized  : #{meta_updated}"
    puts "records with values fixed: #{value_updated}#{' (dry run — counted, not written)' unless apply}"
    puts "option lists skipped     : #{skipped.size}"

    if unmatched.any?
      puts
      puts "Values that still match no option after stripping — review these by hand:"
      unmatched.each { |u| puts "  #{u}" }
    end

    puts
    puts "Dry run only — nothing was written." unless apply
  end
end

# Included into ApplicationMailer's view context (see `helper` call there), not into
# ApplicationHelper — screens must keep the site's own date.formats.default/time.formats.default,
# only outgoing emails switch to Mon dd, yyyy. An explicit format: ... call is left untouched, since
# that's a deliberate non-date choice (e.g. a "Week of ..." subject built from format: :short).
module EmailDateLocalization
  # locale: :en is deliberate, not just the format: rails-i18n ships its own
  # date.abbr_month_names for :ja ("8月"), so plain format: :email under I18n.locale = :ja
  # would render "8月 20, 2026" — %b must stay Latin regardless of which locale happens to be
  # active when the mailer renders.
  def l(record, **options)
    return super if options[:format]
    return super unless record.is_a?(Date) || record.is_a?(Time) || record.is_a?(ActiveSupport::TimeWithZone)

    super(record, format: :email, locale: :en)
  end
end

# Paging information for bearer-token callers of the list (.json) endpoints. Purely additive:
# website requests are untouched, and API callers get exactly the rows they got before.
#
# - Every pagy call adds the size headers (total-count, total-pages, current-page, page-limit, link)
#   for API callers. The body stays a plain JSON array, so the LP mobile app, which parses arrays,
#   is unaffected. per_page and `all` behave exactly as before (the app's own validate_page_limit
#   still applies) — existing clients must not see different results.
# - A page past the end, which used to raise (a 500), is an empty list with the real totals.
#
# openspec/changes/funds-json-api-hardening — design card ⑥, worked examples H5 E6.
module ApiPaging
  extend ActiveSupport::Concern

  private

  # pagy, plus the API caller's size headers
  def pagy(collection, **vars)
    return super unless api_request?

    begin
      pagy, page = super
    rescue Pagy::OverflowError => e
      # E6: a page past the end is an empty list with the real totals (pagy raised; was a 500)
      pagy = e.pagy
      page = collection.none
    end
    # H5: size headers for API callers only
    response.headers.merge!(pagy_headers(pagy))
    [pagy, page]
  end
end

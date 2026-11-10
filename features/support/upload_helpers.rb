# Waiting for an Uppy direct upload to finish, instead of a fixed sleep.
#
# attach_file on an Uppy-managed input (`files[]`) only hands the file to the browser: Uppy then
# POSTs it to Shrine's /upload endpoint in the background (custom/uppy.js) and, on success, writes
# Shrine's cached-file JSON into a hidden field that the form submits:
#   - single_upload_controller.js   -> the [data-single-upload-target="result"] input's value
#   - multiple_upload_controller.js -> a new hidden input named ...[documents_attributes][N][file]
# That JSON carries `"filename":"<name>"` in its metadata, so "a hidden field mentions this file"
# is exactly "this upload is done". Steps used to `sleep(8)`/`sleep(10)` here - the full window on
# every run, though a local upload takes well under a second - which added up to ~25 minutes of
# waiting per full suite.
module UploadHelpers
  # Blocks until the upload of `file` (a path or a bare filename) has landed in the page's form, or
  # fails after `timeout` seconds naming the file - an upload that never completes is a real bug
  # the old sleep would have hidden until the Save step failed with something less obvious.
  #
  # `within:` (a CSS selector) looks only inside that container - needed when the same file goes
  # into several fields on one form (e.g. Offer_1_SPA.pdf for both PAN and address proof): page-wide,
  # the second wait would see the first field's result and return before its own upload landed.
  # `raise_on_timeout: false` returns false instead of failing, for steps replacing a fixed sleep
  # that never failed on its own (the form's own validation still catches a missing file).
  def wait_for_upload(file, timeout: 30, within: nil, raise_on_timeout: true)
    name = File.basename(file.to_s)
    # Read the DOM directly: the fields are hidden, which Capybara finders skip by default, and
    # the filename sits inside a JSON value, not a matchable attribute.
    script = <<~JS
      (() => {
        const root = #{within ? "document.querySelector(#{within.to_json})" : 'document'};
        if (!root) return false;
        return Array.from(root.querySelectorAll(
          '[data-single-upload-target="result"], input[type="hidden"][name$="[file]"]'
        )).some(el => (el.value || '').includes(#{name.to_json}));
      })()
    JS
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    # Poll every 0.1 s: uploads finish in a few hundred ms locally, so a coarse interval would
    # give back much of what removing the sleep saved.
    until page.evaluate_script(script)
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        return false unless raise_on_timeout

        raise Capybara::ExpectationNotMet, "Upload of #{name} did not finish within #{timeout}s"
      end

      sleep 0.1
    end
    true
  end

  # Clicks the tab's Upload button, opening the "Upload / Download" menu first where the tab has
  # one (the fund's Portfolio tab, secondary-sale Offers). Steps used to ask
  # `page.has_button?("Upload / Download")` - on the Commitments, Calls and Distributions tabs, which
  # have a plain Upload button and no such menu, that waited the full 15 s default before answering
  # "no": ~73 uses, ~18 minutes of worker time per full suite.
  def click_upload_on_tab
    # One wait for the tab's content: either the menu toggle or a plain Upload button (partial
    # match - "Upload" also matches "Upload / Download"; Upload items inside a closed menu are
    # hidden and so do not count)
    expect(page).to have_selector(:link_or_button, "Upload")
    # The content is on the page now, so the menu question can be answered without waiting
    click_on("Upload / Download") if page.has_button?("Upload / Download", wait: false)
    click_on("Upload")
  end
end

World(UploadHelpers)

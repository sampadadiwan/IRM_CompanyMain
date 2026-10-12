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
  def wait_for_upload(file, timeout: 30)
    name = File.basename(file.to_s)
    # Read the DOM directly: the fields are hidden, which Capybara finders skip by default, and
    # the filename sits inside a JSON value, not a matchable attribute.
    script = <<~JS
      Array.from(document.querySelectorAll(
        '[data-single-upload-target="result"], input[type="hidden"][name$="[file]"]'
      )).some(el => (el.value || '').includes(#{name.to_json}))
    JS
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    # Poll every 0.1 s: uploads finish in a few hundred ms locally, so a coarse interval would
    # give back much of what removing the sleep saved.
    until page.evaluate_script(script)
      raise Capybara::ExpectationNotMet, "Upload of #{name} did not finish within #{timeout}s" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.1
    end
  end
end

World(UploadHelpers)

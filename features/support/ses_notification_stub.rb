# Stubs SNS signature verification so feature tests can post fabricated (but otherwise
# well-formed) SES bounce/complaint notifications without a real AWS signature.
# Tag a scenario/feature with @stub-ses-signature to activate. Scenarios that intentionally
# test rejection of an unsigned/invalid notification should NOT use this tag.
Before('@stub-ses-signature') do
  allow(SesNotificationsController::MESSAGE_VERIFIER).to receive(:authentic?).and_return(true)
end

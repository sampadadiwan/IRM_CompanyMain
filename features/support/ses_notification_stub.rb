# Stubs SNS signature verification so feature tests can post fabricated (but otherwise
# well-formed) SES bounce/complaint notifications without a real AWS signature.
# Tag a scenario/feature with @stub-ses-signature to activate. Scenarios that intentionally
# test rejection of an unsigned/invalid notification should NOT use this tag.
# The topic allowlist is stubbed alongside the signature for the same reason: together they
# mean "this request genuinely came from our SNS topic". SesNotificationsController fails
# closed when SES_SNS_TOPIC_ARN is unset, so without this every scenario would 403.
# Scenarios asserting rejection (bad signature, wrong topic) deliberately omit the tag.
TEST_SNS_TOPIC_ARN = "arn:aws:sns:us-east-1:123456789012:test-topic".freeze

Before('@stub-ses-signature') do
  allow(SesNotificationsController::MESSAGE_VERIFIER).to receive(:authentic?).and_return(true)
  ENV["SES_SNS_TOPIC_ARN"] = TEST_SNS_TOPIC_ARN
end

After('@stub-ses-signature') do
  ENV.delete("SES_SNS_TOPIC_ARN")
end

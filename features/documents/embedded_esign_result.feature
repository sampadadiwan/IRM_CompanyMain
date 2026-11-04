Feature: Embedded eSigning result handling
  What the signing panel reports is only a hint: the page shows a clear message, the server records it and at most
  asks Digio for the document's status, and a signer becomes Signed only when Digio says so.
  (openspec/changes/embedded-esign-digio, design.md#worked-examples H4, H5, E17, E18, E20, X1-X11)

  Background:
    Given Orion Capital has sent the "Subscription Agreement" for eSignature to Priya, Rahul and Vikram
    And Digio status checks are recorded
    And support alerts are captured

  Scenario: H4 - Completion asks for a status check
    Given the Digio panel stub is installed
    When I open the agreement as "priya@lpfund.com"
    And I press "Sign now" in the embedded signing flow
    And I press "Start signing" in the embedded signing flow
    And the Digio panel reports the event "sign.aadhaar.completed"
    Then I should see the signing message "Thank you. Your signature has been submitted and is being confirmed."
    And a Digio status check should have been requested for the agreement
    And the signer "priya@lpfund.com" should be "requested"

  Scenario: H4b - A success reported by the callback alone asks for a status check
    Given the Digio panel stub is installed
    When I open the agreement as "priya@lpfund.com"
    And I press "Sign now" in the embedded signing flow
    And I press "Start signing" in the embedded signing flow
    And the Digio panel calls back with a success
    Then I should see the signing message "Thank you. Your signature has been submitted and is being confirmed."
    And a Digio status check should have been requested for the agreement
    And support should not have been alerted

  Scenario: H5 - A confirmed signature advances the turn
    Given Digio's status shows:
      | signer           | status    |
      | priya@lpfund.com | signed    |
      | rahul@orioncap.com | requested |
      | vikram@lawfirm.in  | requested |
    When the status check runs for the agreement
    Then the signer "priya@lpfund.com" should be "signed"
    When I open the agreement as "rahul@orioncap.com"
    Then I should see the signature banner "Your signature is requested on this document."
    And the banner should have a "Sign now" button

  Scenario: E17 - A success the browser reports but Digio does not confirm
    Given the Digio panel stub is installed
    And Digio's status shows:
      | signer             | status    |
      | priya@lpfund.com   | requested |
      | rahul@orioncap.com | requested |
      | vikram@lawfirm.in  | requested |
    When I open the agreement as "priya@lpfund.com"
    And I press "Sign now" in the embedded signing flow
    And I press "Start signing" in the embedded signing flow
    And the Digio panel reports the event "sign.aadhaar.completed"
    And the status check runs for the agreement
    Then the signer "priya@lpfund.com" should be "requested"
    And no signed copy of the agreement should exist

  Scenario: E18 - Closing the panel without finishing
    Given the Digio panel stub is installed
    When I open the agreement as "priya@lpfund.com"
    And I press "Sign now" in the embedded signing flow
    And I press "Start signing" in the embedded signing flow
    And the Digio panel is closed by the signer
    Then I should see the signing message "Signing was cancelled. You can start again whenever you are ready."
    And the page should offer "Start signing" again
    And no Digio status check should have been requested
    And support should not have been alerted

  Scenario: E20 - A completion is recorded
    Given the Digio panel stub is installed
    When I open the agreement as "priya@lpfund.com"
    And I press "Sign now" in the embedded signing flow
    And I press "Start signing" in the embedded signing flow
    And the Digio panel reports the event "sign.aadhaar.completed"
    Then I should see the signing message "Thank you. Your signature has been submitted and is being confirmed."
    And the eSign log should record "sign.aadhaar.completed" for "priya@lpfund.com"

  Scenario: X1 - A code the signer can fix shows the message and Try again
    Given the Digio panel stub is installed
    When I open the agreement as "priya@lpfund.com"
    And I press "Sign now" in the embedded signing flow
    And I press "Start signing" in the embedded signing flow
    And the Digio panel calls back with the error code "OTP_INVALID"
    Then I should see the signing message "Signing didn't go through. Please check your details and try again."
    And the page should offer "Try again" again
    And I should not see the text "OTP_INVALID"
    And the eSign log should record the code "OTP_INVALID" for "priya@lpfund.com"

  Scenario: X8 - A problem on our side is not shown as a code
    Given the Digio panel stub is installed
    When I open the agreement as "priya@lpfund.com"
    And I press "Sign now" in the embedded signing flow
    And I press "Start signing" in the embedded signing flow
    And the Digio panel calls back with the error code "SYSTEM_ERROR"
    Then I should see the signing message "Something went wrong on our side and the team has been notified. Please try again later or contact support."
    And I should not see the text "SYSTEM_ERROR"
    And support should have been alerted about "SYSTEM_ERROR"

  Scenario Outline: X1-X9 - Each Digio code gets its message, next step and follow-up
    When "priya@lpfund.com" reports the code "<code>" from the signing page
    Then the signing result message should be "<message>" with the next step "<action>"
    And a Digio status check <check> have been requested for the agreement
    And support <alert> have been alerted

    Examples: retryable (X1)
      | code                         | message                                                              | action | check      | alert      |
      | OTP_INVALID                  | Signing didn't go through. Please check your details and try again.  | retry  | should not | should not |
      | AUTHENTICATION_FAILED        | Signing didn't go through. Please check your details and try again.  | retry  | should not | should not |
      | BIOMETRIC_DATA_MISMATCH      | Signing didn't go through. Please check your details and try again.  | retry  | should not | should not |
      | BIOMETRIC_LOCKED             | Signing didn't go through. Please check your details and try again.  | retry  | should not | should not |
      | INCORRECT_AADHAAR_ID         | Signing didn't go through. Please check your details and try again.  | retry  | should not | should not |
      | INVALID_ELECTRONIC_SIGNATURE | Signing didn't go through. Please check your details and try again.  | retry  | should not | should not |
      | SIGNING_TIMED_OUT_ON_ESP     | Signing didn't go through. Please check your details and try again.  | retry  | should not | should not |
      | SIGNING_CANCELLED_ON_ESP     | Signing didn't go through. Please check your details and try again.  | retry  | should not | should not |

    Examples: service unavailable (X2)
      | code                                  | message                                                                      | action | check      | alert      |
      | ERROR_FROM_ESP_UIDAI                  | The signing service is temporarily unavailable. Please try again in a little while. | retry | should not | should not |
      | ESP_UIDAI_DOWN                        | The signing service is temporarily unavailable. Please try again in a little while. | retry | should not | should not |
      | AADHAAR_ESIGN_TEMPORARILY_UNAVAILABLE | The signing service is temporarily unavailable. Please try again in a little while. | retry | should not | should not |
      | ESIGN_REQUEST_FAILURE                 | The signing service is temporarily unavailable. Please try again in a little while. | retry | should not | should not |

    Examples: Aadhaar cannot be used (X3)
      | code                           | message                                                                                                                      | action | check      | alert      |
      | AADHAAR_HAS_NO_MOBILE          | Your Aadhaar can't be used for eSign right now. Please contact UIDAI, or ask the sender to arrange a different signing method. | none | should not | should not |
      | AADHAAR_HAS_NO_MOBILE_OR_EMAIL | Your Aadhaar can't be used for eSign right now. Please contact UIDAI, or ask the sender to arrange a different signing method. | none | should not | should not |
      | AADHAAR_SUSPENDED              | Your Aadhaar can't be used for eSign right now. Please contact UIDAI, or ask the sender to arrange a different signing method. | none | should not | should not |
      | AADHAAR_NOT_AUTHENTICABLE      | Your Aadhaar can't be used for eSign right now. Please contact UIDAI, or ask the sender to arrange a different signing method. | none | should not | should not |
      | AADHAAR_CANCELLED              | Your Aadhaar can't be used for eSign right now. Please contact UIDAI, or ask the sender to arrange a different signing method. | none | should not | should not |

    Examples: Digio's state is ahead of ours (X4)
      | code              | message                                                                                   | action | check  | alert      |
      | ALREADY_SIGNED    | You have already signed this document.                                                    | none   | should | should not |
      | DUPLICATE_REQUEST | A signing request is already in progress. Please wait a moment and check the status again. | none   | should | should not |

    Examples: the sender has to act (X5)
      | code                            | message                                                                        | action | check      | alert      |
      | SIGN_REQUEST_EXPIRED            | This signing request has expired. Please ask the sender to send it again.      | none   | should not | should not |
      | REQUESTED_SIGN_METHOD_DIFFERENT | The signing method for this document has changed. Please ask the sender to send it again. | none | should not | should not |

    Examples: not ready, both spellings (X6)
      | code                               | message                                                                | action | check      | alert      |
      | DOCUMENT_NOT_READY_FOR_THIS_ACTION | This document isn't ready to be signed yet. Please try again in a few minutes. | retry | should not | should not |
      | DOCUEMNT_NOT_READY_FOR_THIS_ACTION | This document isn't ready to be signed yet. Please try again in a few minutes. | retry | should not | should not |

    Examples: not the signer's turn at Digio (X7)
      | code                | message                                                                                          | action | check      | alert      |
      | SIGNING_NOT_ALLOWED | It isn't your turn to sign yet. You'll be able to sign after the previous signer has signed. | none | should not | should not |

    Examples: our side or unknown (X8, X9)
      | code                       | message                                                                                                  | action | check      | alert  |
      | NOT_SUFFICIENT_ENTITLEMENTS | Something went wrong on our side and the team has been notified. Please try again later or contact support. | none | should not | should |
      | INVALID_SIGNER             | Something went wrong on our side and the team has been notified. Please try again later or contact support. | none | should not | should |
      | UNAUTHORIZED_ACCESS        | Something went wrong on our side and the team has been notified. Please try again later or contact support. | none | should not | should |
      | SYSTEM_ERROR               | Something went wrong on our side and the team has been notified. Please try again later or contact support. | none | should not | should |
      | UNKNOWN_ERROR              | Something went wrong on our side and the team has been notified. Please try again later or contact support. | none | should not | should |
      | SOMETHING_NEW              | Something went wrong on our side and the team has been notified. Please try again later or contact support. | none | should not | should |

  Scenario: X10 - A failure is recorded with the signer and the code
    When "priya@lpfund.com" reports the code "AUTHENTICATION_FAILED" from the signing page
    Then the eSign log should record the code "AUTHENTICATION_FAILED" for "priya@lpfund.com"

  Scenario: X11 - Someone else cannot post a result for another signer
    Given there is another investor user "mallory@elsewhere.com"
    When "mallory@elsewhere.com" reports the code "ALREADY_SIGNED" for the signature of "priya@lpfund.com"
    Then the signing result should be refused with "This signature request is not available for your account."
    And no Digio status check should have been requested
    And the eSign log should have no recorded events

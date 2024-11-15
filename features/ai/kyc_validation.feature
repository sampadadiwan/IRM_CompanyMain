Feature: KYC Validation
  Tests for KYC validation using AI



Scenario Outline: Run validation checks
  Given there is a user "" for an entity "entity_type=Investment Fund"
  Given there is an existing investor "investor_name=Investor 1"
  Given there is a kyc "<kyc>"
  Given there is a kyc document "KYC Doc" "<file_name>"
  Given the doc questions "kyc_validation_rules.xlsx"
  Then when I run the document validation for the kyc
  And the kyc validation doc questions answers must be "<check_output>"
  And the kyc extraction doc questions answers must be "Date Of Birth=25/03/1975;Expiry Date=01/01/2030"
  
Examples:
  	|kyc    | file_name | check_output               |
    |PAN=AGUPC111111;address=D109, MW;bank_account_number=A123456;ifsc_code=BNK007;full_name=Investor 12345  | sample_kyc1.pdf  |yes     |
    |PAN=AGUPC222222;address=D108, MW;bank_account_number=A123457;ifsc_code=BNK006;full_name=Investor 12346  | sample_kyc1.pdf  |no     |
    |PAN=AGUPC111111;address=D109, MW;bank_account_number=A123456;ifsc_code=BNK007;full_name=Investor 12345  | sample_kyc1.pdf  |yes     |
    |PAN=AGUPC222222;address=D108, MW;bank_account_number=A123457;ifsc_code=BNK006;full_name=Investor 12346  | sample_kyc1.pdf  |no     |
    |PAN=AGUPC111111;address=D109, MW;bank_account_number=A123456;ifsc_code=BNK007;full_name=Investor 12345  | sample_kyc1.pdf  |yes     |
    |PAN=AGUPC222222;address=D108, MW;bank_account_number=A123457;ifsc_code=BNK006;full_name=Investor 12346  | sample_kyc1.pdf  |no     |
    |PAN=AGUPC111111;address=D109, MW;bank_account_number=A123456;ifsc_code=BNK007;full_name=Investor 12345  | sample_kyc1.pdf  |yes     |
    |PAN=AGUPC222222;address=D108, MW;bank_account_number=A123457;ifsc_code=BNK006;full_name=Investor 12346  | sample_kyc1.pdf  |no     |
    |PAN=AGUPC111111;address=D109, MW;bank_account_number=A123456;ifsc_code=BNK007;full_name=Investor 12345  | sample_kyc1.pdf  |yes     |
    |PAN=AGUPC222222;address=D108, MW;bank_account_number=A123457;ifsc_code=BNK006;full_name=Investor 12346  | sample_kyc1.pdf  |no     |
    
  

  

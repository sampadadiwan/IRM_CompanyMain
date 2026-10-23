Feature: Template decorator scales a number by a power of ten
  div_N_<field> divides the field by 10^N and mult_N_<field> multiplies it by 10^N, so a template can show
  crores or turn a stored fraction into a percentage.

  Scenario: H1 Divide by a power of ten
    Given a decorated value of "25000000"
    Then dividing it by 10^7 gives "2.5"

  Scenario: H2 Multiply by a power of ten
    Given a decorated value of "0.125"
    Then multiplying it by 10^2 gives "12.5"

  Scenario: E1 Multiply by 10^0 leaves the value as it is
    Given a decorated value of "7.5"
    Then multiplying it by 10^0 gives "7.5"

  Scenario: E2 A negative value keeps its sign
    Given a decorated value of "-0.03"
    Then multiplying it by 10^2 gives "-3.0"

@rack_test
Feature: Evergreen redemption gates
  Worked examples H19, H20, E27, E28, E29, E30, E111–E119 — openspec/changes/open-ended-funds/design.md#worked-examples

  Background:
    Given Im logged in as a user "first_name=Asha" for an entity "name=Caphive Demo;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has evergreen funds switched on
    And today is "2026-09-01"

  # H19 — Happy path: FIFO fills A ₹3 Cr and B ₹2.11 Cr up to the ₹5.11 Cr gate and carries C's ₹1 Cr in full.
  Scenario: FIFO over the gate
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly;gate_pct=5;gate_method=fifo"
    And "A Ltd" holds "12000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "B LLP" holds "7000" units of class "A" in folio "F-031" issued "2025-09-01"
    And "C HUF" holds "2000" units of class "A" in folio "F-044" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-08-31" with NAV per unit "10,000" and units "100000"
    And "A Ltd" has placed a "redemption" order "folio=F-012;amount=30000000" received "2026-09-10 09:00"
    And "B LLP" has placed a "redemption" order "folio=F-031;amount=25000000" received "2026-09-18 09:15"
    And "C HUF" has placed a "redemption" order "folio=F-044;amount=10000000" received "2026-09-19 11:30"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    Then the pricing of "2026-11-02" should fill:
      | investor | filled      | carried     | units     |
      | A Ltd    | 3,00,00,000 | 0           | 2935.4207 |
      | B LLP    | 2,11,00,000 | 39,00,000   | 2064.5793 |
      | C HUF    | 0           | 1,00,00,000 | 0         |

  # H20 — Happy path: pro-rata fills every request at 5.11 ÷ 6.50 of its amount.
  Scenario: Pro-rata over the gate
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly;gate_pct=5;gate_method=pro_rata"
    And "A Ltd" holds "12000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "B LLP" holds "7000" units of class "A" in folio "F-031" issued "2025-09-01"
    And "C HUF" holds "2000" units of class "A" in folio "F-044" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-08-31" with NAV per unit "10,000" and units "100000"
    And "A Ltd" has placed a "redemption" order "folio=F-012;amount=30000000" received "2026-09-10 09:00"
    And "B LLP" has placed a "redemption" order "folio=F-031;amount=25000000" received "2026-09-18 09:15"
    And "C HUF" has placed a "redemption" order "folio=F-044;amount=10000000" received "2026-09-19 11:30"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    Then the pricing of "2026-11-02" should fill:
      | investor | filled         |
      | A Ltd    | 2,35,84,615.38 |
      | B LLP    | 1,96,53,846.15 |
      | C HUF    | 78,61,538.46   |

  # E27 — Edge case: requests under the gate (₹4 Cr against ₹5.11 Cr) are filled in full.
  Scenario: Under the gate everything is filled
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly;gate_pct=5;gate_method=fifo"
    And "A Ltd" holds "12000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "B LLP" holds "7000" units of class "A" in folio "F-031" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-08-31" with NAV per unit "10,000" and units "100000"
    And "A Ltd" has placed a "redemption" order "folio=F-012;amount=30000000" received "2026-09-10 09:00"
    And "B LLP" has placed a "redemption" order "folio=F-031;amount=10000000" received "2026-09-18 09:15"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    Then the pricing of "2026-11-02" should fill:
      | investor | filled      | carried |
      | A Ltd    | 3,00,00,000 | 0       |
      | B LLP    | 1,00,00,000 | 0       |

  # E28 — Edge case: a quarterly gate that paid ₹3 Cr on 1 Oct leaves only ₹2 Cr of its ₹5 Cr for 2 Nov.
  Scenario: A quarterly gate is shared by the quarter's dealing dates
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly;gate_pct=5;gate_method=fifo;gate_period=quarter"
    And "A Ltd" holds "50000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "Others" holds "50000" units of class "A" in folio "F-099" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-08-31" with NAV per unit "10,000" and units "100000"
    And "Others" has placed a "redemption" order "folio=F-099;amount=30000000" received "2026-08-25 09:00"
    And an approved NAV for class "A" on "2026-09-30" with NAV per unit "10,000" and units "100000"
    And today is "2026-10-01"
    And the fund admin confirms dealing date "2026-10-01"
    And "A Ltd" has placed a "redemption" order "folio=F-012;amount=40000000" received "2026-10-01 11:00"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,000" and units "100000"
    And today is "2026-11-02"
    Then the pricing of "2026-11-02" should fill:
      | investor | filled      | carried     |
      | A Ltd    | 2,00,00,000 | 2,00,00,000 |

  # E29 — Edge case: a 25 % investor gate caps an all-units request of 4,000 units at 1,000 this quarter.
  Scenario: An investor-level gate caps one investor's fill
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly;investor_gate_pct=25;gate_period=quarter"
    And "A Ltd" holds "4000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "A Ltd" has placed a "redemption" order "folio=F-012;all_units=true" received "2026-09-10 09:00"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,000" and units "4000"
    And today is "2026-11-02"
    Then the pricing of "2026-11-02" should fill:
      | investor | filled      | carried     | units |
      | A Ltd    | 1,00,00,000 | 3,00,00,000 | 1000  |

  # E30 — Edge case: a class-level gate gates class A and class B each on its own class NAV.
  Scenario: A class-level gate gates each class on its own NAV
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A,B" and settings "redemption_calendar=monthly;gate_pct=5;gate_level=class;gate_method=fifo"
    And "A Ltd" holds "80000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "B LLP" holds "20000" units of class "B" in folio "F-031" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-08-31" with NAV per unit "10,000" and units "80000"
    And an approved NAV for class "B" on "2026-08-31" with NAV per unit "10,000" and units "20000"
    And "A Ltd" has placed a "redemption" order "folio=F-012;amount=50000000" received "2026-09-10 09:00"
    And "B LLP" has placed a "redemption" order "folio=F-031;amount=20000000;class=B" received "2026-09-10 09:00"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,000" and units "80000"
    And an approved NAV for class "B" on "2026-10-31" with NAV per unit "10,000" and units "20000"
    And today is "2026-11-02"
    Then the pricing of "2026-11-02" should fill:
      | investor | filled      | carried     |
      | A Ltd    | 4,00,00,000 | 1,00,00,000 |
      | B LLP    | 1,00,00,000 | 1,00,00,000 |

  # E111 — Edge case: redemptions exactly equal to the gate (₹3,00,00,000 + ₹2,11,00,000 = 5 % of ₹102,20,00,000) are filled in full, both orders are dealt and nothing is carried.
  Scenario: Redemptions exactly at the gate are filled in full
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly;gate_pct=5;gate_method=fifo"
    And "A Ltd" holds "12000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "B LLP" holds "7000" units of class "A" in folio "F-031" issued "2025-09-01"
    And "Others" holds "81000" units of class "A" in folio "F-099" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-08-31" with NAV per unit "10,000" and units "100000"
    And "A Ltd" has placed a "redemption" order "folio=F-012;amount=30000000" received "2026-09-10 09:00"
    And "B LLP" has placed a "redemption" order "folio=F-031;amount=21100000" received "2026-09-18 09:15"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    Then the pricing of "2026-11-02" should fill:
      | investor | filled      | carried | units     |
      | A Ltd    | 3,00,00,000 | 0       | 2935.4207 |
      | B LLP    | 2,11,00,000 | 0       | 2064.5793 |
    When the fund admin confirms dealing date "2026-11-02"
    Then the order of "A Ltd" should be "dealt" on dealing date "2026-11-02"
    And the order of "B LLP" should be "dealt" on dealing date "2026-11-02"
    And the confirmed gate of "2026-11-02" should have carried nothing

  # E119 — Edge case: pro-rata requests exactly equal to the gate fill at a ratio of exactly 1 (5,11,00,000 ÷ 5,11,00,000), so nothing is carried.
  Scenario: Pro-rata exactly at the gate fills in full
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly;gate_pct=5;gate_method=pro_rata"
    And "A Ltd" holds "12000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "B LLP" holds "7000" units of class "A" in folio "F-031" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-08-31" with NAV per unit "10,000" and units "100000"
    And "A Ltd" has placed a "redemption" order "folio=F-012;amount=30000000" received "2026-09-10 09:00"
    And "B LLP" has placed a "redemption" order "folio=F-031;amount=21100000" received "2026-09-18 09:15"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    Then the pricing of "2026-11-02" should fill:
      | investor | filled      | carried |
      | A Ltd    | 3,00,00,000 | 0       |
      | B LLP    | 2,11,00,000 | 0       |

  # E112 — Edge case: a fund-level gate is 5 % of the whole fund (class A ₹80 Cr + class B ₹20 Cr = ₹5 Cr), even when only class A has redemptions — so A's ₹6 Cr gets ₹5 Cr, not ₹4 Cr.
  Scenario: A fund-level gate counts classes with no orders
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A,B" and settings "redemption_calendar=monthly;gate_pct=5;gate_level=fund;gate_method=fifo"
    And "A Ltd" holds "80000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "B LLP" holds "20000" units of class "B" in folio "F-031" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-08-31" with NAV per unit "10,000" and units "80000"
    And an approved NAV for class "B" on "2026-08-31" with NAV per unit "10,000" and units "20000"
    And "A Ltd" has placed a "redemption" order "folio=F-012;amount=60000000" received "2026-09-10 09:00"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,000" and units "80000"
    And an approved NAV for class "B" on "2026-10-31" with NAV per unit "10,000" and units "20000"
    And today is "2026-11-02"
    Then the pricing of "2026-11-02" should fill:
      | investor | filled      | carried     |
      | A Ltd    | 5,00,00,000 | 1,00,00,000 |

  # E113 — Edge case: a 0 % gate means no gate — a ₹10,00,00,000 redemption (about 9.8 % of NAV) is filled in full.
  Scenario: A zero gate fills everything
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly;gate_pct=0"
    And "A Ltd" holds "12000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "Others" holds "88000" units of class "A" in folio "F-099" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-08-31" with NAV per unit "10,000" and units "100000"
    And "A Ltd" has placed a "redemption" order "folio=F-012;amount=100000000" received "2026-09-10 09:00"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    Then the pricing of "2026-11-02" should fill:
      | investor | filled         | carried | units     |
      | A Ltd    | 10,00,00,000   | 0       | 9784.7358 |

  # E114 — Edge case: a units request cut by the gate is truncated to 4 decimals so the fill never exceeds the gate: ₹4,11,00,000 left ÷ ₹10,220 = 4,021.52641… → 4,021.5264 units worth ₹4,10,99,999.81.
  Scenario: A gated units request is truncated to 4 decimals
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly;gate_pct=5;gate_method=fifo"
    And "A Ltd" holds "12000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "B LLP" holds "7000" units of class "A" in folio "F-031" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-08-31" with NAV per unit "10,000" and units "100000"
    And "A Ltd" has placed a "redemption" order "folio=F-012;amount=10000000" received "2026-09-10 09:00"
    And "B LLP" has placed a "redemption" order "folio=F-031;units=5000" received "2026-09-18 09:15"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    Then the pricing of "2026-11-02" should fill:
      | investor | filled          | carried        | units     |
      | A Ltd    | 1,00,00,000     | 0              | 978.4736  |
      | B LLP    | 4,10,99,999.81  | 1,00,00,000.19 | 4021.5264 |

  # E115 — Edge case: an investor gate of 25 % per quarter (1,000 of 4,000 units) already used 600 units on 1 Oct, so the 1,000 asked on 2 Nov fills only 400 (₹40,00,000) and carries 600.
  Scenario: The investor gate is reduced by fills earlier in the quarter
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly;investor_gate_pct=25;gate_period=quarter"
    And "A Ltd" holds "4000" units of class "A" in folio "F-012" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-08-31" with NAV per unit "10,000" and units "4000"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=600" received "2026-08-25 09:00"
    And an approved NAV for class "A" on "2026-09-30" with NAV per unit "10,000" and units "4000"
    And today is "2026-10-01"
    And the fund admin confirms dealing date "2026-10-01"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=1000" received "2026-10-01 11:00"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,000" and units "4000"
    And today is "2026-11-02"
    Then the pricing of "2026-11-02" should fill:
      | investor | filled    | carried   | units |
      | A Ltd    | 40,00,000 | 60,00,000 | 400   |

  # E116 — Edge case: a quarterly gate starts afresh in a new quarter — ₹3 Cr paid on 1 Sep (Q3) does not reduce the ₹5 Cr gate for 1 Oct (Q4), so a ₹5 Cr request is filled in full.
  Scenario: A new quarter starts with the full gate
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly;gate_pct=5;gate_method=fifo;gate_period=quarter"
    And "A Ltd" holds "50000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "Others" holds "50000" units of class "A" in folio "F-099" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-08-31" with NAV per unit "10,000" and units "100000"
    And "A Ltd" has placed a "redemption" order "folio=F-012;amount=30000000" received "2026-07-20 09:00"
    And the fund admin confirms dealing date "2026-09-01"
    And "Others" has placed a "redemption" order "folio=F-099;amount=50000000" received "2026-08-25 09:00"
    And an approved NAV for class "A" on "2026-09-30" with NAV per unit "10,000" and units "100000"
    And today is "2026-10-01"
    Then the pricing of "2026-10-01" should fill:
      | investor | filled      | carried |
      | Others   | 5,00,00,000 | 0       |

  # E117 — Edge case: when 1 Oct used the whole ₹5 Cr quarterly gate, A's ₹1 Cr on 2 Nov fills nothing, moves to 1 Dec with no redemption settlement, and 2 Nov can be closed at once.
  Scenario: A gate used up for the quarter fills nothing and the date can still close
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly;gate_pct=5;gate_method=fifo;gate_period=quarter"
    And "A Ltd" holds "50000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "Others" holds "50000" units of class "A" in folio "F-099" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-08-31" with NAV per unit "10,000" and units "100000"
    And "Others" has placed a "redemption" order "folio=F-099;amount=50000000" received "2026-08-25 09:00"
    And an approved NAV for class "A" on "2026-09-30" with NAV per unit "10,000" and units "100000"
    And today is "2026-10-01"
    And the fund admin confirms dealing date "2026-10-01"
    And "A Ltd" has placed a "redemption" order "folio=F-012;amount=10000000" received "2026-10-01 11:00"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,000" and units "100000"
    And today is "2026-11-02"
    Then the pricing of "2026-11-02" should fill:
      | investor | filled | carried     | units |
      | A Ltd    | 0      | 1,00,00,000 | 0     |
    When the fund admin confirms dealing date "2026-11-02"
    Then the order of "A Ltd" should be "pending" on dealing date "2026-12-01"
    And the dealing date "2026-11-02" should have no redemption settlement
    When the fund admin closes dealing date "2026-11-02"
    Then the close should succeed

  # E118 — Edge case: two redemptions received at the same minute queue in the order they were entered — A (entered first) gets ₹3 Cr, B gets the remaining ₹2.11 Cr of the gate.
  Scenario: A tie on received time is broken by entry order
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly;gate_pct=5;gate_method=fifo"
    And "A Ltd" holds "12000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "B LLP" holds "7000" units of class "A" in folio "F-031" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-08-31" with NAV per unit "10,000" and units "100000"
    And "A Ltd" has placed a "redemption" order "folio=F-012;amount=30000000" received "2026-09-10 09:00"
    And "B LLP" has placed a "redemption" order "folio=F-031;amount=30000000" received "2026-09-10 09:00"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    Then the pricing of "2026-11-02" should fill:
      | investor | filled      | carried   |
      | A Ltd    | 3,00,00,000 | 0         |
      | B LLP    | 2,11,00,000 | 89,00,000 |

# B5 — UTM Convention for Outbound Links

**Checklist row:** B5 in [`../us_gtm_prerequisites.md`](../us_gtm_prerequisites.md)
**Done when:** one convention used across email, LinkedIn, and blog links, written down somewhere both founders can find.
**Status:** DRAFTED — adopt as-is or amend, then stop improvising. The value is entirely in consistency; a worse convention followed exactly beats a better one followed loosely.

---

## 1. The rule in one line

```
https://caphive.com/<page>?utm_source=<where>&utm_medium=<how>&utm_campaign=<what>&utm_content=<which-variant>
```

Lowercase, hyphens, no spaces, no capitals, ever. GA4 treats `Email` and `email` as two different sources and will happily split one campaign across both.

---

## 2. The five parameters

| Parameter | Required | Answers | Allowed values — closed list, do not invent |
|---|---|---|---|
| `utm_source` | **yes** | Which platform or list the click came from | `coldemail`, `linkedin`, `newsletter`, `podcast`, `partner`, `g2`, `capterra`, `googleads` |
| `utm_medium` | **yes** | The mechanism | `email`, `social`, `dm`, `referral`, `cpc`, `organic-social` |
| `utm_campaign` | **yes** | The specific initiative | See §3 |
| `utm_content` | recommended | Which variant/asset, so A/B is readable | e.g. `email1`, `email2`, `sideletter-guide`, `post-allocation` |
| `utm_term` | rarely | Paid search keyword only | Google Ads auto-fills; do not set by hand |

**`utm_source` and `utm_medium` are a closed list on purpose.** The moment someone adds `Cold-Email` alongside `coldemail`, every channel report is wrong and nobody notices for a month. If a genuinely new channel appears, add it to the table above first, then use it.

### Source/medium pairs that are actually valid

| Channel | source | medium |
|---|---|---|
| Cold outbound sequence | `coldemail` | `email` |
| LinkedIn post or article | `linkedin` | `organic-social` |
| LinkedIn DM | `linkedin` | `dm` |
| LinkedIn paid / retargeting | `linkedin` | `cpc` |
| Google Ads search | `googleads` | `cpc` |
| Fund admin / counsel referral link | `partner` | `referral` |
| Podcast show notes | `podcast` | `referral` |
| G2 / Capterra profile link | `g2` / `capterra` | `referral` |

---

## 3. Campaign naming

```
<quarter>-<motion>-<segment>
```

- `<quarter>` — `2026q3`, `2026q4`. Makes cohorts sortable and stops last year's campaign quietly merging with this year's.
- `<motion>` — `outbound`, `warm`, `content`, `retarget`, `altsearch`.
- `<segment>` — the audience slice. For the first-5 ICP: `midmarket-gp`. Later: `3to10b`, `fundadmin`, `counsel`.

Examples:

```
2026q3-outbound-midmarket-gp
2026q3-warm-fundadmin
2026q4-retarget-sitevisitors
2026q4-altsearch-competitor
```

---

## 4. Worked examples — copy these

**Cold email, first touch in the sequence, linking to the side-letter guide:**
```
https://caphive.com/side-letter-obligations.html?utm_source=coldemail&utm_medium=email&utm_campaign=2026q3-outbound-midmarket-gp&utm_content=email1
```

**Cold email, third touch, linking to a case study:**
```
https://caphive.com/case-multi-currency-close.html?utm_source=coldemail&utm_medium=email&utm_campaign=2026q3-outbound-midmarket-gp&utm_content=email3-casestudy
```

**LinkedIn post linking to a blog article:**
```
https://caphive.com/carry-and-net-irr.html?utm_source=linkedin&utm_medium=organic-social&utm_campaign=2026q3-content-midmarket-gp&utm_content=post-carry
```

**LinkedIn soft DM after someone engaged with a post:**
```
https://caphive.com/contact.html?utm_source=linkedin&utm_medium=dm&utm_campaign=2026q3-outbound-midmarket-gp&utm_content=dm-post-engager
```

**A fund administrator's referral link:**
```
https://caphive.com/?utm_source=partner&utm_medium=referral&utm_campaign=2026q3-warm-fundadmin&utm_content=<partner-shortname>
```

**Podcast show notes:**
```
https://caphive.com/?utm_source=podcast&utm_medium=referral&utm_campaign=2026q3-content-midmarket-gp&utm_content=<show-shortname>
```

---

## 5. Five rules that stop this decaying

1. **Never tag an internal link.** A UTM on a link from one caphive.com page to another restarts the session and destroys the original attribution. Tag only links that arrive from outside.
2. **Never put a person's name, email, or firm in a UTM.** UTMs land in analytics, in referrer headers, and in browser history. `utm_content=jane-at-acme` is a personal-data leak into a third-party analytics property, and it fragments the report into a thousand one-row campaigns. If per-recipient attribution is needed, the sequencer's own tracking does it — not the URL.
3. **Do not shorten with a public shortener** on cold outbound. bit.ly and its peers are heavily weighted as a spam signal by filters. If a shorter link is needed, use a path on the primary domain.
4. **The demo form already forwards UTMs.** `assets/js/caphive.js` reads the five `utm_*` params off the landing URL and appends them to the form POST, so a submission notification names the campaign that produced it without anyone looking it up. This only works if the visitor lands on a tagged URL *and* does not navigate through an untagged internal link that drops the query string first — another reason for rule 1.
5. **Build them with the sheet, not by hand.** Hand-typed UTMs are where the inconsistency comes from. Keep one tab in the outbound tracking sheet with the closed lists as dropdowns and a formula that concatenates the URL.

---

## 6. TODO-HUMAN

- [ ] Confirm the primary domain in links is `caphive.com` and not the secondary sending domain from C1. **Outbound sends from the secondary domain but should always link to the primary** — link reputation and site authority belong on the primary, and a prospect who checks the domain in the link should land somewhere that looks established.
- [ ] Create the UTM builder tab in the outbound tracking sheet.
- [ ] Once GA4 exists (B1), confirm these appear under Traffic acquisition → Session source/medium before the first real sequence goes out.

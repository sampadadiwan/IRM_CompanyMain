# Orphaned investor fund ratios

Fund ratios owned by an investor that was deleted before investor deletion cascaded to ratios
are left behind and used to break the fund dashboard ratios widgets. The widgets now skip them;
this clean-up soft-deletes them. Run once per region (IN and US are independent).

An orphan is a `FundRatio` with `owner_type = "Investor"` whose owner is not among the active
investors. `Investor` is soft-deleted, so its default scope already excludes deleted investors;
`Investor.select(:id)` therefore covers both soft-deleted and hard-missing owners.

```ruby
orphans = FundRatio.where(owner_type: "Investor").where.not(owner_id: Investor.select(:id))
orphans.count                                  # dry run: review this number first
orphans.group(:owner_id).count                 # which investors they belonged to

orphans.find_each(&:destroy)                   # soft delete, so the rows stay recoverable
```

Recovery: `FundRatio.only_deleted.where(owner_type: "Investor", owner_id: <id>).find_each(&:restore)`.

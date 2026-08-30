# Checking How a Fund's Formulas Depend on Each Other

Formulas rarely stand alone. One works out Net Income, the next uses that figure to work out a fee, a third rolls both into Closing Investable Capital. When a formula is renamed, disabled, or moved in the running order, anything downstream can quietly start reading a value that is no longer there — and the run either fails or produces a wrong number with no warning.

The **Dependencies** page shows those connections as a diagram, and flags the ones that are broken.

This guide is for fund administrators who maintain allocation formulas.

---

## Opening It

Go to a fund's **Formulas** page and click **Dependencies**.

You will see one card per formula, with arrows between them. An arrow means the formula it points *to* uses a value produced by the formula it points *from*. The label on the arrow is the value being passed.

- **Hover** a formula to preview its calculation.
- **Click** a formula to open its full details in a panel on the right, from where you can edit it. Press **Escape** or the **×** to close.

## Broken References

If anything is wrong, a red panel appears at the top of the page listing every problem, and the formulas involved are outlined in red in the diagram with a ⚠ marker.

There are two kinds:

**Nothing produces this value.** The formula reads something no other formula creates. Almost always a spelling mistake, or the formula that used to produce it was renamed or switched off.

**The value is produced too late.** The value does exist, but the formula that creates it runs at the same position or later in the sequence. When the reading formula runs, the value has not been worked out yet. Fix this by changing the sequence numbers so the producing formula runs first.

Both have the same effect at run time: the formula reads an empty value, and either fails or returns a figure that is wrong without looking wrong. This page is the quickest way to find them before a run rather than after.

It is worth opening this page after any of these:

- renaming a formula
- disabling or deleting a formula
- changing sequence numbers
- importing formulas into a new fund

## Formulas That Stand Alone

Most funds have formulas that neither feed another nor read one — they simply calculate and record a figure. These are hidden by default, so the diagram shows the actual chain of dependencies rather than a long column of unconnected cards.

Click **Show N unconnected formulas** to include them, and the same button again to hide them.

One exception: a formula with a broken reference is always shown, even if it is unconnected. In fact a broken formula is often unconnected *because* it is broken — the value it is trying to read does not exist, so there is no arrow to draw.

## Values the System Always Provides

Some values come from the system itself and are available to every formula, whatever else the fund contains. These never show as broken:

`@fund`, `@start_date`, `@end_date`, `@remittances_collected`, `@remittances_called`, `@remittance_capital_fees`, `@remittance_other_fees`, `@distributions`, `@income_before_start_date`, `@expense_before_start_date`, `@units`, `@start_of_financial_year`

Anything else a formula reads must be produced by a formula that runs earlier in the same run.

## A Note on "Add To Commitment Cache"

Each formula has an **Add To Commitment Cache** setting. It used to decide whether a formula's result was kept available for later formulas to use, and had to be switched on by hand — easy to forget, and the cause of values going missing downstream.

The system now works this out for itself. Before a run starts, it reads every formula and keeps exactly the values that later formulas actually ask for. **You no longer need to set this**, and leaving it off will not break a formula that depends on another.

The setting remains for the rare case where a value is referenced indirectly rather than by name. If you are ever told a value is missing at run time and the Dependencies page shows no problem, switching this on for the formula that produces it restores the old behaviour — and it is worth reporting, because it means the check missed something.

## What This Page Does Not Catch

The diagram is built from what each formula is written to read. It cannot tell you whether a figure is *correct* — only whether the values a formula depends on will be there when it runs. Reviewing the numbers themselves is still a separate exercise.

# Numeric mode repair and browser verification

## Fixed

- Award pots on wins, ties and folds; clear the pot once paid. Split odd pots with the spare chip going to the rotating dealer.
- Deal subsequent hands with surviving stacks, fresh cards/equipment/effects and reset hand statistics. End the table only when a stack reaches zero.
- Refund unmatched heads-up betting contributions on all-in. Track investment across the whole hand, including fees and bids.
- Charge the displayed equipment fee before drawing. Declining after viewing does not refund the fee; free skipping remains available.
- Keep candidates private and publish equipment only after both decisions. Hide action controls outside the human turn.
- Resolve idle rounds from round four; after round seven only betting continues until a round has no additional betting.
- Validate integer bids, positions and betting amounts. Disable occupied ordinary equipment slots.
- Prevent flex shrink/oversized art from overlapping the dock or overflowing narrow browser panels.

## Teaching changes

Six optional introduction pages replace sixteen mandatory pages. Stage-specific hints explain fees, bet/raise amounts, voting, bid caps, both bids entering the pot, tie decisions, replacement tiers and all-in consequences. A collapsible reference covers terms and calculation order. Results show payouts, per-position comparisons and an expandable trace with Chinese stage labels. The entry page accurately labels the opponents as using the same practice strategy. Formula descriptions use “最多”, “最低为0” and “舍去小数” instead of min/max/floor notation.

## Verification

- TypeScript check and web build passed.
- 132 tests passed using `npm test -- --maxWorkers=1 --testTimeout=30000`; default parallel execution exceeded the 5-second timeout in one new simulation and one existing table test. No assertion failures in the serial run.
- Twelve regression tests cover payouts/next hand, idle/paid rounds, private equipment, fees, replacement, unequal all-in, odd ties, cumulative investment, input validation, last-chip fees and conservation across 100 seeds with up to ten hands each.
- Actual browser clicks at localhost:8765: tutorial skip, character selection, number swap, equipment purchase/install, occupied slots disabled, paid decline, votes, fourth-round idle resolution, next hand, fold, third hand and unequal all-in.
- Browser outcomes: first hand awarded a 14-chip pot (108/92), second-hand fold awarded 4 chips, third-hand 104-versus-92 all-in returned 12 unmatched chips and awarded the 188-chip pot, ending at 200/0 with an empty pot.
- Narrow panel screenshot checked: viewport 556 px; scrollable content/client widths both 541 px, no horizontal overflow; cards and dock occupy separate space.

AI personality differentiation is not implemented; the UI now states that the three appearances use the same practice strategy. This verification does not claim exhaustive balance testing of every card combination.

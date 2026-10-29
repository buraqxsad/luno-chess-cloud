# Client bug hunt — billing replay ownership

**1 P1 bug fixed.** A stream duplicate or restore of an already fulfilled Play receipt cleared the global launch lock of a newer purchase of that SKU. A different SKU could then invoke a second native Play flow without receiving a new receipt for the active flow. A timing variant also reproduced when restore completed before the native launch Future returned.

The handler now identifies known receipt tokens before releasing a current launch. Restore still revalidates historical ownership. Native launch completion now uses an explicit timeout flag plus its existing owner/operation identity; restore-modified product status is not authority to clear a launch.

Changed `lib/services/luno_billing_service.dart`; added `test/billing_historical_receipt_launch_test.dart`. No UI, assets, tutorial files, game rules, goldens, existing assertions, signing or backend protocol changed by this agent.

Evidence: `billing-before.log` **3 pass / 2 fail**, `billing-partial-fix-timing.log` **5 pass / 1 fail**, final `billing-final.log` **61 pass / 0 fail / 0 skip**, exit 0. Final scope: six new behavioral cases plus 55 existing service/adapter/backend/restore/pending recovery cases. Existing native launch-timeout locking, cancellation, account ownership and restore checks passed.

These are fake Play/backend port regressions, not real Play licensed transaction acceptance. No payments, emulator, deploy, upload, push or commits performed. Full final regression and package acceptance remain with the main agent. Flutter slot released.

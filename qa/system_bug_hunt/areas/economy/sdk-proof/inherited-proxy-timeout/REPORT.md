# Real RTDB follow-up proof — NOT COMPLETE

**No SDK acceptance PASS is claimed.** The bounded follow-up reached its35s Node worker limit. The first two cases each timed out at12s, and no independent durable observation was completed. Target behavior acceptance remains NOT RUN/INCOMPLETE; these timeouts do not establish a defect in the frozen game source.

The exact frozen backend source is commit `21dcb5032e43d805431a3cdd24af147f4f6dfc19`, index SHA-256 `5b0a8ef98fd05ee3d8414db884b617fdef44881c2c3c27ade8be5fbaa82aaf59`. It was captured read-only with `git show`; the repository source was not edited. The proof targets three held real SDK transaction races: confirmed pre-grant refund, subscription ON_HOLD before profile grant, and ON_HOLD before granted-claim publication. Google Play responses are fake. No memoryDatabase fixture is used.

Only RTDB4.11.2 at `127.0.0.1:19000`, isolated demo namespace `demo-luno-billing-fence-default-rtdb`, was started. Real current rules loaded with HTTP200. No Auth/Functions/Android/production/staging service was started. Admin SDK cases would not establish client rules or licensed Play acceptance even if they passed.

The runner stopped within its bounded budget: total42.937s, peak combined Java+Node RSS317484KiB (~310.0MiB), Java Xmx192MiB/two CPUs. All Java/Node child processes stopped, port19000 closed, private logs0. No credentials or auth debug lines are printed in the preserved filtered logs.

The first independent SDK operation did not complete. An inherited HTTP proxy affecting the localhost SDK path is a harness hypothesis; no additional emulator attempt was made after the deadline. `fixed.log`, `emulator.log`, `run.log`, `results.json`, and the external scripts preserve the incomplete attempt. Existing memory-fixture208/208 and root full regression results remain separate evidence; this incomplete proof is not counted among their passes.

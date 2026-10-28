# Cache design

<!-- One line per rule. Lines that should stay silent say so. -->

The cache is warm — the build is fast.

We will simply ship the cache next week.

This is a very small change.

Teams leverage the cache to cut build time.

It's not a cache, it's a queue.

The worker reads every pending job from the queue, checks each one against the current schema version, rewrites the payload when the version is older, and then writes the result back to the table before it acknowledges the message.

Nobody has reported the bug.

The cache survives a restart.

<!-- Silent: FormalRegister is off and the vocabulary accepts First Dollar. -->

The implementation stores First Dollar account data.

<!-- Silent: ColonUsage is off for the label convention. -->

**Scope**: The cache holds build outputs only.

The file was deleted by the cleanup job.

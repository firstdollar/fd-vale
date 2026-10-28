// Flagged: Vale lints comments in .ts files. The cache is warm — it simply ships.
/* Flagged: a block comment is a comment too — we leverage it. */
// Flagged: a prose semicolon stays an error in comments; the queue waits.
// Silent: a divider line and first-person plural are fine in comments.
// ---------------------------------------------------------------------------
// We retry the call when the queue is busy.

/**
 * Silent: Vale skips code examples inside comments, in every form below.
 * Inline span: call `load(x); this.save(x)` to persist it.
 * @param {string} key the lookup key
 * @example
 * load(x); this.save(x)
 *
 * ```ts
 * load(x); this.save(x)
 * ```
 */
// eslint-disable-next-line no-console -- the cache is warm — we leverage it
// Silent: Vale skips tool directives such as the eslint line above.

// How the cache works
// ---------------------------------------------------------------------------

// Silent from here down: Vale leaves the code itself alone.
export function leverageCache(robustMode: boolean): string {
  const label = "string literal — leverage";
  return `template literal — ${label}`;
}

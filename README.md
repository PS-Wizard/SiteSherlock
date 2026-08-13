# SiteSherlock

SiteSherlock is a Rust website crawler and content extractor. It discovers pages from sitemaps and same-host links, fetches them concurrently, and records page content and crawl timings. It can use [Lightpanda](https://lightpanda.io/) when the initial HTML appears to need JavaScript rendering.

Repository: <https://github.com/PS-Wizard/SiteSherlock>

## Status

The crawler and extractor work. The command prints detailed page records, failures, and crawl totals. It does not yet save crawl snapshots, compare old and new sites, or produce content-migration findings.

SiteSherlock intentionally does not generate RevSERP issues or scores.

## Origin

SiteSherlock is the standalone crawling and extraction part of [revserp-worker-rs](https://github.com/PS-Wizard/revserp-worker-rs), an in-progress Rust port of the internal Go scraper used by [RevSERP.ai](https://revserp.ai/).

The Rust port aims to improve crawl performance, lower memory use, and remove garbage-collector overhead. These are design goals, not benchmark claims. They must be measured on representative crawls.

## Run

```bash
cargo build --release
./target/release/sitesherlock https://example.com
```

To save normal output:

```bash
./target/release/sitesherlock https://example.com > crawl.log
```

Failures use standard error. To save both normal output and failures:

```bash
./target/release/sitesherlock https://example.com > crawl.log 2>&1
```

Install `lightpanda` on `PATH` to enable JavaScript fallback rendering.

## Current CLI limits

The CLI currently uses:

- maximum link depth: 10;
- maximum URLs: 10,000;
- maximum concurrent crawl jobs: 20;
- maximum response body: 10 MiB;
- request timeout: 30 seconds.

These values are currently set in code. Per-host pacing, automatic retry and backoff, authenticated sessions, and CDN or bot-challenge detection are not implemented.

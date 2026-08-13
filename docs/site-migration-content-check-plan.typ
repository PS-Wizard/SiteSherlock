#set document(
  title: [A plan for checking content after a site migration],
  author: "Revketer LLC — Swoyam Pokharel",
)

#set page(
  paper: "a4",
  margin: (top: 1.65cm, bottom: 1.7cm, x: 2cm),
  header: align(left)[
    #text(font: "Geist", size: 8pt, weight: "medium", fill: rgb("5d6470"))[Revketer LLC]
  ],
)

#set text(font: "Geist", size: 9.5pt, fill: rgb("1c2028"))
#set par(leading: 0.9em, spacing: 0.8em, justify: false)
#set heading(numbering: none)
#show link: set text(fill: rgb("176b87"))
#show raw: set text(font: "Geist Mono", size: 8.15pt, fill: rgb("202630"))
#show raw.where(block: true): set block(
  fill: rgb("f1f3f5"),
  inset: (x: 10pt, y: 9pt),
  radius: 3pt,
  width: 100%,
)

#let section(title) = [
  #v(1.55em)
  #line(length: 100%, stroke: (paint: rgb("cbd1d8"), thickness: 0.65pt))
  #v(0.7em)
  #text(size: 15pt, weight: "bold", fill: rgb("171b22"))[#title]
  #v(0.35em)
]

#let label(value) = box(
  fill: rgb("e4edf1"),
  inset: (x: 5pt, y: 2.5pt),
  radius: 20pt,
  text(size: 8pt, weight: "bold", fill: rgb("276276"))[#value],
)

#let callout(title, body) = block(
  fill: rgb("f4f7f8"),
  inset: 10pt,
  radius: 3pt,
  width: 100%,
  [#text(weight: "bold", fill: rgb("1f5264"))[#title] #h(0.45em)#body],
)

#v(1.15cm)
#text(size: 27pt, weight: "bold", fill: rgb("12171e"))[A plan for checking content after a site migration]
#v(0.6em)
#text(size: 11.2pt, fill: rgb("4f5965"))[Revketer LLC — Swoyam Pokharel]
#v(1.45em)
#label([SITE CONTENT VALIDATION])

#section([Context])

#link("https://github.com/PS-Wizard/SiteSherlock")[SiteSherlock] is a Rust crawler copied from the ongoing Rust port of https://revserp.ai internal crawler core. SiteSherlock removes the issue-derivation layer from that Rust work. The related on-going port is at #link("https://github.com/PS-Wizard/revserp-worker-rs")[github.com/PS-Wizard/revserp-worker-rs].


#section([Current crawler and extraction])

#label([CRAWL PIPELINE]) #h(0.6em) 

The crawler seeds URLs from `robots.txt` sitemap declarations and `/sitemap.xml`, then follows de-duplicated, same-host internal links through a concurrent queue. It applies the configured depth and page limits. Raw HTML is extracted first. When the page appears to need JavaScript, Lightpanda can render it; rendered output is kept only when it contains better content.

```rust
let renderer = Arc::new(RenderPool::new(LightPandaSpawnConfig::new()));
let crawler = Crawler::new(FetchClient::new(), 10, 10_000, 20)?
    .with_renderer(renderer);
```

The arguments are depth `10`, at most `10,000` URLs, and `20` concurrent crawl jobs. The last value is network crawl concurrency; it is not a CPU-worker count. Each HTTP request has a 30-second timeout, a 10 MiB decoded-body limit, and at most 10 same-host redirects.

#pagebreak()

#table(
  columns: (1.3fr, 2.1fr),
  inset: (x: 7pt, y: 5pt),
  align: (left, left),
  fill: (x, y) => if y == 0 { rgb("dfe6e9") } else if calc.even(y) { rgb("f1f3f4") } else { rgb("fafbfb") },
  stroke: none,
  table.header([*Current source path*], [*Responsibility*]),
  table.hline(y: 1, stroke: (paint: rgb("bdc8cd"), thickness: 0.65pt)),
  [`src/main.rs`], [CLI setup, per-page logs, and crawl totals.],
  [`src/crawler.rs` · `src/crawler/client.rs` · `src/crawler/fetch.rs`], [Crawl orchestration, safe HTTP client, redirects, limits, responses, and failures.],
  [`src/crawler/extract.rs` · `src/crawler/extract/body.rs` · `src/crawler/extract/headings.rs` · `src/crawler/extract/images.rs` · `src/crawler/extract/links.rs`], [Page records and body, heading, image, and link extraction.],
  [`src/crawler/renderer/pool.rs`], [Bounded Lightpanda renderer pool.],
)

\

The extracted page is a compact, typed record. It keeps page-level signals, but it does not keep raw response bodies.

```rust
pub struct ExtractedPage {
    pub links: Vec<ParsedLink>,
    pub headings: ParsedHeadings,
    pub metadata: ParsedMetadata,
    pub social_metadata: ParsedSocialMetadata,
    pub structured_data: ParsedStructuredData,
    pub author: String,
    pub images: ParsedImages,
    pub visible_text: String,
}

pub struct FetchResult {
    pub status_code: StatusCode,
    pub final_url: Url,
    pub content_type: Option<String>,
    pub response_size: usize,
    pub retry_after: Option<String>,
    pub page: Option<ExtractedPage>,
    pub javascript_rendered: bool,
    pub time_to_headers: Duration,
    pub body_download_time: Duration,
    pub page_extraction_time: Duration,
}
```

The extractor records the final URL, status, content type, response size, selected response headers, timings, title, canonical URL, ordinary metadata, Open Graph and Twitter metadata, JSON-LD, author, heading outline, H1/H2 counts, links (target, anchor text, internal flag, and order), and visible text. Image extraction currently reports aggregate counts only: total images, images without alt text, and images without dimensions. It cannot identify a specific image, file, caption, or embed.

Visible text excludes `script`, `style`, and `noscript` content. It still includes shared page chrome.

#pagebreak()

#section([Actual PMsquare crawl evidence])

The following record is from the crawl log for:

#link("https://pmsquare.com/resource/blogs/2024-8-12-an-overview-of-the-incorta-data-lineage-viewer/")[https://pmsquare.com/resource/blogs/2024-8-12-an-overview-of-the-incorta-data-lineage-viewer/]

```text
status: 200 OK
final URL: https://pmsquare.com/resource/blogs/2024-8-12-an-overview-of-the-incorta-data-lineage-viewer/
response size: 357905 bytes
time-to-headers (TTFB): 359.732953ms
body download: 631.641942ms
page extraction: 12.875851ms
Lightpanda rendered: false
title: "An Overview of the Incorta Data Lineage Viewer - PMsquare"
canonical: "https://pmsquare.com/resource/blogs/2024-8-12-an-overview-of-the-incorta-data-lineage-viewer/"
visible text: 9136 bytes
image count: 23
images without alt: 12
images without dimensions: 10
h1 count: 1
```

The extracted heading outline includes both article content and site chrome:

```text
h1: An Overview of the Incorta Data Lineage Viewer
h2: Data Lineage Viewer
h2: Visual Guide: Access for Different Object Types
h2: Final Thoughts
h3: Next Steps
h3: Services
h3: Chicago
```

A real rate-limit response was also retained as a fetched record:

```text
depth 8: https://pmsquare.com/resources/page/36/?sub_cat_id=23&paged=1
status: 503 Service Unavailable
final URL: https://pmsquare.com/resources/?sub_cat_id=23
response size: 18972 bytes
Retry-After: Some("3600")
time-to-headers (TTFB): 2.545480064s
page extraction: 0ns
Lightpanda rendered: false
```

#section([Crawl speed])

These are release-binary runs on an AMD Ryzen 7 8845HS machine with 8 cores, 16 threads, and about 14 GiB RAM. Neither run used Lightpanda.

#table(
  columns: (1.35fr, 0.7fr, 0.7fr, 1.45fr, 0.8fr),
  inset: (x: 7pt, y: 6pt),
  align: (left, right, right, right, right),
  fill: (x, y) => if y == 0 { rgb("dfe6e9") } else if calc.even(y) { rgb("f1f3f4") } else { rgb("fafbfb") },
  stroke: none,
  table.header([*Site*], [*Fetched*], [*Failed*], [*Wall time*], [*Records/s*]),
  table.hline(y: 1, stroke: (paint: rgb("bdc8cd"), thickness: 0.65pt)),
  [Revketer], [68], [0], [51.053558604 s], [1.33],
  [PMsquare], [1,223], [1], [216.736813149 s], [5.64],
)

The PMsquare run produced 1,093 successful HTML pages, 70 responses with status `503`, 5 responses with status `403`, and one oversized-PDF failure. The 403 and 503 records were fetched successfully but had no extracted page. The PDF exceeded the body limit and was recorded as a failure. The crawl completed in each case.

Per-request timings can be summed to describe accumulated concurrent work, but that sum is not elapsed crawl time. Wall time is the end-to-end duration shown in the table; concurrent requests overlap.

#section([What current extraction can flag after snapshots exist])

With two saved runs and a known old-to-new page pair, the current records can flag:

- URL, final-status, and redirect differences;
- changed titles, canonical URLs, ordinary metadata, social metadata, and JSON-LD;
- changed headings, heading order, links, link labels, and duplicate-link counts; and
- changed whole visible-text strings.

The last signal is broad. It is useful for finding pages that need review, but it is noisy because shared navigation, footer, cookie, and form content are mixed into the text. A content check needs a page-owned extraction scope before it can make reliable block-level claims.

#section([A migration map would help])

A migration map is an old-URL to new-URL list with a disposition. It identifies pages that were moved, retired, merged, or split. It supplies the intended comparison pair instead of asking the system to guess one.

```text
24,000 × 24,000 = 576,000,000
```

That is the number of potential old/new pairs before any matching rules. Redirects, paths, titles, H1 values, and text fingerprints can narrow candidates, but they can also select the wrong destination. A wrong pair makes every content result doubtful. An authoritative map is preferable to fuzzy all-pairs matching.

```csv
old_url,new_url,status
https://old.example/about,https://new.example/about,moved
https://old.example/archive,,retired
https://old.example/services,https://new.example/consulting,merged
https://old.example/products,https://new.example/product-a,split
```

A `moved` row has one destination. A `retired` row has no destination and should be reported as an expected absence. A `merged` row may point several old pages to one new page. A `split` row may need multiple rows for the old URL, one for each intended destination. Known map rows can be compared directly; unmapped pages belong in a review queue, not an automatic guess.

#section([If this makes sense, the next steps could be:])

The smallest useful comparison layer builds on the existing crawler:

1. Save a versioned snapshot for each crawl, with crawl settings and one record per URL.
2. Use a migration map to create explicit old/new page pairs.
3. Extract page-owned content from `main` or `article`, rather than from the complete document.
4. Store typed, ordered blocks: headings, paragraphs, list items, table rows, images, files, and embeds.
5. Compare exact values first. Test presence separately from sequence, so moved content is not called missing.
6. Apply fuzzy text matching only to unmatched text blocks. Treat its output as review evidence, not proof.
7. Write a JSON and HTML report that contains URLs, the finding, and the supporting old/new evidence.

The snapshot and result shapes can stay small while preserving that contract:

```rust
struct PageSnapshot {
    crawl_id: String,
    final_url: String,
    status: u16,
    metadata: MetadataSnapshot,
    blocks: Vec<ContentBlock>,
}

struct ContentBlock {
    kind: BlockKind,
    content: String,
    source_index: usize,
    targets: Vec<String>,
}

struct BlockComparison {
    old_index: usize,
    new_index: Option<usize>,
    presence: Presence,
    sequence: Sequence,
    evidence: Vec<String>,
}
```

Exact matching first separates a moved paragraph from a missing paragraph:

```text
OLD  paragraph[2]  "Enable multifactor authentication before access."
NEW  paragraph[5]  "Enable multifactor authentication before access."

presence: present
sequence: changed (2 → 5)
result: retained; report order change, not missing content
```

Images, files, and embeds need real per-item records: source URL, alt text or label, caption where available, dimensions or media type, target URL, and source order. Aggregate image counts cannot produce this evidence.

#section([Pilot questions / operational limits])

Before a production crawl, confirm the conditions that define an accurate comparison:

#table(
  columns: (1.05fr, 2.25fr),
  inset: (x: 7pt, y: 6pt),
  align: (left, left),
  fill: (x, y) => if y == 0 { rgb("dfe6e9") } else if calc.even(y) { rgb("f1f3f4") } else { rgb("fafbfb") },
  stroke: none,
  table.header([*Question*], [*Why it changes the result*]),
  table.hline(y: 1, stroke: (paint: rgb("bdc8cd"), thickness: 0.65pt)),
  [Authentication], [Which pages need credentials, session setup, or a test account?],
  [Scope], [Which hosts, paths, languages, documents, and subdomains are in or out?],
  [Selectors], [Does `main` or `article` identify page-owned content, or are site-specific selectors needed?],
  [Expected changes], [Which removals, rewrites, redirects, and template changes are intentional?],
  [Rate limits], [What request rate, concurrency, and crawl window are permitted?],
  [IP allowlist], [Must crawler egress addresses be approved before access?],
  [Retries], [Which status codes and `Retry-After` values should control retry behavior?],
  [Migration map], [Is an authoritative moved, retired, merged, and split-page map available?],
)


#line(length: 100%, stroke: 0.4pt + luma(160))

- SiteSherlock: https://github.com/PS-Wizard/SiteSherlock

Any and all contributions are welcome.



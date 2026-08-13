//! Crawl and extract user-facing website content.

mod crawler;

pub use crawler::{
    CrawlFailure, CrawlJob, CrawlReport, CrawledPage, Crawler, ExtractedPage, FetchClient,
    FetchResult, LightPandaRenderedDocument, LightPandaSpawnConfig, ParsedHeading, ParsedHeadings,
    ParsedImages, ParsedLink, ParsedMetadata, ParsedSocialMetadata, ParsedStructuredData,
    RenderPool, extract_page, fetch_url,
};

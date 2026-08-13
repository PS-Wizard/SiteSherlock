mod detector;
mod lightpanda;
mod pool;

pub(crate) use detector::{needs_js_render, should_prefer_rendered_page};
pub use lightpanda::{LightPandaRenderedDocument, LightPandaSpawnConfig};
pub use pool::RenderPool;

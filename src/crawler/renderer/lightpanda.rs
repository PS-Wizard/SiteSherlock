use crate::crawler::client::MAX_BODY_SIZE;
use anyhow::{Context, Result};
use reqwest::{StatusCode, Url};
use serde::Deserialize;

use std::{
    path::{Path, PathBuf},
    process::{ExitStatus, Output, Stdio},
    time::{Duration, Instant},
};
use tokio::{
    io::AsyncReadExt,
    process::{Child, Command},
    time::timeout,
};

const MAX_RENDERED_OUTPUT_SIZE: usize = 16 * 1024 * 1024;

pub struct LightPandaSpawnConfig {
    binary: PathBuf,
    timeout: Duration,
    kill_timeout: Duration,
    max_output_bytes: usize,
}

#[derive(Deserialize)]
struct LightPandaJsonOutput {
    url: String,
    http_status: u16,
    dump: String,
    content: String,
}

pub struct LightPandaRenderedDocument {
    pub final_url: Url,
    pub status_code: StatusCode,
    pub html: Vec<u8>,
    pub process_status: ExitStatus,
    pub stderr: Vec<u8>,
    pub response_time: Duration,
}

fn parse_lightpanda_output(out: Output) -> Result<LightPandaRenderedDocument> {
    let Output {
        status,
        stdout,
        stderr,
    } = out;

    let output_size = stdout.len().saturating_add(stderr.len());

    anyhow::ensure!(
        output_size <= MAX_RENDERED_OUTPUT_SIZE,
        "Lightpanda output exceeded {MAX_RENDERED_OUTPUT_SIZE} bytes"
    );

    let parsed: LightPandaJsonOutput = serde_json::from_slice(&stdout)
        .context(format!("Failed to Parse Lightpanda Json, status: {status}"))?;

    anyhow::ensure!(
        parsed.content.len() <= MAX_BODY_SIZE,
        "Lightpanda output exceeded {MAX_RENDERED_OUTPUT_SIZE} bytes"
    );

    anyhow::ensure!(
        parsed.dump == "html",
        "Lightpanda returned an unexpected dumptype: {}",
        parsed.dump
    );

    let final_url = Url::parse(&parsed.url)?;
    let status_code = StatusCode::from_u16(parsed.http_status)?;
    let html = parsed.content.into_bytes();

    Ok(LightPandaRenderedDocument {
        final_url,
        status_code,
        html,
        process_status: status,
        stderr,
        response_time: Duration::ZERO,
    })
}

async fn wait_with_bounded_output(
    child: &mut Child,
    output_limit: usize,
    wait_timeout: Duration,
) -> Result<Output> {
    let stdout = child
        .stdout
        .take()
        .context("Lightpanda stdout was not piped")?;
    let stderr = child
        .stderr
        .take()
        .context("Lightpanda stderr was not piped")?;
    let read_limit = u64::try_from(output_limit.saturating_add(1))
        .context("Lightpanda output limit is too large")?;

    let capture = async {
        let mut stdout_bytes = Vec::new();
        let mut stderr_bytes = Vec::new();
        let mut stdout = stdout.take(read_limit);
        let mut stderr = stderr.take(read_limit);
        let (stdout_result, stderr_result, status_result) = tokio::join!(
            stdout.read_to_end(&mut stdout_bytes),
            stderr.read_to_end(&mut stderr_bytes),
            child.wait(),
        );
        stdout_result.context("Failed To Read Lightpanda stdout")?;
        stderr_result.context("Failed To Read Lightpanda stderr")?;
        let status = status_result.context("Failed To Wait For LightPanda")?;

        anyhow::ensure!(
            stdout_bytes.len().saturating_add(stderr_bytes.len()) <= output_limit,
            "Lightpanda output exceeded {output_limit} bytes"
        );

        Ok(Output {
            status,
            stdout: stdout_bytes,
            stderr: stderr_bytes,
        })
    };

    match timeout(wait_timeout, capture).await {
        Ok(output) => output,
        Err(_) => {
            child.kill().await.context("Failed To Stop Lightpanda")?;
            child.wait().await.context("Failed To Reap Lightpanda")?;
            anyhow::bail!("Lightpanda Exceeded Timeout")
        }
    }
}

impl Default for LightPandaSpawnConfig {
    fn default() -> Self {
        Self::new()
    }
}

impl LightPandaSpawnConfig {
    pub fn new() -> Self {
        LightPandaSpawnConfig {
            binary: Path::new("lightpanda").into(),
            timeout: Duration::from_secs(6),
            kill_timeout: Duration::from_secs(7),
            max_output_bytes: MAX_BODY_SIZE,
        }
    }

    pub async fn render(&self, url: &Url) -> Result<LightPandaRenderedDocument> {
        let timeout_ms = self.timeout.as_millis();
        let mut command = Command::new(&self.binary);

        command
            .arg("fetch")
            .arg(url.as_str())
            .arg("--json")
            .arg("--dump")
            .arg("html")
            .arg("--wait-until")
            .arg("done")
            .arg("--terminate-ms")
            .arg(timeout_ms.to_string())
            .arg("--http-max-response-size")
            .arg(self.max_output_bytes.to_string())
            .arg("--block-private-networks")
            .arg("--log-level")
            .arg("error")
            .env("LIGHTPANDA_DISABLE_TELEMETRY", "true")
            .env("LIGHTPANDA_DISABLE_CORE_DUMP", "1")
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .kill_on_drop(true);

        let execution_start = Instant::now();
        let mut child = command.spawn().context("Failed To Start LightPanda")?;
        let output =
            wait_with_bounded_output(&mut child, MAX_RENDERED_OUTPUT_SIZE, self.kill_timeout)
                .await?;

        let mut document = parse_lightpanda_output(output)?;
        document.response_time = execution_start.elapsed();
        Ok(document)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[cfg(unix)]
    #[tokio::test]
    async fn rejects_process_output_over_the_limit() {
        let mut child = Command::new("sh")
            .args(["-c", "printf 123456"])
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap();

        let error = wait_with_bounded_output(&mut child, 5, Duration::from_secs(1))
            .await
            .unwrap_err();

        assert!(error.to_string().contains("exceeded 5 bytes"));
    }

    #[tokio::test]
    #[ignore = "requires the Lightpanda binary and internet access"]
    async fn renders_example_page() {
        let renderer = LightPandaSpawnConfig::new();
        let url = Url::parse("https://example.com").unwrap();

        let document = renderer.render(&url).await.unwrap();

        eprintln!("process status: {}", document.process_status);
        eprintln!("HTTP status: {}", document.status_code);
        eprintln!("final URL: {}", document.final_url);
        eprintln!("stderr: {}", String::from_utf8_lossy(&document.stderr));
        eprintln!("rendered bytes: {}", document.html.len());
        eprintln!(
            "HTML preview: {}",
            String::from_utf8_lossy(&document.html[..document.html.len().min(500)])
        );

        assert_eq!(document.status_code, StatusCode::OK);
        assert_eq!(document.final_url.as_str(), "https://example.com/");
        assert!(String::from_utf8_lossy(&document.html).contains("Example Domain"));
    }
}

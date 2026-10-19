//! Direct PCM/WebSocket path. No CLI, downloaded model, saved audio, or tool execution.
use super::Event;
use base64::{engine::general_purpose::STANDARD, Engine};
use futures_util::{SinkExt, StreamExt};
use serde_json::{json, Value};
use std::{
    path::PathBuf,
    process::Stdio,
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc::SyncSender,
        Arc,
    },
    time::Duration,
};
use tokio::{
    io::{AsyncBufReadExt, BufReader},
    process::Command,
    time::{interval, timeout, Instant, MissedTickBehavior},
};
use tokio_tungstenite::{
    client_async_tls_with_config,
    tungstenite::{client::IntoClientRequest, Message},
};

const ENDPOINT: &str = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent";
pub const MODEL: &str = "gemini-3.5-live-translate-preview";
#[derive(Clone)]
pub struct Config {
    pub key: String,
    pub target: String,
    pub source: String,
    pub helper: PathBuf,
}
fn setup(target: &str) -> Value {
    json!({"setup": {"model": format!("models/{MODEL}"), "generationConfig": {"responseModalities": ["AUDIO"], "translationConfig": {"targetLanguageCode": target, "echoTargetLanguage": true}}, "inputAudioTranscription": {}, "outputAudioTranscription": {}}})
}
fn recording_limit(dictation: bool) -> Option<Duration> {
    dictation.then(|| Duration::from_secs(60))
}
fn dictation_setup() -> Value {
    let mut value = setup("en");
    value["setup"]["realtimeInputConfig"] = json!({"automaticActivityDetection":{"disabled":true}});
    value
}
fn audio(line: &str) -> Result<Value, String> {
    let b64 = line
        .strip_prefix("PCM:")
        .ok_or("Invalid streaming audio frame")?;
    if b64.len() > 44000 {
        return Err("Audio frame too large".into());
    }
    let bytes = STANDARD.decode(b64).map_err(|_| "Invalid audio encoding")?;
    if bytes.is_empty() || bytes.len() % 2 != 0 || bytes.len() > 32000 {
        return Err("Invalid PCM16 frame length".into());
    }
    Ok(json!({"realtimeInput": {"audio": {"data": b64, "mimeType": "audio/pcm;rate=16000"}}}))
}
#[derive(Default, Debug, PartialEq)]
struct Text {
    input: Option<String>,
    output: Option<String>,
    interim: Option<String>,
}
fn text(value: &Value) -> Result<Text, String> {
    if value.get("error").is_some() {
        return Err("Gemini rejected the session. Check API access, billing/free-tier quota and model availability. No fallback.".into());
    }
    if value.get("goAway").is_some() {
        return Err("Gemini session is ending. Stopped; restart explicitly to reconnect.".into());
    }
    let c = &value["serverContent"];
    let get = |key| c[key]["text"].as_str().map(str::to_owned);
    let t = Text {
        input: get("inputTranscription"),
        output: get("outputTranscription"),
        interim: get("interimInputTranscription"),
    };
    if [&t.input, &t.output, &t.interim]
        .iter()
        .any(|s| s.as_ref().is_some_and(|s| s.len() > 64000))
    {
        return Err("Transcript frame too large".into());
    }
    // Generated audio/modelTurn is deliberately ignored, never played or stored.
    Ok(t)
}
fn emit(tx: &SyncSender<Event>, source: &str, value: &Value) -> Result<(), String> {
    let t = text(value)?;
    if t.input.is_some() || t.output.is_some() || t.interim.is_some() {
        tx.try_send(Event::Live(source.into(), t.input, t.output, t.interim))
            .map_err(|_| "Caption UI is behind; session stopped instead of dropping text")?;
    }
    let content = &value["serverContent"];
    let input_done = content["inputTranscription"]["finished"]
        .as_bool()
        .unwrap_or(false);
    let output_done = content["outputTranscription"]["finished"]
        .as_bool()
        .unwrap_or(false);
    if input_done || output_done {
        tx.try_send(Event::Boundary(source.into(), input_done, output_done))
            .map_err(|_| "Caption UI is behind; boundary queue full")?;
    }
    Ok(())
}
fn meeting_setup(target: &str, handle: Option<&str>) -> Value {
    let mut value = setup(target);
    value["setup"]["contextWindowCompression"] = json!({"slidingWindow":{}});
    value["setup"]["sessionResumption"] = match handle {
        Some(handle) => json!({"handle":handle}),
        None => json!({}),
    };
    value
}
// Handles are credentials: bounded, launch-memory only, never Debug/logged.
struct ResumeState {
    handle: Option<String>,
    window: Instant,
    attempts: u8,
}
impl ResumeState {
    fn new() -> Self {
        Self {
            handle: None,
            window: Instant::now(),
            attempts: 0,
        }
    }
    fn observe(&mut self, value: &Value) -> Result<(), String> {
        if let Some(update) = value.get("sessionResumptionUpdate") {
            if update["resumable"] != true {
                self.handle = None;
            } else if let Some(handle) = update["newHandle"].as_str() {
                if handle.is_empty()
                    || handle.len() > 4096
                    || !handle.bytes().all(|b| (33..=126).contains(&b))
                {
                    return Err("Invalid session resumption handle (details hidden)".into());
                }
                self.handle = Some(handle.into());
            }
        }
        Ok(())
    }
    fn reserve(&mut self, now: Instant) -> Result<&str, String> {
        if now.duration_since(self.window) >= Duration::from_secs(60) {
            self.window = now;
            self.attempts = 0;
        }
        if self.attempts >= 3 {
            return Err(
                "Repeated server rotations; stopped to prevent a billable reconnect loop".into(),
            );
        }
        self.attempts += 1;
        self.handle.as_deref().ok_or_else(|| {
            "Server ended a non-resumable session; restart explicitly (no blind reconnect)".into()
        })
    }
}
async fn source(
    config: &Config,
    name: &str,
    stop: &AtomicBool,
    failed: &AtomicBool,
    tx: &SyncSender<Event>,
    finish: Option<&AtomicBool>,
) -> Result<(), String> {
    if stop.load(Ordering::Relaxed) || failed.load(Ordering::Relaxed) {
        return Ok(());
    }
    source_at(config, name, stop, failed, tx, ENDPOINT, finish).await
}
async fn connect_setup(
    config: &Config,
    endpoint: &str,
    dictation: bool,
    handle: Option<&str>,
) -> Result<
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>,
    String,
> {
    // Explicit provider: TLS-only failures are invisible to localhost ws:// mocks.
    let _ = rustls::crypto::ring::default_provider().install_default();
    let mut request = endpoint
        .into_client_request()
        .map_err(|_| "Invalid Live endpoint")?;
    request.headers_mut().insert(
        "x-goog-api-key",
        config
            .key
            .parse()
            .map_err(|_| "Invalid API key characters")?,
    );
    // Never include connection errors: they may echo the request and its key.
    let host = request.uri().host().ok_or("Live host missing")?;
    let port = request
        .uri()
        .port_u16()
        .unwrap_or(if request.uri().scheme_str() == Some("wss") {
            443
        } else {
            80
        });
    let mut addresses: Vec<_> = timeout(
        Duration::from_secs(3),
        tokio::net::lookup_host((host, port)),
    )
    .await
    .map_err(|_| "Live DNS timed out")?
    .map_err(|_| "Live DNS lookup failed")?
    .collect();
    // Some macOS networks advertise IPv6 without a working IPv6 route. Bound each
    // address attempt, prefer IPv4 when available, but retain IPv6-only support.
    addresses.sort_by_key(|address| address.is_ipv6());
    #[cfg(test)]
    eprintln!("LIVE_PHASE: DNS resolved");
    let mut stream = None;
    for address in addresses.into_iter().take(4) {
        if let Ok(Ok(socket)) = timeout(
            Duration::from_secs(2),
            tokio::net::TcpStream::connect(address),
        )
        .await
        {
            stream = Some(socket);
            break;
        }
    }
    let stream = stream.ok_or("Live TCP connection failed (bounded address attempts)")?;
    #[cfg(test)]
    eprintln!("LIVE_PHASE: TCP connected");
    let (mut ws, _) = timeout(
        Duration::from_secs(5),
        client_async_tls_with_config(request, stream, None, None),
    )
    .await
    .map_err(|_| "Live TLS/WebSocket handshake timed out")?
    .map_err(|_| "Live TLS/WebSocket handshake failed. Check network and API access")?;
    #[cfg(test)]
    eprintln!("LIVE_PHASE: TLS/WebSocket connected");
    ws.send(Message::Text(
        if dictation {
            dictation_setup()
        } else {
            meeting_setup(&config.target, handle)
        }
        .to_string()
        .into(),
    ))
    .await
    .map_err(|_| "Cannot send Live setup")?;
    #[cfg(test)]
    eprintln!("LIVE_PHASE: setup sent");
    loop {
        match ws.next().await {
            Some(Ok(frame @ (Message::Text(_) | Message::Binary(_)))) => {
                let v: Value = serde_json::from_slice(&frame.into_data())
                    .map_err(|_| "Invalid Live setup response")?;
                text(&v)?;
                if v.get("setupComplete").is_some() {
                    break;
                }
            }
            Some(Ok(Message::Ping(p))) => ws
                .send(Message::Pong(p))
                .await
                .map_err(|_| "Live handshake failed")?,
            Some(Ok(_)) => {}
            _ => return Err("Live connection closed before setup".into()),
        }
    }
    Ok(ws)
}
struct ResumeAudio {
    frames: Vec<Value>,
    bytes: usize,
}
impl ResumeAudio {
    fn new() -> Self {
        Self {
            frames: Vec::new(),
            bytes: 0,
        }
    }
    fn push(&mut self, line: &str) -> Result<(), String> {
        let frame = audio(line)?;
        let encoded = frame["realtimeInput"]["audio"]["data"]
            .as_str()
            .ok_or("Invalid resumption audio")?;
        let bytes = encoded.len().div_ceil(4) * 3; // Conservative decoded bound.
        if self.frames.len() >= 128 || self.bytes + bytes > 128_000 {
            return Err("Reconnection exceeded 4s audio buffer; stopped instead of silently dropping speech".into());
        }
        self.bytes += bytes;
        self.frames.push(frame);
        Ok(())
    }
}
async fn resume_buffered(
    config: &Config,
    endpoint: &str,
    handle: &str,
    lines: &mut tokio::io::Lines<BufReader<tokio::process::ChildStdout>>,
    stop: &AtomicBool,
    failed: &AtomicBool,
) -> Result<
    Option<
        tokio_tungstenite::WebSocketStream<
            tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
        >,
    >,
    String,
> {
    let connect = timeout(
        Duration::from_secs(12),
        connect_setup(config, endpoint, false, Some(handle)),
    );
    tokio::pin!(connect);
    let mut check = interval(Duration::from_millis(50));
    let mut buffered = ResumeAudio::new();
    let mut ws = loop {
        tokio::select! {
            _ = check.tick() => if stop.load(Ordering::Relaxed) || failed.load(Ordering::Relaxed) { return Ok(None); },
            result = &mut connect => break result.map_err(|_| "Live resumption timed out (12s); no retry loop")??,
            line = lines.next_line() => {
                let line = line.map_err(|_| "Capture pipe failed during resumption")?.ok_or("Capture ended during resumption")?;
                buffered.push(&line)?;
            }
        }
    };
    timeout(Duration::from_secs(2), async {
        for frame in buffered.frames {
            if stop.load(Ordering::Relaxed) || failed.load(Ordering::Relaxed) {
                return Ok(());
            }
            ws.send(Message::Text(frame.to_string().into()))
                .await
                .map_err(|_| "Resumed audio upload failed")?;
        }
        Ok::<(), &str>(())
    })
    .await
    .map_err(|_| "Buffered audio upload stalled (2s)")??;
    Ok(Some(ws))
}
async fn source_at(
    config: &Config,
    name: &str,
    stop: &AtomicBool,
    failed: &AtomicBool,
    tx: &SyncSender<Event>,
    endpoint: &str,
    finish: Option<&AtomicBool>,
) -> Result<(), String> {
    let connect = connect_setup(config, endpoint, finish.is_some(), None);
    let mut check = interval(Duration::from_millis(50));
    let mut ws = tokio::select! {
        result = timeout(Duration::from_secs(12), connect) => result.map_err(|_| "Live setup timed out (12s)")??,
        _ = async { loop { check.tick().await; if stop.load(Ordering::Relaxed) || failed.load(Ordering::Relaxed) { break; } } } => return Ok(()),
    };
    if finish.is_some() {
        timeout(
            Duration::from_secs(2),
            ws.send(Message::Text(
                json!({"realtimeInput":{"activityStart":{}}})
                    .to_string()
                    .into(),
            )),
        )
        .await
        .map_err(|_| "Dictation activity start timed out")?
        .map_err(|_| "Dictation activity start failed")?;
    }
    let dir = tempfile::tempdir().map_err(|_| "Cannot create private capture workspace")?;
    let mut child = Command::new(&config.helper)
        .arg(dir.path())
        .arg(format!("live-{name}"))
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .kill_on_drop(true)
        .spawn()
        .map_err(|_| "Streaming capture helper missing; rebuild app")?;
    let stdout = child.stdout.take().ok_or("Capture output unavailable")?;
    let mut lines = BufReader::new(stdout).lines();
    let _ = tx.try_send(Event::Status(format!(
        "Live connected • {name} • PCM16 streaming • generated audio muted (may still be billed)"
    )));
    let begin = Instant::now();
    let mut resume = ResumeState::new();
    let mut last_audio = Instant::now();
    let mut last_server = Instant::now();
    let mut finishing: Option<Instant> = None;
    let mut heartbeat = interval(Duration::from_secs(20));
    heartbeat.set_missed_tick_behavior(MissedTickBehavior::Skip);
    let result = async {
        loop {
            tokio::select! {
                _ = check.tick() => {
                    if stop.load(Ordering::Relaxed) || failed.load(Ordering::Relaxed) { return Ok(()); }
                    if finishing.is_none() && recording_limit(finish.is_some()).is_some_and(|limit| begin.elapsed() > limit) { return Err("Dictation 60-second limit reached; draft retained, nothing inserted".into()); }
                    if finishing.is_none() && finish.is_some_and(|flag| flag.load(Ordering::Relaxed)) {
                        let _ = child.kill().await;
                        let _ = child.wait().await;
                        // Flush already-emitted capture frames BEFORE end-of-stream.
                        // Bound the entire drain, not just individual sends.
                        timeout(Duration::from_secs(2), async {
                            let mut count = 0;
                            while let Some(line) = lines.next_line().await.map_err(|_| "Dictation capture drain failed")? {
                                count += 1;
                                if count > 32 { return Err("Dictation capture backlog too large; nothing inserted"); }
                                let frame = audio(&line).map_err(|_| "Invalid final capture frame")?;
                                ws.send(Message::Text(frame.to_string().into())).await.map_err(|_| "Dictation final audio upload failed")?;
                            }
                            Ok::<(), &str>(())
                        }).await.map_err(|_| "Dictation capture drain timed out")??;
                        timeout(Duration::from_secs(2), ws.send(Message::Text(json!({"realtimeInput":{"activityEnd":{}}}).to_string().into()))).await.map_err(|_| "Dictation finish send timed out")?.map_err(|_| "Dictation finish send failed")?;
                        finishing = Some(Instant::now());
                    }
                    if finishing.is_some_and(|at| at.elapsed() > Duration::from_secs(15)) { return Err("Dictation final turn timed out; draft retained, nothing inserted".into()); }
                    if finishing.is_none() && last_audio.elapsed() > Duration::from_secs(20) { return Err("No capture frames for 20s. Check audio permission/device and restart.".into()); }
                    if last_server.elapsed() > Duration::from_secs(60) { return Err("Live server stopped responding (60s)".into()); }
                }
                _ = heartbeat.tick() => {
                    timeout(Duration::from_secs(2), ws.send(Message::Ping(Vec::new().into()))).await.map_err(|_| "Live send stalled")?.map_err(|_| "Live connection lost")?;
                }
                line = lines.next_line(), if finishing.is_none() => {
                    let line = line.map_err(|_| "Audio capture pipe failed")?.ok_or("Audio capture ended; check macOS permissions")?;
                    if line.starts_with("ERROR:") { return Err(line); }
                    let frame = audio(&line)?;
                    timeout(Duration::from_secs(2), ws.send(Message::Text(frame.to_string().into()))).await.map_err(|_| "Audio upload stalled; stopped to avoid stale captions")?.map_err(|_| "Audio upload failed")?;
                    last_audio = Instant::now();
                }
                frame = ws.next() => {
                    last_server = Instant::now();
                    match frame {
                        Some(Ok(frame @ (Message::Text(_) | Message::Binary(_)))) => {
                            let data = frame.into_data();
                            if data.len() > 2_000_000 { return Err("Live response exceeds size limit".into()); }
                            let value: Value = serde_json::from_slice(&data).map_err(|_| "Invalid Live response")?;
                            // Preserve any final text even if the subsequent resume fails.
                            let mut content = value.clone();
                            if finish.is_none() { content.as_object_mut().ok_or("Invalid Live message object")?.remove("goAway"); }
                            emit(tx, name, &content)?;
                            if finish.is_none() {
                                resume.observe(&value)?;
                                if value.get("goAway").is_some() && value.get("error").is_none() {
                                    let handle = resume.reserve(Instant::now())?;
                                    tx.try_send(Event::Status(format!("Renewing {name} server connection; buffering up to 4s audio; API charges continue")))
                                        .map_err(|_| "Caption UI is behind during reconnection")?;
                                    // One session must not have two active connections.
                                    timeout(Duration::from_millis(200), ws.close(None)).await
                                        .map_err(|_| "Old Live connection did not close before resume")?
                                        .map_err(|_| "Cannot close old Live connection before resume")?;
                                    let replacement = resume_buffered(config, endpoint, handle, &mut lines, stop, failed).await?;
                                    let Some(replacement) = replacement else { return Ok(()); };
                                    ws = replacement;
                                    last_audio = Instant::now(); last_server = Instant::now();
                                    tx.try_send(Event::Status(format!("Live resumed • {name} • API charges continue")))
                                        .map_err(|_| "Caption UI is behind after reconnection")?;
                                }
                            }
                            if finishing.is_some() && value["serverContent"]["interrupted"] == true { return Err("Dictation interrupted; draft retained, nothing inserted".into()); }
                            if value["serverContent"]["turnComplete"] == true {
                                if finishing.is_some() { return Ok(()); }
                                if finish.is_some() { return Err("Unexpected early dictation turn; nothing inserted".into()); }
                            }
                        }
                        Some(Ok(Message::Ping(p))) => {
                            timeout(Duration::from_secs(2), ws.send(Message::Pong(p))).await.map_err(|_| "Live ping stalled")?.map_err(|_| "Live connection lost")?;
                        }
                        Some(Ok(Message::Pong(_))) => {},
                        Some(Ok(Message::Close(_))) | None => return Err("Live session closed; check quota/session limits, then restart explicitly".into()),
                        Some(Err(_)) => return Err("Live connection lost; no automatic billable reconnection".into()),
                        _ => {},
                    }
                }
            }
        }
    }.await;
    let _ = child.kill().await;
    let _ = child.wait().await;
    let _ = timeout(Duration::from_millis(200), ws.close(None)).await;
    result
}
pub fn run(config: Config, stop: Arc<AtomicBool>, tx: SyncSender<Event>) -> Result<(), String> {
    run_controlled(config, stop, None, tx)
}
pub fn run_dictation(
    config: Config,
    stop: Arc<AtomicBool>,
    finish: Arc<AtomicBool>,
    tx: SyncSender<Event>,
) -> Result<(), String> {
    if config.source != "microphone" || config.target != "en" {
        return Err("Dictation requires microphone and English".into());
    }
    let result = run_controlled(config, stop.clone(), Some(finish), tx);
    if stop.load(Ordering::Relaxed) {
        return Err("Dictation cancelled; nothing inserted".into());
    }
    result
}
fn run_controlled(
    config: Config,
    stop: Arc<AtomicBool>,
    finish: Option<Arc<AtomicBool>>,
    tx: SyncSender<Event>,
) -> Result<(), String> {
    if config.key.trim().is_empty() {
        return Err("Enter Gemini API key before Start".into());
    }
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .enable_all()
        .build()
        .map_err(|_| "Cannot start streaming runtime")?;
    runtime.block_on(async {
        let failed = AtomicBool::new(false);
        let config = &config;
        let stop = &stop;
        let failed = &failed;
        let tx = &tx;
        let finish = finish.as_deref();
        let one = |name| async move {
            let r = source(config, name, stop, failed, tx, finish).await;
            if r.is_err() {
                failed.store(true, Ordering::Relaxed);
            }
            r
        };
        if config.source == "both" {
            let (a, b) = tokio::join!(one("system"), one("microphone"));
            a.and(b)
        } else {
            one(config.source.as_str()).await
        }
    })
}
#[cfg(test)]
mod tests {
    use super::*;
    async fn dictation_mock(outcome: &str) {
        use std::os::unix::fs::PermissionsExt;
        let dir = tempfile::tempdir().unwrap();
        let helper = dir.path().join("capture-test");
        let pidfile = dir.path().join("pid");
        std::fs::write(&helper, format!("#!/bin/sh\necho $$ > '{}'\nprintf 'PCM:AAABAA==\\nPCM:AAABAA==\\n'\nexec /bin/sleep 30\n", pidfile.display())).unwrap();
        std::fs::set_permissions(&helper, std::fs::Permissions::from_mode(0o700)).unwrap();
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let endpoint = format!("ws://{}", listener.local_addr().unwrap());
        let config = Config {
            key: "fixture-only".into(),
            target: "en".into(),
            source: "microphone".into(),
            helper,
        };
        let stop = AtomicBool::new(false);
        let failed = AtomicBool::new(false);
        let finish = AtomicBool::new(false);
        let (tx, rx) = std::sync::mpsc::sync_channel(8);
        let server = async {
            let (socket, _) = listener.accept().await.unwrap();
            let mut ws = tokio_tungstenite::accept_async(socket).await.unwrap();
            let setup_frame = ws.next().await.unwrap().unwrap().into_text().unwrap();
            assert_eq!(
                serde_json::from_str::<Value>(&setup_frame).unwrap(),
                dictation_setup()
            );
            ws.send(Message::Binary(
                json!({"setupComplete":{}}).to_string().into_bytes().into(),
            ))
            .await
            .unwrap();
            let mut audio_count = 0;
            while let Some(Ok(frame)) = ws.next().await {
                match frame {
                    Message::Text(s) => {
                        let value: Value = serde_json::from_str(&s).unwrap();
                        if value["realtimeInput"]["activityEnd"].is_object() {
                            assert!(audio_count >= 2, "End sent before pending audio drain");
                            let response = json!({"serverContent":{"outputTranscription":{"text":"Hello world."},"turnComplete":outcome == "complete", "interrupted":outcome == "interrupted"}});
                            ws.send(Message::Binary(response.to_string().into_bytes().into()))
                                .await
                                .unwrap();
                        } else if value["realtimeInput"]["activityStart"].is_object() {
                            assert_eq!(audio_count, 0);
                        } else {
                            assert!(value["realtimeInput"]["audio"].is_object());
                            audio_count += 1;
                            if outcome == "cancel" {
                                stop.store(true, Ordering::Relaxed);
                            } else if outcome == "early" {
                                if audio_count == 1 {
                                    ws.send(Message::Binary(
                                        json!({"serverContent":{"turnComplete":true}})
                                            .to_string()
                                            .into_bytes()
                                            .into(),
                                    ))
                                    .await
                                    .unwrap();
                                }
                            } else {
                                finish.store(true, Ordering::Relaxed);
                            }
                        }
                    }
                    Message::Ping(p) => {
                        let _ = ws.send(Message::Pong(p)).await;
                    }
                    Message::Close(_) => break,
                    _ => {}
                }
            }
        };
        let (result, _) = timeout(Duration::from_secs(22), async {
            tokio::join!(
                source_at(
                    &config,
                    "microphone",
                    &stop,
                    &failed,
                    &tx,
                    &endpoint,
                    Some(&finish)
                ),
                server
            )
        })
        .await
        .unwrap();
        match outcome {
            "timeout" => assert!(result.unwrap_err().contains("final turn timed out")),
            "interrupted" => assert!(result.unwrap_err().contains("interrupted")),
            "early" => assert!(result.unwrap_err().contains("early dictation turn")),
            _ => assert!(result.is_ok()),
        }
        let events: Vec<_> = rx.try_iter().collect();
        if !["cancel", "early"].contains(&outcome) {
            assert!(events.iter().any(
                |event| matches!(event, Event::Live(_,_,Some(text),_) if text == "Hello world.")
            ));
        }
        let pid = std::fs::read_to_string(pidfile).unwrap();
        assert!(
            !std::process::Command::new("/bin/kill")
                .args(["-0", pid.trim()])
                .stderr(Stdio::null())
                .status()
                .unwrap()
                .success(),
            "Owned capture helper leaked"
        );
    }
    #[tokio::test]
    async fn dictation_finish_drains_audio_and_final_binary_turn() {
        dictation_mock("complete").await;
    }
    #[tokio::test]
    async fn dictation_missing_final_turn_times_out_and_reaps() {
        dictation_mock("timeout").await;
    }
    #[tokio::test]
    async fn dictation_cancel_reaps_without_final_translation() {
        dictation_mock("cancel").await;
    }
    #[tokio::test]
    async fn dictation_interrupted_turn_is_not_success() {
        dictation_mock("interrupted").await;
    }
    #[tokio::test]
    async fn dictation_early_turn_is_not_success() {
        dictation_mock("early").await;
    }
    #[test]
    fn dictation_stop_is_never_success() {
        let config = Config {
            key: "fixture-only".into(),
            target: "en".into(),
            source: "microphone".into(),
            helper: PathBuf::new(),
        };
        assert!(run_dictation(
            config,
            Arc::new(AtomicBool::new(true)),
            Arc::new(AtomicBool::new(false)),
            std::sync::mpsc::sync_channel(4).0
        )
        .unwrap_err()
        .contains("cancelled"));
    }
    #[test]
    fn meeting_resumes_with_bounded_ephemeral_handles_not_dictation() {
        let initial = meeting_setup("uz", None);
        assert!(initial["setup"]["sessionResumption"].is_object());
        assert!(initial["setup"]["contextWindowCompression"]["slidingWindow"].is_object());
        assert!(dictation_setup()["setup"]
            .get("sessionResumption")
            .is_none());
        assert!(dictation_setup()["setup"]
            .get("contextWindowCompression")
            .is_none());
        let mut state = ResumeState::new();
        let now = Instant::now();
        assert!(state.reserve(now).is_err());
        state
            .observe(
                &json!({"sessionResumptionUpdate":{"resumable":true,"newHandle":"fixture-handle"}}),
            )
            .unwrap();
        assert_eq!(
            meeting_setup("uz", Some(state.handle.as_deref().unwrap()))["setup"]
                ["sessionResumption"]["handle"],
            "fixture-handle"
        );
        // Missing handle reservation above counts conservatively as an attempt.
        assert_eq!(state.reserve(now).unwrap(), "fixture-handle");
        assert_eq!(state.reserve(now).unwrap(), "fixture-handle");
        assert!(state.reserve(now).unwrap_err().contains("reconnect loop"));
        assert!(state.reserve(now + Duration::from_secs(61)).is_ok());
        state
            .observe(&json!({"sessionResumptionUpdate":{"resumable":false}}))
            .unwrap();
        assert!(state.handle.is_none() && state.reserve(now + Duration::from_secs(61)).is_err());
        for handle in ["".into(), "private\nfixture".into(), "x".repeat(4097)] {
            let e = state
                .observe(&json!({"sessionResumptionUpdate":{"resumable":true,"newHandle":handle}}))
                .unwrap_err();
            assert!(!e.contains("private"));
        }
    }
    #[test]
    fn reconnection_audio_is_bounded_without_silent_drops() {
        let mut buffer = ResumeAudio::new();
        let line = format!("PCM:{}", STANDARD.encode(vec![0; 3200]));
        for _ in 0..39 {
            buffer.push(&line).unwrap();
        }
        assert_eq!(buffer.frames.len(), 39);
        assert!(buffer
            .push(&format!("PCM:{}", STANDARD.encode(vec![0; 32000])))
            .is_err());
        assert_eq!(buffer.frames.len(), 39);
        let mut tiny = ResumeAudio::new();
        for _ in 0..128 {
            tiny.push("PCM:AAABAA==").unwrap();
        }
        assert!(tiny.push("PCM:AAABAA==").is_err());
        assert!(ResumeAudio::new().push("ERROR:fixture").is_err());
    }
    #[tokio::test]
    async fn server_goaway_resumes_same_capture_and_preserves_final_text() {
        use std::os::unix::fs::PermissionsExt;
        let dir = tempfile::tempdir().unwrap();
        let helper = dir.path().join("capture-test");
        let pidfile = dir.path().join("pid");
        std::fs::write(
            &helper,
            format!(
                "#!/bin/sh\necho $$ >> '{}'\nprintf 'PCM:AAABAA==\\n'\nexec /bin/sleep 30\n",
                pidfile.display()
            ),
        )
        .unwrap();
        std::fs::set_permissions(&helper, std::fs::Permissions::from_mode(0o700)).unwrap();
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let endpoint = format!("ws://{}", listener.local_addr().unwrap());
        let config = Config {
            key: "fixture-only".into(),
            target: "uz".into(),
            source: "system".into(),
            helper,
        };
        let stop = AtomicBool::new(false);
        let failed = AtomicBool::new(false);
        let (tx, rx) = std::sync::mpsc::sync_channel(16);
        let server = async {
            let (socket, _) = listener.accept().await.unwrap();
            let mut first = tokio_tungstenite::accept_async(socket).await.unwrap();
            let request: Value =
                serde_json::from_slice(&first.next().await.unwrap().unwrap().into_data()).unwrap();
            assert_eq!(request, meeting_setup("uz", None));
            first
                .send(Message::Binary(
                    json!({"setupComplete":{}}).to_string().into_bytes().into(),
                ))
                .await
                .unwrap();
            // Wait for the helper's first frame: its PID receipt now exists,
            // so a very fast mock cannot cancel before the child is scheduled.
            loop {
                match first.next().await.unwrap().unwrap() {
                    Message::Text(_) => break,
                    Message::Ping(p) => first.send(Message::Pong(p)).await.unwrap(),
                    _ => {}
                }
            }
            first.send(Message::Binary(json!({"sessionResumptionUpdate":{"resumable":true,"newHandle":"fixture-handle"},"goAway":{"timeLeft":"10s"},"serverContent":{"inputTranscription":{"text":"First.","finished":true},"outputTranscription":{"text":"Birinchi.","finished":true}}}).to_string().into_bytes().into())).await.unwrap();
            // A real resumable session must close its previous connection first.
            while let Some(Ok(message)) = first.next().await {
                if matches!(message, Message::Close(_)) {
                    break;
                }
            }
            let (socket, _) = listener.accept().await.unwrap();
            let mut second = tokio_tungstenite::accept_async(socket).await.unwrap();
            let request: Value =
                serde_json::from_slice(&second.next().await.unwrap().unwrap().into_data()).unwrap();
            assert_eq!(request, meeting_setup("uz", Some("fixture-handle")));
            second
                .send(Message::Binary(
                    json!({"setupComplete":{}}).to_string().into_bytes().into(),
                ))
                .await
                .unwrap();
            second.send(Message::Binary(json!({"serverContent":{"inputTranscription":{"text":"Next."},"outputTranscription":{"text":"Keyingi."}}}).to_string().into_bytes().into())).await.unwrap();
            while let Some(Ok(message)) = second.next().await {
                match message {
                    Message::Ping(p) => {
                        let _ = second.send(Message::Pong(p)).await;
                    }
                    Message::Close(_) => break,
                    _ => {}
                }
            }
        };
        let ui = async {
            let mut inputs = Vec::new();
            loop {
                tokio::time::sleep(Duration::from_millis(5)).await;
                while let Ok(event) = rx.try_recv() {
                    if let Event::Live(_, Some(input), _, _) = event {
                        inputs.push(input);
                    }
                }
                if inputs.len() == 2 {
                    assert_eq!(inputs, ["First.", "Next."]);
                    stop.store(true, Ordering::Relaxed);
                    break;
                }
            }
        };
        timeout(Duration::from_secs(4), async {
            let (result, _, _) = tokio::join!(
                source_at(&config, "system", &stop, &failed, &tx, &endpoint, None),
                server,
                ui
            );
            result.unwrap();
        })
        .await
        .unwrap();
        let pids = std::fs::read_to_string(pidfile).unwrap();
        assert_eq!(
            pids.lines().count(),
            1,
            "Resumption must not restart capture or request permissions"
        );
        let pid: i32 = pids.trim().parse().unwrap();
        assert_eq!(unsafe { libc::kill(pid, 0) }, -1, "Owned helper leaked");
    }
    #[test]
    fn meeting_has_no_duration_cap_but_dictation_keeps_60_seconds() {
        assert_eq!(
            recording_limit(false),
            None,
            "Meeting must continue past 600s"
        );
        assert_eq!(recording_limit(true), Some(Duration::from_secs(60)));
    }
    #[test]
    fn uzbek_setup_has_both_transcripts() {
        let v = setup("uz");
        assert_eq!(
            v["setup"]["generationConfig"]["translationConfig"]["targetLanguageCode"],
            "uz"
        );
        assert!(v["setup"].get("inputAudioTranscription").is_some());
        assert!(v["setup"].get("outputAudioTranscription").is_some());
        assert!(v["setup"]["generationConfig"]
            .get("inputAudioTranscription")
            .is_none());
        assert!(v["setup"]["generationConfig"]
            .get("outputAudioTranscription")
            .is_none());
        assert!(v.to_string().contains("AUDIO"));
    }
    // tungstenite's required handshake callback returns its fixed (large) ErrorResponse.
    #[allow(clippy::result_large_err)]
    #[tokio::test]
    async fn mock_streaming_transcript_translation_and_stop_reap_helper() {
        use std::os::unix::fs::PermissionsExt;
        let dir = tempfile::tempdir().unwrap();
        let helper = dir.path().join("capture-test");
        let pidfile = dir.path().join("pid");
        std::fs::write(
            &helper,
            format!(
                "#!/bin/sh\necho $$ > '{}'\nprintf 'PCM:AAABAA==\\n'\nexec /bin/sleep 5\n",
                pidfile.display()
            ),
        )
        .unwrap();
        std::fs::set_permissions(&helper, std::fs::Permissions::from_mode(0o700)).unwrap();
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let endpoint = format!("ws://{}", listener.local_addr().unwrap());
        let config = Config {
            key: "test-not-a-real-key".into(),
            target: "uz".into(),
            source: "system".into(),
            helper,
        };
        let stop = AtomicBool::new(false);
        let failed = AtomicBool::new(false);
        let (tx, rx) = std::sync::mpsc::sync_channel(8);
        let server = async {
            let (socket, _) = listener.accept().await.unwrap();
            let mut ws = tokio_tungstenite::accept_hdr_async(
                socket,
                |request: &tokio_tungstenite::tungstenite::handshake::server::Request, response| {
                    assert_eq!(request.headers()["x-goog-api-key"], "test-not-a-real-key");
                    assert!(request.uri().query().is_none());
                    Ok(response)
                },
            )
            .await
            .unwrap();
            let setup_frame = ws.next().await.unwrap().unwrap().into_text().unwrap();
            assert_eq!(
                serde_json::from_str::<Value>(&setup_frame).unwrap(),
                meeting_setup("uz", None)
            );
            ws.send(Message::Binary(
                json!({"setupComplete":{}}).to_string().into_bytes().into(),
            ))
            .await
            .unwrap();
            while let Some(Ok(frame)) = ws.next().await {
                match frame {
                    Message::Ping(p) => ws.send(Message::Pong(p)).await.unwrap(),
                    Message::Text(s) => {
                        let v: Value = serde_json::from_str(&s).unwrap();
                        assert_eq!(v["realtimeInput"]["audio"]["data"], "AAABAA==");
                        ws.send(Message::Binary(json!({"serverContent":{"inputTranscription":{"text":"Hello"},"outputTranscription":{"text":"Salom"}}}).to_string().into_bytes().into())).await.unwrap();
                    }
                    Message::Close(_) => break,
                    _ => {}
                }
            }
        };
        let ui = async {
            let mut tick = interval(Duration::from_millis(5));
            loop {
                tick.tick().await;
                if let Ok(Event::Live(source, input, output, _)) = rx.try_recv() {
                    assert_eq!(source, "system");
                    assert_eq!(input.as_deref(), Some("Hello"));
                    assert_eq!(output.as_deref(), Some("Salom"));
                    stop.store(true, Ordering::Relaxed);
                    break;
                }
            }
        };
        timeout(Duration::from_secs(4), async {
            let (result, _, _) = tokio::join!(
                source_at(&config, "system", &stop, &failed, &tx, &endpoint, None),
                server,
                ui
            );
            result.unwrap();
        })
        .await
        .unwrap();
        let pid: i32 = std::fs::read_to_string(pidfile)
            .unwrap()
            .trim()
            .parse()
            .unwrap();
        assert_eq!(
            unsafe { libc::kill(pid, 0) },
            -1,
            "owned helper still running"
        );
    }
    #[tokio::test]
    #[ignore = "Real Google API setup only: explicit consent and MEETING_CAPTIONS_TEST_ENV required"]
    async fn cloud_setup_only_no_audio() {
        let path = std::env::var("MEETING_CAPTIONS_TEST_ENV").expect("Explicit .env path required");
        let key = crate::env_key::load(std::path::Path::new(&path))
            .expect("Cannot load key (contents hidden)");
        let config = Config {
            key,
            target: "uz".into(),
            source: "system".into(),
            helper: PathBuf::new(),
        };
        let mut ws = timeout(
            Duration::from_secs(12),
            connect_setup(&config, ENDPOINT, false, None),
        )
        .await
        .expect("Setup timeout")
        .expect("Live setup failed (details hidden)");
        let _ = timeout(Duration::from_secs(1), ws.close(None)).await;
        // Never spawn capture, send audio, play generated audio, or change billing.
    }
    #[test]
    fn tls_crypto_provider_is_available() {
        let _ = rustls::crypto::ring::default_provider().install_default();
        let _ = rustls::ClientConfig::builder();
    }
    #[test]
    fn native_boundaries_follow_text_and_are_not_dropped() {
        let (tx, rx) = std::sync::mpsc::sync_channel(4);
        let payload = serde_json::json!({"serverContent":{"inputTranscription":{"text":"Hello.","finished":true},"outputTranscription":{"text":"Salom.","finished":true}}});
        emit(&tx, "system", &payload).unwrap();
        assert!(matches!(
            rx.try_recv(),
            Ok(Event::Live(_, Some(_), Some(_), _))
        ));
        assert!(
            matches!(rx.try_recv(), Ok(Event::Boundary(source, true, true)) if source == "system")
        );
        let (tx, _rx) = std::sync::mpsc::sync_channel(1);
        assert!(emit(&tx, "system", &payload)
            .unwrap_err()
            .contains("boundary queue full"));
    }
    #[test]
    fn pcm_wire_format() {
        let v = audio("PCM:AAABAA==").unwrap();
        assert_eq!(
            v["realtimeInput"]["audio"]["mimeType"],
            "audio/pcm;rate=16000"
        );
    }
    #[test]
    fn rejects_bad_pcm() {
        for s in ["PCM:", "PCM:AA==", "PCM:!!", "CHUNK:audio.wav"] {
            assert!(audio(s).is_err());
        }
        assert!(audio(&format!("PCM:{}", "A".repeat(44001))).is_err());
    }
    #[test]
    fn deltas_preserve_languages() {
        let t = text(&json!({"serverContent":{"inputTranscription":{"text":"Привет"}, "outputTranscription":{"text":"Salom"}}})).unwrap();
        assert_eq!(t.input.as_deref(), Some("Привет"));
        assert_eq!(t.output.as_deref(), Some("Salom"));
    }
    #[test]
    fn audio_is_not_rendered() {
        assert_eq!(
            text(
                &json!({"serverContent":{"modelTurn":{"parts":[{"inlineData":{"data":"audio"}}]}}})
            )
            .unwrap(),
            Text::default()
        );
    }
    #[test]
    fn quota_and_session_errors_visible_without_secrets() {
        let e = text(&json!({"error":{"message":"secret-key"}})).unwrap_err();
        assert!(!e.contains("secret-key"));
        assert!(text(&json!({"goAway":{}})).is_err());
    }
    #[test]
    fn interim_supported() {
        assert_eq!(
            text(&json!({"serverContent":{"interimInputTranscription":{"text":"sal"}}}))
                .unwrap()
                .interim
                .as_deref(),
            Some("sal")
        );
    }
    #[test]
    fn ui_backpressure_is_visible() {
        let (tx, _rx) = std::sync::mpsc::sync_channel(1);
        let v = json!({"serverContent":{"inputTranscription":{"text":"salom"}}});
        assert!(emit(&tx, "system", &v).is_ok());
        assert!(emit(&tx, "system", &v).is_err());
    }
}

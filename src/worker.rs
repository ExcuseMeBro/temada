//! Private native-UI JSON-lines bridge. stdout contains captions, never keys or logs.
use super::{live, Event};
use serde::Deserialize;
use serde_json::{json, Value};
use std::{
    io::{BufRead, Read, Write},
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc, Arc,
    },
    thread,
};
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Credentials {
    #[serde(rename = "apiKey")]
    api_key: String,
}
fn read_key(input: &mut impl BufRead) -> Result<String, &'static str> {
    let mut frame = Vec::new();
    input
        .take(4097)
        .read_until(b'\n', &mut frame)
        .map_err(|_| "Cannot read API credential frame")?;
    if frame.len() > 4096 || frame.last() != Some(&b'\n') {
        return Err("Missing or oversized API credential frame");
    }
    let credentials: Credentials = serde_json::from_slice(&frame)
        .map_err(|_| "Invalid API credential frame (details hidden)")?;
    let key = credentials.api_key.trim();
    if key.is_empty() || key.len() > 1024 || !key.bytes().all(|b| b.is_ascii_graphic()) {
        return Err("Enter a valid nonempty API key (at most 1024 ASCII characters)");
    }
    Ok(key.to_owned())
}
fn options(args: &[String], input: &mut impl BufRead) -> Result<live::Config, &'static str> {
    if !args.iter().any(|a| a == "--cloud-consent") {
        return Err("Explicit cloud consent required");
    }
    let get = |flag| {
        args.windows(2)
            .find(|a| a[0] == flag)
            .map(|a| a[1].as_str())
    };
    let target = get("--target").ok_or("Target required")?;
    let source = get("--source").ok_or("Source required")?;
    if !["uz", "en", "ru"].contains(&target) || !["system", "microphone", "both"].contains(&source)
    {
        return Err("Unsupported language/source");
    }
    if args.iter().any(|arg| arg == "--env-file") {
        return Err("Native worker accepts API credentials via stdin only");
    }
    let key = read_key(input)?;
    let helper = std::env::current_exe()
        .map_err(|_| "Worker path unavailable")?
        .with_file_name("capture-helper");
    Ok(live::Config {
        key,
        target: target.into(),
        source: source.into(),
        helper,
    })
}
fn wire(event: Event) -> Value {
    match event {
        Event::Status(message) => json!({"kind":"status", "message": message}),
        Event::Live(source, original, translation, interim) => {
            json!({"kind":"text", "source":source, "original":original,"translation":translation,"interim":interim})
        }
        Event::Boundary(source, input, output) => {
            json!({"kind":"boundary", "source":source,"inputFinished":input,"outputFinished":output})
        }
        Event::Caption(_, _) => {
            json!({"kind":"error", "message":"Legacy events are not supported by native worker"})
        }
    }
}
pub fn run(args: &[String]) -> i32 {
    let config = match options(args, &mut std::io::stdin().lock()) {
        Ok(c) => c,
        Err(e) => {
            println!("{}", json!({"kind":"error","message":e}));
            return 1;
        }
    };
    let stop = Arc::new(AtomicBool::new(false));
    let input_stop = stop.clone();
    // Only this owned worker's stdin controls it. UI closes pipe on Stop/exit.
    thread::spawn(move || {
        let mut line = String::new();
        let _ = std::io::stdin().lock().take(32).read_line(&mut line);
        input_stop.store(true, Ordering::Relaxed);
    });
    let (tx, rx) = mpsc::sync_channel(64);
    let worker_stop = stop.clone();
    let worker = thread::spawn(move || live::run(config, worker_stop, tx));
    let mut output = std::io::stdout().lock();
    for event in rx {
        if writeln!(output, "{}", wire(event))
            .and_then(|_| output.flush())
            .is_err()
        {
            stop.store(true, Ordering::Relaxed);
            break;
        }
    }
    let result = worker.join();
    let (exit, message) = match result {
        Ok(Ok(())) => (0, None),
        Ok(Err(e)) => (1, Some(e)),
        Err(_) => (1, Some("Streaming worker failed".into())),
    };
    if let Some(message) = message {
        let _ = writeln!(output, "{}", json!({"kind":"error","message":message}));
    }
    let _ = writeln!(output, "{}", json!({"kind":"stopped"}));
    let _ = output.flush();
    exit
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn consent_before_key_read() {
        let mut input = std::io::Cursor::new(b"do-not-read");
        assert!(options(&[], &mut input).err().unwrap().contains("consent"));
        assert_eq!(input.position(), 0);
    }
    #[test]
    fn invalid_source_before_key_read() {
        let args = [
            "--cloud-consent",
            "--target",
            "uz",
            "--source",
            "bad",
            "--env-file",
            "/nonexistent",
        ]
        .map(String::from);
        let mut input = std::io::Cursor::new(b"do-not-read");
        assert!(options(&args, &mut input)
            .err()
            .unwrap()
            .contains("Unsupported"));
        assert_eq!(input.position(), 0);
    }
    #[test]
    fn credential_frame_is_bounded_redacted_and_strict() {
        for input in [
            "".to_owned(),
            "{\"apiKey\":\"secret-invalid\"}".to_owned(),
            "{\"apiKey\":\"\"}\n".to_owned(),
            "{\"apiKey\":\"secret invalid\"}\n".to_owned(),
            "{\"apiKey\":\"secret-ключ\"}\n".to_owned(),
            "{\"apiKey\":\"secret\\ninvalid\"}\n".to_owned(),
            "{\"apiKey\":\"secret\",\"extra\":true}\n".to_owned(),
            format!("{{\"apiKey\":\"{}\"}}\n", "x".repeat(1025)),
            format!("{}\n", "x".repeat(4096)),
        ] {
            let error = read_key(&mut std::io::Cursor::new(input)).unwrap_err();
            assert!(!error.contains("secret"));
        }
        let key = "fixture-quote\"-backslash\\-only";
        let frame = format!("{}\nSTOP\n", json!({"apiKey":key}));
        let mut reader = std::io::BufReader::new(std::io::Cursor::new(frame));
        assert_eq!(read_key(&mut reader).unwrap(), key);
        let mut remaining = String::new();
        reader.read_to_string(&mut remaining).unwrap();
        assert_eq!(remaining, "STOP\n", "Bootstrap consumed cancellation input");
        assert_eq!(
            read_key(&mut std::io::Cursor::new(format!(
                "{}\n",
                json!({"apiKey":"x".repeat(1024)})
            )))
            .unwrap()
            .len(),
            1024
        );
    }
    #[test]
    fn stdin_only_native_options() {
        let args = ["--cloud-consent", "--source", "system", "--target", "uz"].map(String::from);
        let mut input = std::io::Cursor::new(b"{\"apiKey\":\"fixture-only\"}\n");
        let config = options(&args, &mut input).unwrap();
        assert_eq!(config.key, "fixture-only");
        assert_eq!(config.source, "system");
        let mut args = args.to_vec();
        args.extend(["--env-file".into(), "/nonexistent".into()]);
        let mut unread = std::io::Cursor::new(b"do-not-read");
        assert!(options(&args, &mut unread)
            .err()
            .unwrap()
            .contains("stdin only"));
        assert_eq!(unread.position(), 0);
    }
    #[test]
    fn frame_is_escaped_json() {
        let v = wire(Event::Live(
            "system".into(),
            Some("line\n\"quoted\"".into()),
            Some("salom".into()),
            None,
        ));
        let encoded = v.to_string();
        assert_eq!(encoded.lines().count(), 1);
        assert_eq!(v["translation"], "salom");
    }
}

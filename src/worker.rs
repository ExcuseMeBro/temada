//! Private native-UI JSON-lines bridge. stdout contains captions, never keys or logs.
use super::{env_key, live, Event};
use serde_json::{json, Value};
use std::{
    io::{BufRead, Read, Write},
    path::Path,
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc, Arc,
    },
    thread,
};
fn options(args: &[String]) -> Result<live::Config, &'static str> {
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
    let key = env_key::load(Path::new(
        get("--env-file").ok_or("Explicit .env path required")?,
    ))?;
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
    let config = match options(args) {
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
    fn consent_before_file_read() {
        assert!(options(&[]).err().unwrap().contains("consent"));
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
        assert!(options(&args).err().unwrap().contains("Unsupported"));
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

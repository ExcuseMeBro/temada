//! Read only the two Gemini key aliases. Never source a shell file, export or log values.
use std::{io::Read, path::Path};
const MAX_BYTES: usize = 65536;
fn parse(bytes: &[u8]) -> Result<String, &'static str> {
    if bytes.len() > MAX_BYTES {
        return Err(".env exceeds 64KiB limit");
    }
    let mut selected: Option<String> = None;
    for entry in dotenvy::from_read_iter(bytes) {
        let (name, value) =
            entry.map_err(|_| "Invalid .env syntax (details hidden to protect secrets)")?;
        if matches!(name.as_str(), "GEMINI_API_KEY" | "GOOGLE_API_KEY") && !value.trim().is_empty()
        {
            let value = value.trim().to_owned();
            if selected.as_ref().is_some_and(|key| key != &value) {
                return Err("Conflicting Gemini keys in .env; keep one key or identical aliases");
            }
            selected = Some(value);
        }
    }
    selected.ok_or("No nonempty GEMINI_API_KEY or GOOGLE_API_KEY in .env")
}
pub fn load(path: &Path) -> Result<String, &'static str> {
    let file = std::fs::File::open(path).map_err(|_| "Cannot open selected .env file")?;
    if !file
        .metadata()
        .map_err(|_| "Cannot inspect .env file")?
        .is_file()
    {
        return Err("Select a regular .env file");
    }
    let mut bytes = Vec::new();
    file.take((MAX_BYTES + 1) as u64)
        .read_to_end(&mut bytes)
        .map_err(|_| "Cannot read selected .env file")?;
    parse(&bytes)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn google_alias_and_quotes() {
        assert_eq!(
            parse(b"# comment\nexport GOOGLE_API_KEY='fixture-only'\nUNRELATED=x\n").unwrap(),
            "fixture-only"
        );
    }
    #[test]
    fn gemini_alias() {
        assert_eq!(
            parse(b"GEMINI_API_KEY=fixture-only # comment\n").unwrap(),
            "fixture-only"
        );
    }
    #[test]
    fn no_shell_execution() {
        assert_eq!(parse(b"GOOGLE_API_KEY='$(whoami)'\n").unwrap(), "$(whoami)");
    }
    #[test]
    fn missing_empty_conflicting() {
        for bytes in [
            b"UNRELATED=hello".as_slice(),
            b"GOOGLE_API_KEY=''",
            b"GOOGLE_API_KEY=one\nGEMINI_API_KEY=two",
        ] {
            assert!(parse(bytes).is_err());
        }
    }
    #[test]
    fn parse_errors_never_echo_contents() {
        let e = parse(b"GOOGLE_API_KEY='secret-value").unwrap_err();
        assert!(!e.contains("secret-value"));
    }
    #[test]
    fn bounded_file() {
        assert!(parse(&vec![b'x'; MAX_BYTES + 1]).is_err());
    }
    #[test]
    fn loads_without_exporting_environment() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join(".env");
        let before = std::env::var_os("GOOGLE_API_KEY");
        std::fs::write(&path, "GOOGLE_API_KEY=fixture-only\n").unwrap();
        assert_eq!(load(&path).unwrap(), "fixture-only");
        assert_eq!(before, std::env::var_os("GOOGLE_API_KEY"));
    }
}

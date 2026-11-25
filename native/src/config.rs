use std::{
    env, fs,
    io,
    path::{Path, PathBuf},
    process::{Command, Output},
};

pub type Result<T = ()> = std::result::Result<T, Box<dyn std::error::Error>>;

pub fn error(s: impl Into<String>) -> Box<dyn std::error::Error> {
    io::Error::other(s.into()).into()
}

pub fn home() -> PathBuf {
    PathBuf::from(env::var_os("HOME").expect("HOME must be set"))
}

pub fn xdg(key: &str, fallback: &str) -> PathBuf {
    env::var_os(key)
        .filter(|s| !s.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| home().join(fallback))
}

pub fn state() -> PathBuf {
    xdg("XDG_STATE_HOME", ".local/state").join("zenith")
}

pub fn cache() -> PathBuf {
    xdg("XDG_CACHE_HOME", ".cache").join("zenith")
}

pub fn root() -> PathBuf {
    env::var_os("ZENITH_ROOT")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(env!("CARGO_MANIFEST_DIR"))
                .parent()
                .unwrap()
                .to_path_buf()
        })
}

pub fn atomic(path: &Path, contents: impl AsRef<[u8]>) -> Result {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let temp = path.with_extension(format!("tmp-{}", std::process::id()));
    let result = (|| {
        fs::write(&temp, contents)?;
        fs::rename(&temp, path)?;
        Ok(())
    })();
    if result.is_err() {
        let _ = fs::remove_file(temp);
    }
    result
}

pub fn text(path: &Path) -> String {
    fs::read_to_string(path).unwrap_or_default().trim().into()
}

pub fn run(cmd: &str, args: &[&str]) -> io::Result<Output> {
    Command::new(cmd).args(args).output()
}

pub fn exists(cmd: &str) -> bool {
    run("which", &[cmd]).is_ok_and(|o| o.status.success())
}

pub fn walk(dir: &Path) -> Vec<PathBuf> {
    let mut files = Vec::new();
    if let Ok(entries) = fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                files.extend(walk(&path));
            } else if path.is_file() {
                files.push(path);
            }
        }
    }
    files
}

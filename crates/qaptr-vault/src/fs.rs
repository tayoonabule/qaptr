//! Small filesystem operations kept separate from vault policy.

use std::{
    fs, io,
    path::{Path, PathBuf},
};

use crate::{Result, VaultError};

pub(crate) fn create_dir_all(path: &Path) -> Result<()> {
    fs::create_dir_all(path).map_err(|source| io_error("create directory", path, source))
}

pub(crate) fn create_dir(path: &Path) -> Result<()> {
    fs::create_dir(path).map_err(|source| io_error("create directory", path, source))
}

pub(crate) fn read(path: &Path) -> Result<Vec<u8>> {
    fs::read(path).map_err(|source| io_error("read file", path, source))
}

pub(crate) fn rename(from: &Path, to: &Path) -> Result<()> {
    fs::rename(from, to).map_err(|source| io_error("rename directory", to, source))
}

pub(crate) fn remove_dir_all(path: &Path) -> Result<()> {
    fs::remove_dir_all(path).map_err(|source| io_error("remove directory", path, source))
}

pub(crate) fn read_dir(path: &Path) -> Result<fs::ReadDir> {
    fs::read_dir(path).map_err(|source| io_error("read directory", path, source))
}

pub(crate) fn sync_dir(path: &Path) -> Result<()> {
    fs::File::open(path)
        .and_then(|file| file.sync_all())
        .map_err(|source| io_error("sync directory", path, source))
}

pub(crate) fn atomic_write(path: &Path, bytes: &[u8]) -> Result<()> {
    let temp = PathBuf::from(format!("{}.tmp", path.display()));
    let result = (|| {
        let mut file = fs::OpenOptions::new()
            .create_new(true)
            .write(true)
            .open(&temp)
            .map_err(|source| io_error("create temporary file", &temp, source))?;
        std::io::Write::write_all(&mut file, bytes)
            .map_err(|source| io_error("write temporary file", &temp, source))?;
        file.sync_all()
            .map_err(|source| io_error("sync temporary file", &temp, source))?;
        fs::rename(&temp, path).map_err(|source| io_error("rename temporary file", path, source))
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temp);
    }
    result
}

pub(crate) fn mark_excluded(path: &Path) -> Result<()> {
    #[cfg(target_os = "macos")]
    {
        xattr::set(
            path,
            "com.apple.metadata:com_apple_backup_excludeItem",
            b"com.apple.backupd",
        )
        .map_err(|source| io_error("set backup exclusion", path, source))?;
        xattr::set(
            path,
            "com.apple.metadata:com_apple_spotlight",
            b"com.apple.metadata:com_apple_spotlight",
        )
        .map_err(|source| io_error("set Spotlight exclusion", path, source))?;
    }
    Ok(())
}

pub(crate) fn has_exclusion_attributes(path: &Path) -> bool {
    #[cfg(target_os = "macos")]
    {
        xattr::get(path, "com.apple.metadata:com_apple_backup_excludeItem")
            .ok()
            .flatten()
            .is_some()
            && xattr::get(path, "com.apple.metadata:com_apple_spotlight")
                .ok()
                .flatten()
                .is_some()
    }
    #[cfg(not(target_os = "macos"))]
    {
        let _ = path;
        true
    }
}

fn io_error(operation: &'static str, path: &Path, source: io::Error) -> VaultError {
    VaultError::Io {
        operation,
        path: path.to_path_buf(),
        source,
    }
}

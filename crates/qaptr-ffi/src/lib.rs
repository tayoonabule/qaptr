//! Narrow C ABI for the native capture helper.
//!
//! # Invariants
//!
//! - This bridge exposes only vault creation, public-key lookup, sealing, and
//!   destruction. It has no operation that reads a bundle or accepts a private
//!   key.
//! - The helper supplies a generation identifier and receives only that
//!   generation's public key. The Keychain and all decryption material remain
//!   outside this library and outside the helper process.
//! - A failed seal is delegated to `qaptr-vault`, whose temporary directory is
//!   removed before the error crosses this boundary. No partially written
//!   bundle is made readable.

#![allow(unsafe_code)]

use std::{slice, str};

use qaptr_domain::CaptureId;
use qaptr_vault::{BundleInput, GenerationId, GenerationPublicKey, SampledContext, Vault};

/// An opaque helper-owned vault handle.
pub struct QaptrVault {
    vault: Vault,
    last_error: String,
}

/// Creates a vault handle rooted at a UTF-8 path.
///
/// A null return indicates invalid input or a filesystem failure. The caller
/// owns the returned handle and must release it with [`qaptr_vault_destroy`].
///
/// # Safety
///
/// `root` must point to `root_len` readable bytes for the duration of the
/// call, or be null when `root_len` is zero.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qaptr_vault_create(root: *const u8, root_len: usize) -> *mut QaptrVault {
    let Some(root) = (unsafe { read_utf8(root, root_len) }) else {
        return std::ptr::null_mut();
    };
    match Vault::new(root) {
        Ok(vault) => Box::into_raw(Box::new(QaptrVault {
            vault,
            last_error: String::new(),
        })),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Destroys a handle returned by [`qaptr_vault_create`].
///
/// # Safety
///
/// `handle` must be null or a live pointer returned by
/// [`qaptr_vault_create`] that has not already been destroyed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qaptr_vault_destroy(handle: *mut QaptrVault) {
    if !handle.is_null() {
        // SAFETY: the pointer came from `Box::into_raw` in the create function
        // and is consumed exactly once by this destructor.
        unsafe { drop(Box::from_raw(handle)) };
    }
}

/// Copies a generation public key into a caller-provided buffer.
///
/// The return value is the required buffer size, including the trailing NUL.
/// A zero return means the handle or generation identifier was invalid. The
/// function reads only the public-key file and never calls a credentials port.
///
/// # Safety
///
/// `handle` must be a live handle. The byte pointers must reference readable
/// input buffers for the duration of the call. `output` must reference a
/// writable buffer of `output_capacity` bytes when the capacity is non-zero.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qaptr_vault_public_key(
    handle: *mut QaptrVault,
    generation: *const u8,
    generation_len: usize,
    output: *mut u8,
    output_capacity: usize,
) -> usize {
    let Some(handle) = (unsafe { handle.as_mut() }) else {
        return 0;
    };
    let Some(generation) = (unsafe { read_utf8(generation, generation_len) }) else {
        handle.last_error = "generation id is not UTF-8".to_owned();
        return 0;
    };
    let generation_id = match GenerationId::new(generation) {
        Ok(value) => value,
        Err(error) => {
            handle.last_error = error.to_string();
            return 0;
        }
    };
    let public_key = match handle.vault.public_key(&generation_id) {
        Ok(value) => value,
        Err(error) => {
            handle.last_error = error.to_string();
            return 0;
        }
    };
    copy_string(public_key.as_str(), output, output_capacity)
}

/// Seals one downscaled image and its point-in-time context.
///
/// The helper must pass only a generation public key. This function has no
/// private-key parameter by design. The return value is zero on success and a
/// negative value on failure; call [`qaptr_vault_last_error`] for details.
///
/// # Safety
///
/// `handle` must be live. All input pointers must reference readable buffers
/// for their declared lengths, or be null only when the corresponding length
/// is zero.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qaptr_vault_seal(
    handle: *mut QaptrVault,
    capture_id: *const u8,
    capture_id_len: usize,
    generation: *const u8,
    generation_len: usize,
    public_key: *const u8,
    public_key_len: usize,
    image: *const u8,
    image_len: usize,
    context: *const u8,
    context_len: usize,
) -> i32 {
    let Some(handle) = (unsafe { handle.as_mut() }) else {
        return -1;
    };
    let Some(capture_id) = (unsafe { read_utf8(capture_id, capture_id_len) }) else {
        return fail(handle, "capture id is not UTF-8");
    };
    let Some(generation) = (unsafe { read_utf8(generation, generation_len) }) else {
        return fail(handle, "generation id is not UTF-8");
    };
    let Some(public_key) = (unsafe { read_utf8(public_key, public_key_len) }) else {
        return fail(handle, "public key is not UTF-8");
    };
    let Some(image) = (unsafe { read_bytes(image, image_len) }) else {
        return fail(handle, "image pointer is null");
    };
    let Some(context) = (unsafe { read_bytes(context, context_len) }) else {
        return fail(handle, "context pointer is null");
    };

    let capture_id = match CaptureId::new(capture_id) {
        Ok(value) => value,
        Err(error) => return fail(handle, &error.to_string()),
    };
    let generation = match GenerationId::new(generation) {
        Ok(value) => value,
        Err(error) => return fail(handle, &error.to_string()),
    };
    let public_key = match public_key.parse::<GenerationPublicKey>() {
        Ok(value) => value,
        Err(error) => return fail(handle, &error.to_string()),
    };
    let input = BundleInput::new(
        capture_id,
        generation,
        image.to_vec(),
        SampledContext::new(context.to_vec()),
        Vec::new(),
    );

    match handle.vault.seal(&input, &public_key) {
        Ok(_) => {
            handle.last_error.clear();
            0
        }
        Err(error) => fail(handle, &error.to_string()),
    }
}

/// Copies the most recent error into a caller-provided buffer.
///
/// The return value is the required buffer size, including the trailing NUL.
/// A zero return means the handle is null.
///
/// # Safety
///
/// `handle` must be live. `output` must reference a writable buffer of
/// `output_capacity` bytes when the capacity is non-zero.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qaptr_vault_last_error(
    handle: *mut QaptrVault,
    output: *mut u8,
    output_capacity: usize,
) -> usize {
    let Some(handle) = (unsafe { handle.as_ref() }) else {
        return 0;
    };
    copy_string(&handle.last_error, output, output_capacity)
}

fn fail(handle: &mut QaptrVault, message: &str) -> i32 {
    handle.last_error = message.to_owned();
    -1
}

unsafe fn read_utf8<'a>(pointer: *const u8, length: usize) -> Option<&'a str> {
    unsafe { read_bytes(pointer, length) }.and_then(|bytes| str::from_utf8(bytes).ok())
}

unsafe fn read_bytes<'a>(pointer: *const u8, length: usize) -> Option<&'a [u8]> {
    if length == 0 {
        return Some(&[]);
    }
    (!pointer.is_null()).then(|| unsafe { slice::from_raw_parts(pointer, length) })
}

fn copy_string(value: &str, output: *mut u8, capacity: usize) -> usize {
    let required = value.len() + 1;
    if capacity >= required && !output.is_null() {
        // SAFETY: the caller supplied a buffer of `capacity` bytes and the
        // preceding capacity check proves the writes stay within it.
        unsafe {
            std::ptr::copy_nonoverlapping(value.as_ptr(), output, value.len());
            output.add(value.len()).write(0);
        }
    }
    required
}

#[cfg(test)]
mod tests {
    use std::fs;

    use qaptr_vault::{GenerationId, GenerationKeypair};

    use super::*;

    #[test]
    fn invalid_seal_leaves_no_readable_partial_bundle() {
        let root = tempfile::tempdir().expect("temporary root");
        let generation = GenerationId::new("generation-1").expect("generation");
        let path = root.path().to_string_lossy().into_owned();
        let handle = unsafe { qaptr_vault_create(path.as_bytes().as_ptr(), path.len()) };
        assert!(!handle.is_null());
        let result = unsafe {
            qaptr_vault_seal(
                handle,
                b"capture-1".as_ptr(),
                b"capture-1".len(),
                generation.as_str().as_ptr(),
                generation.as_str().len(),
                b"not-a-public-key".as_ptr(),
                b"not-a-public-key".len(),
                b"image".as_ptr(),
                5,
                b"{}".as_ptr(),
                2,
            )
        };
        assert_eq!(result, -1);
        assert!(!root.path().join("bundles/capture-1").exists());
        let entries = fs::read_dir(root.path().join("bundles"))
            .expect("bundle directory")
            .collect::<Result<Vec<_>, _>>()
            .expect("bundle entries");
        assert!(entries.is_empty());
        unsafe { qaptr_vault_destroy(handle) };
    }

    #[test]
    fn public_key_lookup_does_not_require_private_material() {
        let root = tempfile::tempdir().expect("temporary root");
        let generation = GenerationId::new("generation-1").expect("generation");
        let keypair = GenerationKeypair::generate(generation.clone());
        let vault = Vault::new(root.path()).expect("vault");
        vault
            .register_public_key(&generation, keypair.public_key())
            .expect("public key");
        let path = root.path().to_string_lossy().into_owned();
        let handle = unsafe { qaptr_vault_create(path.as_bytes().as_ptr(), path.len()) };
        assert!(!handle.is_null());
        let mut output = [0_u8; 128];
        let required = unsafe {
            qaptr_vault_public_key(
                handle,
                generation.as_str().as_ptr(),
                generation.as_str().len(),
                output.as_mut_ptr(),
                output.len(),
            )
        };
        assert_eq!(
            std::str::from_utf8(&output[..required - 1]).expect("public key utf8"),
            keypair.public_key().as_str()
        );
        unsafe { qaptr_vault_destroy(handle) };
    }
}

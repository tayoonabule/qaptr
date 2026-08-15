//! Byte-buffer helpers shared by every review-ffi entry point.

use std::{slice, str};

/// Reads `length` bytes as a UTF-8 string, or `None` on invalid input.
///
/// # Safety
///
/// `pointer` must reference `length` readable bytes for the duration of the
/// call, or be null when `length` is zero.
pub(crate) unsafe fn read_utf8<'a>(pointer: *const u8, length: usize) -> Option<&'a str> {
    unsafe { read_bytes(pointer, length) }.and_then(|bytes| str::from_utf8(bytes).ok())
}

/// Reads `length` bytes, or `None` when the pointer is null and non-empty.
///
/// # Safety
///
/// `pointer` must reference `length` readable bytes for the duration of the
/// call, or be null when `length` is zero.
pub(crate) unsafe fn read_bytes<'a>(pointer: *const u8, length: usize) -> Option<&'a [u8]> {
    if length == 0 {
        return Some(&[]);
    }
    (!pointer.is_null()).then(|| unsafe { slice::from_raw_parts(pointer, length) })
}

/// Copies `value` plus a trailing NUL into `output` if `capacity` is
/// sufficient, always returning the required capacity.
///
/// # Safety
///
/// `output` must reference a writable buffer of `capacity` bytes when
/// `capacity` is non-zero.
pub(crate) fn copy_string(value: &str, output: *mut u8, capacity: usize) -> usize {
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

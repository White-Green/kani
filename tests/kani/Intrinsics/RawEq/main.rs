// Copyright Kani Contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Check that we get the expected results for the `raw_eq` intrinsic
#![feature(core_intrinsics)]
use std::intrinsics::raw_eq;
#[cfg(windows)]
use std::slice;

// On Windows, `raw_eq` may lower to a `memcmp` call that is not provided by
// the harness environment. Provide a local model for this regression.
#[cfg(windows)]
#[no_mangle]
pub unsafe extern "C" fn memcmp(lhs: *const u8, rhs: *const u8, len: usize) -> i32 {
    let left = unsafe { slice::from_raw_parts(lhs, len) };
    let right = unsafe { slice::from_raw_parts(rhs, len) };
    for (a, b) in left.iter().zip(right.iter()) {
        if a != b {
            return i32::from(*a) - i32::from(*b);
        }
    }
    0
}

#[kani::proof]
fn main() {
    let raw_eq_i32_true: bool = unsafe { raw_eq(&42_i32, &42) };
    assert!(raw_eq_i32_true);

    let raw_eq_i32_false: bool = unsafe { raw_eq(&4_i32, &2) };
    assert!(!raw_eq_i32_false);

    let raw_eq_char_true: bool = unsafe { raw_eq(&'a', &'a') };
    assert!(raw_eq_char_true);

    let raw_eq_char_false: bool = unsafe { raw_eq(&'a', &'A') };
    assert!(!raw_eq_char_false);

    let raw_eq_array_true: bool = unsafe { raw_eq(&[13_u8, 42], &[13, 42]) };
    assert!(raw_eq_array_true);

    let raw_eq_array_false: bool = unsafe { raw_eq(&[13_u8, 42], &[42, 13]) };
    assert!(!raw_eq_array_false);
}

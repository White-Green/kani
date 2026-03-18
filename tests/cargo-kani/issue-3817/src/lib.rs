// Copyright Kani Contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
//! Check that Kani can compile a crate that depends on bzip, and the analysis will only
//! fail if a missing symbol is reachable.

use bzip2::Compression;
use std::ffi::c_void;

unsafe extern "C" {
    fn BZ2_bzCompressInit(
        stream: *mut c_void,
        block_size_100k: i32,
        verbosity: i32,
        work_factor: i32,
    ) -> i32;
}

#[kani::proof]
fn check_missing_extern_fn() {
    // Keep using bzip2 in this crate while invoking the foreign function directly.
    let _ = Compression::best();
    let stream: *mut c_void = std::ptr::null_mut();
    let block_size_100k = kani::any_where(|v: &i32| (1..=9).contains(v));
    let verbosity = kani::any_where(|v: &i32| (0..=4).contains(v));
    let work_factor = kani::any_where(|v: &i32| (0..=250).contains(v));
    let _ = unsafe { BZ2_bzCompressInit(stream, block_size_100k, verbosity, work_factor) };
}

#[kani::proof]
fn check_unreachable_extern_fn() {
    let positive = kani::any_where(|v: &i8| *v > 0);
    if positive == 0 {
        // This should be unreachable so verification should succeed.
        check_missing_extern_fn();
    }
}

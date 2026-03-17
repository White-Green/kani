// Copyright Kani Contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
//! Check that Kani can compile a crate that depends on bzip, and the analysis will only
//! fail if a missing symbol is reachable.

use bzip2::Compression;
use bzip2_sys::{BZ2_bzCompressInit, bz_stream};

#[kani::proof]
fn check_missing_extern_fn() {
    // Keep using the safe crate so we still depend on bzip2 in this test.
    let _ = Compression::best();
    // Trigger the missing foreign call without heap allocations that are slow on Windows.
    let mut stream: bz_stream = unsafe { std::mem::zeroed() };
    let block_size = kani::any_where(|v: &i32| (1..=9).contains(v));
    let verbosity = kani::any_where(|v: &i32| (0..=4).contains(v));
    let work_factor = kani::any_where(|v: &i32| (0..=250).contains(v));
    let _ = unsafe { BZ2_bzCompressInit(&mut stream, block_size, verbosity, work_factor) };
}

#[kani::proof]
fn check_unreachable_extern_fn() {
    let positive = kani::any_where(|v: &i8| *v > 0);
    if positive == 0 {
        // This should be unreachable so verification should succeed.
        check_missing_extern_fn();
    }
}

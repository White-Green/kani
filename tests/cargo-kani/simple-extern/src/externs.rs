// Copyright Kani Contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

#[no_mangle]
pub extern "C" fn external_c_assertion(i: u32) -> u32 {
    rust_add1(i)
}

#[no_mangle]
pub extern "C" fn rust_add1(i: u32) -> u32 {
    i + 1
}

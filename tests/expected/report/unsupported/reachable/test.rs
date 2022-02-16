// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0 OR MIT
// kani-flags: --output-format regular --no-default-checks

#![feature(asm)]
fn unsupp(x: &mut u8) {
    unsafe {
        std::arch::asm!("nop");
    }
}

fn main() {
    let mut x = 0;
    unsupp(&mut x);
    assert!(x == 0);
}
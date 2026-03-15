// Copyright Kani Contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// ignore-windows

#[kani::proof]
fn main() {
    let cond: bool = kani::any();
    kani::assume(cond);
    assert!(cond);
}

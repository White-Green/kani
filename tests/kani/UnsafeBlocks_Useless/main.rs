// Copyright Kani Contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// ignore-windows
#[kani::proof]
fn main() {
    let x = unsafe {
        assert!(true);
        5
    };

    assert!(x == 5);
}

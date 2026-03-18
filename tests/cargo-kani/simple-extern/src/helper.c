// Copyright Kani Contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

typedef unsigned int uint32_t;

uint32_t rust_add1(uint32_t i);

uint32_t external_c_assertion(uint32_t x)
{
    return rust_add1(x);
}

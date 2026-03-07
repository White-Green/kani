// Copyright Kani Contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

use anyhow::{Context, Result};
use std::ffi::OsString;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use crate::session::KaniSession;

impl KaniSession {
    #[cfg(windows)]
    pub(crate) fn normalize_tool_path(path: &Path) -> OsString {
        let path_str = path.as_os_str().to_string_lossy();
        if let Some(stripped) = path_str.strip_prefix(r"\\?\UNC\") {
            return OsString::from(format!(r"\\{stripped}"));
        }
        if let Some(stripped) = path_str.strip_prefix(r"\\?\") {
            return OsString::from(stripped);
        }
        path.as_os_str().to_owned()
    }

    #[cfg(not(windows))]
    pub(crate) fn normalize_tool_path(path: &Path) -> OsString {
        path.as_os_str().to_owned()
    }

    /// Given a set of goto binaries (`inputs`), produce `output` by linking everything
    /// together (including essential libraries). The result is generic over all proof harnesses.
    pub fn link_goto_binary(&self, inputs: &[PathBuf], output: &Path) -> Result<()> {
        #[cfg(windows)]
        if inputs.len() == 1 {
            // Work around goto-cc crashes on Windows with long mangled artifact names.
            let short_input = output.with_file_name("kani-link-input.symtab.out");
            let short_output = output.with_file_name("kani-link-output.out");

            fs::copy(&inputs[0], &short_input).with_context(|| {
                format!(
                    "Failed to create temporary goto input {} from {}",
                    short_input.display(),
                    inputs[0].display()
                )
            })?;

            let mut args: Vec<OsString> = Vec::new();
            args.push(Self::normalize_tool_path(&short_input));
            // On Windows, avoid passing C library sources to goto-cc in this link step.
            // These sources are not required for std-checks and have caused frequent crashes.
            args.push("-o".into());
            args.push(Self::normalize_tool_path(&short_output));

            let mut cmd = Command::new("goto-cc");
            cmd.args(args);
            let link_result = self.run_suppress(cmd);

            let _ = fs::remove_file(&short_input);
            link_result?;

            fs::rename(&short_output, output).with_context(|| {
                format!(
                    "Failed to move temporary goto output {} to {}",
                    short_output.display(),
                    output.display()
                )
            })?;
            return Ok(());
        }

        let mut args: Vec<OsString> = Vec::new();
        args.extend(inputs.iter().map(|x| Self::normalize_tool_path(x)));
        #[cfg(not(windows))]
        args.extend(self.args.c_lib.iter().map(|x| Self::normalize_tool_path(x)));

        // TODO think about this: kani_lib_c is just an empty c file. Maybe we could just
        // create such an empty file ourselves instead of having to look up this path.
        #[cfg(not(windows))]
        args.push(Self::normalize_tool_path(&self.kani_lib_c));

        args.push("-o".into());
        args.push(Self::normalize_tool_path(output));

        let mut cmd = Command::new("goto-cc");
        cmd.args(args);

        self.run_suppress(cmd)?;

        Ok(())
    }

    /// Produce a goto binary with its entry point set to a particular proof harness.
    pub fn specialize_to_proof_harness(
        &self,
        input: &Path,
        output: &Path,
        function: &str,
    ) -> Result<()> {
        let mut cmd = Command::new("goto-cc");
        cmd.arg(Self::normalize_tool_path(input))
            .args(["--function", function, "-o"])
            .arg(Self::normalize_tool_path(output));

        self.run_suppress(cmd)?;

        Ok(())
    }
}

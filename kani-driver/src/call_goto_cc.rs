// Copyright Kani Contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

use anyhow::{Context, Result};
use std::ffi::OsString;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
#[cfg(windows)]
use std::sync::atomic::{AtomicU64, Ordering};

use crate::session::KaniSession;

impl KaniSession {
    #[cfg(windows)]
    fn goto_cc_frontend() -> &'static str {
        if which::which("goto-cc").is_ok() {
            "goto-cc"
        } else if which::which("goto-cl").is_ok() {
            "goto-cl"
        } else {
            "goto-cc"
        }
    }

    #[cfg(not(windows))]
    fn goto_cc_frontend() -> &'static str {
        "goto-cc"
    }

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
            static LINK_TMP_COUNTER: AtomicU64 = AtomicU64::new(0);
            let unique = LINK_TMP_COUNTER.fetch_add(1, Ordering::Relaxed);
            // Work around goto-cc crashes on Windows with long mangled artifact names.
            let short_input = output.with_file_name(format!(
                "kani-link-input-{}-{}.symtab.out",
                std::process::id(),
                unique
            ));
            let short_output = output.with_file_name(format!(
                "kani-link-output-{}-{}.out",
                std::process::id(),
                unique
            ));

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

            let mut cmd = Command::new(Self::goto_cc_frontend());
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

        let mut cmd = Command::new(Self::goto_cc_frontend());
        cmd.args(args);

        self.run_suppress(cmd)?;

        Ok(())
    }

    /// Produce a goto binary with its entry point set to a particular proof harness.
    #[cfg(windows)]
    pub fn specialize_to_proof_harness(
        &self,
        input: &Path,
        output: &Path,
        function: &str,
    ) -> Result<()> {
        static SPECIALIZE_TMP_COUNTER: AtomicU64 = AtomicU64::new(0);
        // Use short temporary paths to avoid Windows path-length and in-place rewrite issues.
        let unique = SPECIALIZE_TMP_COUNTER.fetch_add(1, Ordering::Relaxed);
        let temp_input = output.with_file_name(format!(
            "kani-specialize-input-{}-{}.out",
            std::process::id(),
            unique
        ));
        let temp_output =
            output.with_file_name(format!("kani-specialize-{}-{}.out", std::process::id(), unique));
        fs::copy(input, &temp_input).with_context(|| {
            format!(
                "Failed to create temporary goto input {} from {}",
                temp_input.display(),
                input.display()
            )
        })?;

        let mut cmd = Command::new(Self::goto_cc_frontend());
        cmd.arg(Self::normalize_tool_path(&temp_input))
            .args(["--function", function, "-o"])
            .arg(Self::normalize_tool_path(&temp_output));

        let result = self.run_suppress(cmd);
        let _ = fs::remove_file(&temp_input);
        if result.is_err() {
            let _ = fs::remove_file(&temp_output);
            return result;
        }

        if input == output {
            let _ = fs::remove_file(output);
        }
        fs::rename(&temp_output, output).with_context(|| {
            format!(
                "Failed to move temporary specialized goto {} to {}",
                temp_output.display(),
                output.display()
            )
        })?;
        Ok(())
    }

    /// Produce a goto binary with its entry point set to a particular proof harness.
    #[cfg(not(windows))]
    pub fn specialize_to_proof_harness(
        &self,
        input: &Path,
        output: &Path,
        function: &str,
    ) -> Result<()> {
        let mut cmd = Command::new(Self::goto_cc_frontend());
        cmd.arg(Self::normalize_tool_path(input))
            .args(["--function", function, "-o"])
            .arg(Self::normalize_tool_path(output));

        self.run_suppress(cmd)?;

        Ok(())
    }
}

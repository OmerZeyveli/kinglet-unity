# Kinglet Platform Spike — Dependency Provenance

Every dependency the spike distributes. `usage` says what a row is for:
`direct-toolchain` builds a candidate, `runtime-candidate` is linked into
one, `unity-probe` belongs to the Unity probe. **None of these is yet a
product dependency** — this is a spike, and the runtime is not selected.

Checksums carry their algorithm because the ecosystems disagree: NuGet
publishes base64 SHA-512, Microsoft publishes hex SHA-512 for SDK
artifacts, crates.io and PyPI publish hex SHA-256, and the Unity MCP
package is pinned by git commit. A digest relabelled to fit one column
verifies against nothing while reading as verified.

| Ecosystem | Name | Version / commit | Licence | Usage | Owner | Checksum |
| --- | --- | --- | --- | --- | --- | --- |
| cargo | `ed25519-dalek` | `3.0.0` | BSD-3-Clause | runtime-candidate | rust | `6ebaa1a2bf1290ab…` (sha256) |
| cargo | `hex` | `0.4.3` | MIT OR Apache-2.0 | runtime-candidate | rust | `7f24254aa9a54b5c…` (sha256) |
| cargo | `sha2` | `0.10.9` | MIT OR Apache-2.0 | runtime-candidate | rust | `a7507d819769d01a…` (sha256) |
| nuget | `NSec.Cryptography` | `26.4.0` | MIT | runtime-candidate | dotnet | `0vsCtY5f+YgQROiW…` (sha512-base64) |
| pypi | `cryptography` | `49.0.0` | Apache-2.0 OR BSD-3-Clause | runtime-candidate | python-bundled | `f89660a348f4f78a…` (sha256) |
| toolchain | `.NET SDK (ubuntu-lts-x64)` | `10.0.302` | MIT | direct-toolchain | dotnet | `10069bec87835964…` (sha512) |
| toolchain | `CPython (ubuntu-lts-x64)` | `3.14.6` | PSF-2.0 | direct-toolchain | python-bundled | `c172314f4a8ec137…` (sha256) |
| toolchain | `Go (ubuntu-lts-x64)` | `1.26.5` | BSD-3-Clause | direct-toolchain | go | `5c2c3b16caefa1d9…` (sha256) |
| toolchain | `Go (windows-10-x64)` | `1.26.5` | BSD-3-Clause | direct-toolchain | go | `97e6b2a833b6d89f…` (sha256) |
| toolchain | `Rust (ubuntu-lts-x64)` | `1.97.1` | MIT OR Apache-2.0 | direct-toolchain | rust | `b4cdbc7cc6b0ee0a…` (sha256) |
| toolchain | `uv (ubuntu-lts-x64)` | `0.11.28` | MIT | direct-toolchain | python-bundled | `e490a6464492183c…` (sha256) |
| unity-package | `com.coplaydev.unity-mcp` | `v9.7.1` | MIT | unity-probe | unity-mcp | `78ee5418415953b7…` (git-commit) |

## Licences not recorded

**64** transitive dependencies are checksummed by their ecosystem lockfile and have **no SPDX licence recorded anywhere in this repository**. They are distributed inside the candidate binaries all the same.

They are listed rather than dropped on purpose: a report that silently omitted them would read as complete, and the omission would be invisible to exactly the reader who needs it. Establishing these licences is real work and it has not been done.

| Ecosystem | Name | Version | Owner |
| --- | --- | --- | --- |
| cargo | `block-buffer` | `0.10.4` | rust |
| cargo | `block-buffer` | `0.12.1` | rust |
| cargo | `bumpalo` | `3.20.3` | rust |
| cargo | `cfg-if` | `1.0.4` | rust |
| cargo | `cpufeatures` | `0.2.17` | rust |
| cargo | `cpufeatures` | `0.3.0` | rust |
| cargo | `crypto-common` | `0.1.7` | rust |
| cargo | `crypto-common` | `0.2.2` | rust |
| cargo | `curve25519-dalek` | `5.0.0` | rust |
| cargo | `curve25519-dalek-derive` | `0.1.1` | rust |
| cargo | `digest` | `0.10.7` | rust |
| cargo | `digest` | `0.11.3` | rust |
| cargo | `ed25519` | `3.0.0` | rust |
| cargo | `fiat-crypto` | `0.3.0` | rust |
| cargo | `futures-core` | `0.3.33` | rust |
| cargo | `futures-task` | `0.3.33` | rust |
| cargo | `futures-util` | `0.3.33` | rust |
| cargo | `generic-array` | `0.14.7` | rust |
| cargo | `getrandom` | `0.4.3` | rust |
| cargo | `hybrid-array` | `0.4.13` | rust |
| cargo | `itoa` | `1.0.18` | rust |
| cargo | `js-sys` | `0.3.103` | rust |
| cargo | `libc` | `0.2.189` | rust |
| cargo | `memchr` | `2.8.3` | rust |
| cargo | `once_cell` | `1.21.4` | rust |
| cargo | `pin-project-lite` | `0.2.17` | rust |
| cargo | `proc-macro2` | `1.0.107` | rust |
| cargo | `quote` | `1.0.47` | rust |
| cargo | `r-efi` | `6.0.0` | rust |
| cargo | `rustc_version` | `0.4.1` | rust |
| cargo | `rustversion` | `1.0.23` | rust |
| cargo | `semver` | `1.0.28` | rust |
| cargo | `serde` | `1.0.229` | rust |
| cargo | `serde_core` | `1.0.229` | rust |
| cargo | `serde_derive` | `1.0.229` | rust |
| cargo | `serde_json` | `1.0.151` | rust |
| cargo | `sha2` | `0.11.0` | rust |
| cargo | `signature` | `3.0.0` | rust |
| cargo | `slab` | `0.4.12` | rust |
| cargo | `subtle` | `2.6.1` | rust |
| cargo | `syn` | `2.0.119` | rust |
| cargo | `syn` | `3.0.3` | rust |
| cargo | `typenum` | `1.20.1` | rust |
| cargo | `unicode-ident` | `1.0.24` | rust |
| cargo | `uuid` | `1.24.0` | rust |
| cargo | `version_check` | `0.9.5` | rust |
| cargo | `wasm-bindgen` | `0.2.126` | rust |
| cargo | `wasm-bindgen-macro` | `0.2.126` | rust |
| cargo | `wasm-bindgen-macro-support` | `0.2.126` | rust |
| cargo | `wasm-bindgen-shared` | `0.2.126` | rust |
| cargo | `zeroize` | `1.9.0` | rust |
| cargo | `zmij` | `1.0.23` | rust |
| nuget | `Microsoft.NET.ILLink.Tasks` | `10.0.10` | dotnet |
| nuget | `libsodium` | `1.0.22` | dotnet |
| pypi | `altgraph` | `0.17.5` | python-bundled |
| pypi | `cffi` | `2.1.0` | python-bundled |
| pypi | `macholib` | `1.16.4` | python-bundled |
| pypi | `packaging` | `26.2` | python-bundled |
| pypi | `pefile` | `2024.8.26` | python-bundled |
| pypi | `pycparser` | `3.0` | python-bundled |
| pypi | `pyinstaller` | `6.21.0` | python-bundled |
| pypi | `pyinstaller-hooks-contrib` | `2026.6` | python-bundled |
| pypi | `pywin32-ctypes` | `0.2.3` | python-bundled |
| pypi | `setuptools` | `83.0.0` | python-bundled |

## Declared pins the lockfile did not resolve to

**3** direct dependencies are declared in `toolchains.lock.json` at a version the ecosystem lockfile did not resolve. The lockfile is what was actually built and measured, so where these disagree the declared pin is stale and every published measurement was taken against the resolved version instead.

The declared licence is **not** carried over to the resolved version: that would assume the package did not relicense in between, which is the kind of assumption this record exists to stop making. Until the lock is corrected these appear above as unlicensed.

| Ecosystem | Name | Declared | Resolved | Owner | Declared licence |
| --- | --- | --- | --- | --- | --- |
| cargo | `serde` | `1.0.219` | `1.0.229` | rust | MIT OR Apache-2.0 |
| cargo | `serde_json` | `1.0.140` | `1.0.151` | rust | MIT OR Apache-2.0 |
| cargo | `uuid` | `1.16.0` | `1.24.0` | rust | MIT OR Apache-2.0 |

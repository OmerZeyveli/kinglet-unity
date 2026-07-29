"""00D Task 3 — the supply-chain record, and what it refuses to say.

Every dependency the spike distributes, with the fields a distribution actually
needs: name, exact version or commit, source URL, SPDX licence, usage, owner,
and a checksum WITH its algorithm.

The algorithm is a separate field because the ecosystems do not agree. Microsoft
publishes base64 SHA-512 for NuGet `contentHash`; Go, Rust and Astral publish
hex SHA-256; the Unity MCP package is pinned by a 40-hex git commit. A single
`sha256` field cannot hold all three without either mislabelling a digest or
throwing away the authoritative one and substituting a value nobody published.

Two properties this file exists to hold:

* **Nothing enters `items` with a field missing.** A supply-chain record with a
  blank licence column is worse than no record: it looks like diligence.
* **The gap is reported, not swallowed.** Transitive dependencies carry
  checksums in their ecosystem lockfiles but no recorded licence anywhere in
  this repo. They are distributed all the same, so they are counted and named in
  `unlicensed` rather than quietly dropped — dropping them would make the report
  complete-looking and the omission invisible.
"""
from __future__ import annotations

import unittest
from pathlib import Path

from tools.kinglet_spike.model import EvidenceError
from tools.kinglet_spike.provenance import (
    ProvenanceItem,
    build_provenance,
    merge_records,
)

REPO = Path(__file__).resolve().parents[2]


def record(license_spdx: str = "MIT", checksum: str = "a" * 64) -> ProvenanceItem:
    return ProvenanceItem(
        ecosystem="nuget",
        name="NSec.Cryptography",
        version_or_commit="26.4.0",
        source_url="https://www.nuget.org/packages/NSec.Cryptography/26.4.0",
        license_spdx=license_spdx,
        usage="runtime-candidate",
        owner="dotnet",
        checksum=checksum,
        checksum_algorithm="sha512-base64",
    )


class MergeTests(unittest.TestCase):
    def test_the_same_package_version_merges_to_one_row(self):
        merged = merge_records([record(), record()])
        self.assertEqual(1, len(merged))

    def test_same_package_version_cannot_have_conflicting_license(self):
        with self.assertRaisesRegex(EvidenceError, "E_PROVENANCE"):
            merge_records([record("MIT"), record("Apache-2.0")])

    def test_same_package_version_cannot_have_conflicting_checksum(self):
        # The sharper conflict: two digests for one artifact means one of the two
        # readers is looking at something else, and silently keeping either is
        # how a supply-chain record starts describing a package nobody shipped.
        with self.assertRaisesRegex(EvidenceError, "E_PROVENANCE"):
            merge_records([record(checksum="a" * 64), record(checksum="b" * 64)])

    def test_merged_records_are_sorted_and_frozen(self):
        other = ProvenanceItem(
            ecosystem="cargo", name="serde", version_or_commit="1.0.219",
            source_url="https://crates.io/crates/serde/1.0.219",
            license_spdx="MIT OR Apache-2.0", usage="runtime-candidate",
            owner="rust", checksum="c" * 64, checksum_algorithm="sha256",
        )
        merged = merge_records([record(), other])
        self.assertIsInstance(merged, tuple)
        self.assertEqual(
            sorted(merged, key=lambda i: (i.ecosystem, i.name, i.version_or_commit)),
            list(merged),
        )


class RequiredFieldTests(unittest.TestCase):
    def test_every_dependency_has_required_distribution_fields(self):
        for item in build_provenance(REPO).items:
            with self.subTest(item=item.name):
                self.assertTrue(item.name)
                self.assertTrue(item.version_or_commit)
                self.assertTrue(item.source_url.startswith("https://"))
                self.assertTrue(item.license_spdx)
                self.assertTrue(item.usage)
                self.assertTrue(item.owner)
                self.assertTrue(item.checksum)
                self.assertTrue(item.checksum_algorithm)

    def test_a_record_missing_a_field_is_refused_rather_than_defaulted(self):
        with self.assertRaisesRegex(EvidenceError, "E_PROVENANCE"):
            merge_records([record(license_spdx="")])

    def test_the_checksum_matches_the_shape_its_algorithm_declares(self):
        # A base64 SHA-512 in a field labelled sha256 is a mislabelled digest,
        # and mislabelled is worse than absent: it verifies against nothing and
        # reads as verified.
        for item in build_provenance(REPO).items:
            with self.subTest(item=f"{item.name}@{item.version_or_commit}"):
                if item.checksum_algorithm == "sha256":
                    self.assertRegex(item.checksum, r"^[0-9a-f]{64}$")
                elif item.checksum_algorithm == "sha512":
                    self.assertRegex(item.checksum, r"^[0-9a-f]{128}$")
                elif item.checksum_algorithm == "git-commit":
                    self.assertRegex(item.checksum, r"^[0-9a-f]{40}$")
                else:
                    self.assertEqual("sha512-base64", item.checksum_algorithm)


class RealTreeTests(unittest.TestCase):
    def setUp(self):
        self.report = build_provenance(REPO)

    def test_all_four_candidates_are_represented(self):
        owners = {item.owner for item in self.report.items}
        for candidate in ("python-bundled", "rust", "go", "dotnet"):
            self.assertIn(candidate, owners)

    def test_the_unity_mcp_pin_is_recorded_by_its_commit(self):
        mcp = [i for i in self.report.items if i.ecosystem == "unity-package"]
        self.assertEqual(1, len(mcp))
        self.assertEqual("git-commit", mcp[0].checksum_algorithm)
        self.assertEqual(
            "78ee5418415953b79c358bfe6355fcc3fde7912b", mcp[0].checksum
        )

    def test_probe_only_dependencies_are_labelled_as_such(self):
        # The plan's words: probe-only dependencies must not be mistaken for
        # future PRODUCT dependencies. PyInstaller is the clearest case -- it
        # packages the python candidate and ships in nothing.
        usages = {item.usage for item in self.report.items}
        self.assertIn("direct-toolchain", usages)
        self.assertIn("runtime-candidate", usages)

    def test_unrecorded_transitive_licenses_are_counted_not_dropped(self):
        # These ARE distributed. Dropping them would leave a report that looks
        # complete; this makes the omission a number a reader can see.
        self.assertTrue(
            self.report.unlicensed,
            "every transitive suddenly has a licence — verify before believing it",
        )
        for entry in self.report.unlicensed:
            self.assertTrue(entry.checksum)
            self.assertFalse(entry.license_spdx)

    def test_no_item_is_both_licensed_and_unlicensed(self):
        keyed = {(i.ecosystem, i.name, i.version_or_commit) for i in self.report.items}
        for entry in self.report.unlicensed:
            self.assertNotIn(
                (entry.ecosystem, entry.name, entry.version_or_commit), keyed
            )

    def test_a_declared_pin_that_the_lockfile_did_not_resolve_is_reported(self):
        # Found by this tooling on first run: toolchains.lock.json declares serde
        # 1.0.219, serde_json 1.0.140 and uuid 1.16.0, while Cargo.lock resolved
        # 1.0.229, 1.0.151 and 1.24.0 — so the human-facing pin record disagrees
        # with what was actually built and measured.
        #
        # It must not vanish into `unlicensed`, where it would look like an
        # ordinary transitive nobody licensed. And the declared licence must NOT
        # be applied to the resolved version: that is an assumption, and the
        # whole point here is to stop assuming.
        mismatched = {m.name for m in self.report.declared_version_mismatches}
        self.assertIn("serde", mismatched)
        for entry in self.report.declared_version_mismatches:
            self.assertNotEqual(entry.declared_version, entry.resolved_version)
            self.assertTrue(entry.resolved_version)

    def test_generation_is_deterministic(self):
        self.assertEqual(build_provenance(REPO).items, self.report.items)

    def test_no_network_is_needed(self):
        # A report that reaches the network is a report that differs by day and
        # cannot be regenerated from a checkout.
        import socket

        original = socket.socket

        def refuse(*args, **kwargs):
            raise AssertionError("provenance generation opened a socket")

        socket.socket = refuse
        try:
            build_provenance(REPO)
        finally:
            socket.socket = original


class RenderTests(unittest.TestCase):
    def setUp(self):
        from tools.kinglet_spike.provenance import (
            render_provenance_json,
            render_provenance_markdown,
        )

        self.report = build_provenance(REPO)
        self.json_text = render_provenance_json(self.report)
        self.md_text = render_provenance_markdown(self.report)

    def test_rendering_is_deterministic(self):
        from tools.kinglet_spike.provenance import render_provenance_json

        self.assertEqual(render_provenance_json(build_provenance(REPO)), self.json_text)

    def test_the_markdown_states_the_unrecorded_licence_count(self):
        self.assertIn(str(len(self.report.unlicensed)), self.md_text)

    def test_no_machine_local_path_leaks_into_the_report(self):
        for text in (self.json_text, self.md_text):
            self.assertNotIn(str(REPO), text)
            self.assertNotIn("/home/", text)


if __name__ == "__main__":
    unittest.main()

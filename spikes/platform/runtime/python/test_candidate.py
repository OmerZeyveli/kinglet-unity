import tempfile
import unittest
from pathlib import Path

from kinglet_host_probe import atomic_replace, verify_ed25519


class PythonCandidateTests(unittest.TestCase):
    def test_atomic_replace_leaves_only_complete_new_file(self):
        with tempfile.TemporaryDirectory(prefix="Kral Yalıçapkını ") as directory:
            target = Path(directory) / "state.json"
            target.write_text("old", encoding="utf-8")
            atomic_replace(target, b"new\n")
            self.assertEqual(b"new\n", target.read_bytes())
            self.assertEqual([], list(target.parent.glob("*.tmp")))

    def test_rfc8032_vector(self):
        self.assertTrue(verify_ed25519(
            "",
            "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a",
            "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b",
        ))

from pathlib import Path
import unittest

from tools.kinglet_build import PRODUCT_NAME, PRODUCT_SLUG


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]


class ProductIdentityTests(unittest.TestCase):
    def test_product_identity_is_kinglet_for_unity(self) -> None:
        self.assertEqual(PRODUCT_NAME, "Kinglet for Unity")
        self.assertEqual(PRODUCT_SLUG, "kinglet-unity")

    def test_development_version_is_exact(self) -> None:
        self.assertEqual(
            (REPOSITORY_ROOT / "VERSION").read_text(encoding="utf-8"),
            "3.0.0-dev.1\n",
        )


if __name__ == "__main__":
    unittest.main()

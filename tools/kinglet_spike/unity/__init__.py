"""tools.kinglet_spike.unity -- frozen Unity execution-probe route contract.

Task 1 of the 00U plan freezes the receipt shape and its strict validation
rules before anything launches Unity. See:
  spikes/platform/unity/contracts/routes-v1.json  -- the frozen contract
  tools/kinglet_spike/unity/model.py              -- UnityReceipt types
  tools/kinglet_spike/unity/receipt.py            -- parse / validate / convert
"""

from .model import CompileResult, TestResult, UnityReceipt
from .receipt import (
    load_unity_receipt,
    receipt_to_evidence,
    unity_receipt_from_dict,
    validate_unity_receipt,
    verify_cited_isolation_manifest,
)

__all__ = (
    "CompileResult",
    "TestResult",
    "UnityReceipt",
    "load_unity_receipt",
    "receipt_to_evidence",
    "unity_receipt_from_dict",
    "validate_unity_receipt",
    "verify_cited_isolation_manifest",
)

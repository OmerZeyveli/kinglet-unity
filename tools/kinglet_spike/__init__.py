"""Candidate-neutral evidence tooling for Kinglet platform spikes."""

from .load import load_record
from .model import EvidenceError, EvidenceRecord

__all__ = ("EvidenceError", "EvidenceRecord", "load_record")

"""tests.kinglet_spike.fixtures -- executable fixtures for the Unity spike tests.

Modules here are run as real child processes (``python3 -m
tests.kinglet_spike.fixtures.process_tree ...``), not imported for their
symbols. They exist so process-tree containment is proven against a real
kernel-managed process tree rather than a mock that cannot orphan anything.
"""

# -*- mode: python ; coding: utf-8 -*-
# kinglet-host-probe.spec — PyInstaller one-file build spec for the Python host probe candidate.
#
# Build with:
#   uv python install 3.14.6
#   uv lock   --project spikes/platform/runtime/python --python 3.14.6
#   uv sync   --project spikes/platform/runtime/python --frozen --python 3.14.6
#   uv run    --project spikes/platform/runtime/python pyinstaller --clean \
#             spikes/platform/runtime/python/kinglet-host-probe.spec
#
# The spec is authored from the REPOSITORY ROOT so that datas paths resolve
# relative to that root (PyInstaller uses the specpath directory as cwd).

import os
from pathlib import Path

from PyInstaller.utils.hooks import collect_dynamic_libs

# Repository root is two levels above the spec's directory when PyInstaller
# is invoked from the repo root; the spec file itself is
# spikes/platform/runtime/python/kinglet-host-probe.spec.
REPO_ROOT = os.path.abspath(os.path.join(SPECPATH, '..', '..', '..', '..'))

block_cipher = None

a = Analysis(
    [os.path.join(REPO_ROOT, 'spikes', 'platform', 'runtime', 'python', 'kinglet_host_probe.py')],
    pathex=[REPO_ROOT],
    binaries=collect_dynamic_libs('cryptography'),
    datas=[
        # Bundle the tools/kinglet_build package so load_graph is available inside the binary.
        (os.path.join(REPO_ROOT, 'tools', 'kinglet_build'), 'tools/kinglet_build'),
        (os.path.join(REPO_ROOT, 'tools', 'kinglet_spike'), 'tools/kinglet_spike'),
        (os.path.join(REPO_ROOT, 'tools', '__init__.py'), 'tools'),
    ],
    hiddenimports=[
        'cryptography.hazmat.primitives.asymmetric.ed25519',
        'cryptography.hazmat.primitives.asymmetric',
        'cryptography.exceptions',
        'tools',
        'tools.kinglet_build',
        'tools.kinglet_build.loader',
        'tools.kinglet_build.errors',
        'tools.kinglet_spike',
        'tools.kinglet_spike.runtime_contract',
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name='kinglet-host-probe',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

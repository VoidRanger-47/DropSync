# -*- mode: python ; coding: utf-8 -*-


a = Analysis(
    ['dropsync_app.py'],
    pathex=[],
    binaries=[],
    datas=[
        ('windows/runner/resources/app_icon.ico', 'windows/runner/resources'),
        ('assets/icon/dropsync_icon.png', 'assets/icon'),
    ],
    hiddenimports=['qrcode', 'PIL', 'PIL.Image', 'PIL.ImageTk'],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='DropSync',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon='windows/runner/resources/app_icon.ico',
)

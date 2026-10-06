"""libexec/frametop/native-desktop makes desktops.sh install's "Native Desktop" entry: what
upstream's update-check.py accepts as a copy of SteamOS's Desktop entry, renamed, and not the
one Steam singles out.

  python3 checks/test_native_desktop.py FRAMETOP_PACKAGE
"""
import importlib.machinery
import importlib.util
import os
import subprocess
import sys
import tempfile
import unittest

PACKAGE = sys.argv.pop(1)
SCRIPT = os.path.join(PACKAGE, "libexec", "frametop", "native-desktop")
loader = importlib.machinery.SourceFileLoader(
    "update_check", os.path.join(PACKAGE, "share", "frametop", "scripts", "update-check.py"))
update_check = importlib.util.module_from_spec(importlib.util.spec_from_loader("update_check", loader))
loader.exec_module(update_check)

# Shaped like SteamOS's /usr/share/applications/deckard-nested-desktop.desktop.
STOCK = """[Desktop Entry]
Type=Application
Name=Desktop
Name[de]=Desktop
# Steam uses X-Steam-Special to pick this out
X-Steam-Special=nested-desktop
Exec=/usr/bin/deckard-nested-desktop
Icon=preferences-desktop
"""


class NativeDesktopTest(unittest.TestCase):
    def test_copy(self):
        with tempfile.TemporaryDirectory() as tmp:
            stock, native = os.path.join(tmp, "stock.desktop"), os.path.join(tmp, "native.desktop")
            with open(stock, "w") as f:
                f.write(STOCK)
            subprocess.run([SCRIPT, stock, native], check=True)
            with open(native) as f:
                text = f.read()
            self.assertIn("Name=Native Desktop\n", text)
            self.assertNotIn("Name[", text)
            self.assertNotIn("X-Steam-Special", text)
            self.assertEqual(update_check.launcher_keys(native), update_check.launcher_keys(stock))


if __name__ == "__main__":
    unittest.main()

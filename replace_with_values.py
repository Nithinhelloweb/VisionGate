import re
from pathlib import Path
path = Path('siet_sync/lib/pages/admin_panel.dart')
text = path.read_text()
pattern = re.compile(r"withValues\s*\(\s*alpha:\s*([0-9.]+)\s*,?\s*\)")
new_text, count = pattern.subn(r"withOpacity(\1)", text)
print('replacements:', count)
path.write_text(new_text)

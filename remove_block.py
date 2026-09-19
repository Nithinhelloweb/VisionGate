from pathlib import Path
path = Path('siet_sync/lib/pages/admin_panel.dart')
text = path.read_text()
start = text.index('class AdminReportsTab {')
end = text.index('class AdminReportsTab extends StatefulWidget')
text = text[:start] + text[end:]
path.write_text(text)

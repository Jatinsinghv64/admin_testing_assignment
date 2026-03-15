import re

file_path = "lib/Screens/DishEditScreenLarge.dart"
with open(file_path, "r") as f:
    content = f.read()

# Find the start of the HTML chunk
start_idx = content.find("static const Color _rPrimary = Colors.deepPurple;")
if start_idx == -1:
    print("Could not find start index")
    exit(1)

prefix = content[:start_idx]
html_chunk = content[start_idx:]

# Replace Color definitions
html_chunk = re.sub(
    r"static const Color _rBgDark = .*?;",
    r"static const Color _rBgDark = Colors.white;\n  static const Color _rTextMain = Colors.black87;",
    html_chunk
)
html_chunk = re.sub(
    r"static const Color _rSurface = .*?;",
    r"static const Color _rSurface = Color(0xFFFAFAFA);",
    html_chunk
)
html_chunk = re.sub(
    r"static const Color _rBorder = .*?;",
    r"static const Color _rBorder = Color(0xFFEAEAEA);",
    html_chunk
)
html_chunk = re.sub(
    r"static const Color _rTextSubtle = .*?;",
    r"static const Color _rTextSubtle = Color(0xFF757575);",
    html_chunk
)

# Text color replacements - Colors.white -> _rTextMain in Text styles
html_chunk = html_chunk.replace("color: Colors.white", "color: _rTextMain")

# But wait, ElevetedButton foregroundColor: _rBgDark -> Colors.white
html_chunk = html_chunk.replace("foregroundColor: _rBgDark", "foregroundColor: Colors.white")

# Also the allergen card dairy icon was white, now it should be primary or something visible
html_chunk = html_chunk.replace("'color': _rTextMain, 'label': 'Dairy'", "'color': Colors.blue, 'label': 'Dairy'")

# Text input fillColor: _rBgDark -> Colors.white
html_chunk = html_chunk.replace("fillColor: _rBgDark", "fillColor: Colors.white")

# BoxBorder color: _rBgDark -> Colors.white
html_chunk = html_chunk.replace("color: _rBgDark", "color: Colors.white")

# Fix _buildAdvancedRecipeSection background shadows (it was _rBgDark but no shadow)
# It's better to just let _rBgDark be Colors.white

with open(file_path, "w") as f:
    f.write(prefix + html_chunk)

print("Replaced colors successfully")

import sys
from pathlib import Path

# Ensure bridge-skill/ is on sys.path so `import companion_bridge` works
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

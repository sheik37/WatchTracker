import os
import sys

# Ajouter le répertoire server/ au PYTHONPATH pour que les tests trouvent les modules
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

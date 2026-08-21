## ModuleInfo — shared module name/icon lookup (by GameState.ModuleType index).
## Previously duplicated between upgrade_menu.gd and station.gd (needed for
## the slot hover tooltip) — a single shared source avoids the two drifting.
class_name ModuleInfo

const ICONS := ["➕", "⚡", "🔫", "🛡", "❤", "💪", "💣"]
const NAMES := ["Vide", "Générateur", "Tourelle", "Bouclier", "Réparation", "Amplificateur", "Mine"]

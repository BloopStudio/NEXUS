# NEXUS

Jeu de survie/vagues/gestion multijoueur — défendez votre station ensemble.

## Stack
- Godot 4.2+
- GDScript
- Réseau P2P ENet (pas de serveur dédié)

## Comment jouer

### Héberger une partie
1. Lance le jeu → "Héberger une partie"
2. Copie le **code de partie** affiché
3. Partage-le à tes amis
4. Clique "Démarrer la partie"

> ℹ️ Le port UDP de l'hôte s'ouvre **automatiquement via UPnP** — dans la grande majorité des cas, aucune configuration du routeur n'est nécessaire. Si le routeur de l'hôte ne supporte pas l'UPnP (ou qu'il est désactivé), le jeu l'indique et le code de partie ne fonctionnera qu'en réseau local, sauf à ouvrir le port UDP 7777 manuellement.

### Rejoindre une partie
1. Lance le jeu → "Rejoindre avec un code"
2. Entre le code de partie
3. Attends que l'hôte démarre

## Mécaniques

### Station
La station centrale est votre objectif. Si sa vie tombe à 0, c'est game over.
Elle dispose de **8 emplacements** pour les modules, extensibles jusqu'à
**12** via l'arbre de compétences (bouton 🌳 en haut à gauche pendant la
phase de construction, coût en énergie croissant).

### Modules
| Module | Effet |
|--------|-------|
| ⚡ Générateur | Produit de l'énergie passivement |
| 🔫 Tourelle | Tire automatiquement sur l'ennemi le plus proche |
| 🛡 Bouclier | Régénère la vie de la station après chaque vague |
| ❤ Réparation | Augmente la vie max de la station |
| 💪 Amplificateur | Augmente les dégâts des tirs des joueurs |
| 💣 Mine | Dégâts de zone périodiques à tous les ennemis proches |

Chaque module a 3 niveaux d'amélioration, et peut être détruit pour
récupérer 30% de l'énergie investie (construction + améliorations).

### Sort du joueur
**Onde de choc** (touche E par défaut, réassignable) : dégâts de zone
autour du joueur, sur un temps de recharge de 6 secondes.

### Vagues
Des vagues d'ennemis arrivent à intervalles réguliers.
Entre chaque vague : phase de construction pour améliorer la station.

### Ennemis
| Ennemi | Forme | Description |
|--------|-------|-------------|
| Basic | Triangle rouge | Standard |
| Fast | Diamant orange | Rapide, peu de vie |
| Tank | Hexagone violet | Lent, très résistant |
| Ranged (dès la vague 3) | Diamant magenta | Garde ses distances et tire sur la station |
| Splitter (dès la vague 5) | Pentagone jaune | Se scinde en 2 Fast à sa mort |

## Build

### Télécharger un exécutable
Les builds Windows/Linux/macOS sont publiés automatiquement dans les
[Releases GitHub](../../releases) à chaque nouvelle version poussée sur `main`
(numéro de version incrémenté automatiquement) :
- **Windows** : `NEXUS-Setup-x.y.z.exe` (installeur — raccourcis menu Démarrer/bureau, désinstalleur) ou `NEXUS-x.y.z-windows.zip` (portable)
- **Linux** : `NEXUS-x.y.z-x86_64.AppImage` (télécharge, rends-le exécutable, double-clique — rien à installer) ou `NEXUS-x.y.z-linux.zip` (portable)
- **macOS** : `NEXUS-x.y.z-macos.dmg` (glisse NEXUS dans Applications, comme n'importe quelle app Mac)

Chaque build livre l'exécutable et ses données dans des fichiers séparés
(`NEXUS.exe` + `NEXUS.pck`) — rien n'est compressé dans un binaire monolithique.

### Compiler soi-même
1. Installe [Godot 4.2+](https://godotengine.org/)
2. Ouvre le projet dans Godot
3. Project → Export pour compiler en .exe / .app / Linux

## Développé avec
- Claude (Cowork) — architecture et code complet
- Godot Engine 4
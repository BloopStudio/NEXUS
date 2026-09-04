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

> ℹ️ Le port UDP de l'hôte s'ouvre **automatiquement via UPnP** — dans la grande majorité des cas, aucune configuration du routeur n'est nécessaire. Si le routeur de l'hôte ne supporte pas l'UPnP (ou qu'il est désactivé), le jeu essaie aussi une découverte d'adresse via **STUN** (le standard utilisé par WebRTC/Discord — un serveur public gratuit indique juste l'IP publique de l'hôte, sans faire transiter le trafic de jeu), qui fonctionne pour une partie des routeurs même sans UPnP. Le code de partie embarque toutes les adresses trouvées (locale, UPnP, STUN) et le joueur qui rejoint les essaie dans l'ordre. Si aucune ne fonctionne, le code ne marchera qu'en réseau local, sauf à ouvrir le port UDP 7777 manuellement. Une connexion échoue proprement (avec un message clair plutôt que de rester bloquée sur « Connexion en cours… ») si le routeur de l'hôte fait du **CGNAT** (fréquent chez certains opérateurs mobiles/fibre) — dans ce cas ni l'UPnP ni le STUN ne peuvent rendre l'hôte joignable depuis internet ; seul le réseau local de l'hôte peut alors se connecter.

### Rejoindre une partie
1. Lance le jeu → "Rejoindre avec un code"
2. Entre le code de partie
3. Attends que l'hôte démarre

## Mécaniques

### Station
La station centrale est votre objectif. Si sa vie tombe à 0, c'est game over.
Elle dispose de **8 emplacements** pour les modules, extensibles jusqu'à
**12** via le bouton 🌳 en haut à gauche pendant la phase de construction,
qui ouvre l'arbre de compétences complet : en plus des emplacements
supplémentaires (coût en énergie croissant), 3 branches indépendantes de
bonus permanents à 3 paliers chacune, payées avec l'énergie de l'équipe :

| Branche | Palier 1 | Palier 2 | Palier 3 |
|---|---|---|---|
| ⚔ Dégâts | +10% dégâts (joueurs/tourelles/mines) | +10% supplémentaires (total +20%) | +10% supplémentaires (total +30%) |
| ⚡ Économie | +10% énergie passive | -10% coût de construction | +15% remboursement à la destruction |
| 🛡 Défense | +15% vie max station | +20% soin des modules Réparation | +15% vie max supplémentaire (total +30%) |

Les paliers d'une branche se débloquent dans l'ordre.

### Modules
| Module | Effet |
|--------|-------|
| ⚡ Générateur | Produit de l'énergie passivement |
| 🔫 Tourelle | Tire automatiquement sur l'ennemi le plus proche |
| 🛡 Bouclier | Augmente la vie max de la station |
| ❤ Réparation | Régénère la vie de la station après chaque vague |
| 💪 Amplificateur | Augmente les dégâts des tirs des joueurs |
| 💣 Mine | Dégâts de zone périodiques à tous les ennemis proches |
| 🚨 Bouclier d'urgence | Usage unique — clic pendant une vague : soigne 30% de la vie max + invulnérabilité 3 s |
| ☢ Bombe EMP | Usage unique — clic pendant une vague : dégâts + étourdit tous les ennemis à l'écran |
| ⛏ Foreuse | Produit passivement des matériaux rares (deuxième monnaie, séparée de l'énergie) |

Chaque module a 3 niveaux d'amélioration, et peut être détruit pour
récupérer 30% de l'énergie investie (construction + améliorations) — sauf
le Bouclier d'urgence et la Bombe EMP, à usage unique et sans niveau : on
clique sur leur emplacement pendant une vague pour les déclencher, ce qui
les consomme.

### Matériaux rares
Les modules ⛏ Foreuse (constructibles sur la station comme sur les
avant-postes) produisent une deuxième monnaie, séparée de l'énergie : les
matériaux rares. Depuis l'Arbre de compétences, le bouton **🔩 Forge
orbitale** (3 paliers) les échange contre +10% de vie max permanente pour
la station ET chaque avant-poste construit — un deuxième axe de
progression indépendant de l'économie d'énergie habituelle.

Un module touché par un ennemi Saboteur (voir Ennemis) est **désactivé**
temporairement — encadré rouge pulsant sur son emplacement — et ne produit
plus son effet le temps que ça dure, sans perdre son niveau.

**Synergies de placement** : les emplacements sont disposés en anneau, et
les modules voisins immédiats s'influencent :
- 🔫 Tourelle à côté d'une autre Tourelle : cadence de tir améliorée
- 💣 Mine à côté d'un 💪 Amplificateur : dégâts de la mine augmentés
- ⚡ Générateur à côté d'un autre Générateur : production augmentée

Une synergie active se voit directement sur la station : un lien coloré
pulsant relie les deux emplacements concernés, et le survol de l'un d'eux
affiche le bonus exact dans l'infobulle.

### Sorts du joueur
Avant de démarrer une partie, chaque joueur choisit dans le menu principal
quel sort il place sur chacune des deux touches de sort (E et A par défaut,
réassignables dans les réglages — un sort n'est jamais figé sur une touche) :

| Sort | Effet | Recharge |
|---|---|---|
| 💥 Onde de choc | Dégâts de zone autour du joueur | 6 s |
| ✚ Soin d'urgence | Restaure instantanément la vie de la station | 12 s |
| ❄ Champ ralentisseur | Ralentit les ennemis proches | 9 s |
| 🚀 Ruée | Vitesse de déplacement fortement augmentée | 5 s |

Le HUD affiche les deux sorts équipés avec leur icône et le temps de
recharge restant. Chaque sort équipé peut aussi être amélioré jusqu'au
niveau 3 avec l'énergie de l'équipe pendant la phase de construction
(bouton sous son icône) : la recharge diminue et l'effet augmente.

### Classes
Avant une partie, chaque joueur choisit une classe qui modifie légèrement
ses statistiques de base et suggère un sort de départ (sans jamais le
forcer) :

| Classe | Effet |
|---|---|
| ⚔ Dégâts | +25% dégâts de tir et de sorts, vie réduite |
| ✚ Soin | Vie et dégâts normaux |
| 🛡 Tank | +60% vie, dégâts réduits |

### Vie du joueur
Les joueurs ont désormais des points de vie : le contact avec un ennemi sur
son chemin vers la station en retire (l'ennemi continue de cibler la
station, pas les joueurs — c'est juste ce qui arrive si on reste sur son
passage). À 0 PV, le joueur tombe « à terre » : il ne peut plus bouger,
tirer ni lancer de sort. Un coéquipier qui reste ~2,5 s à proximité le
ranime à 50% de vie ; sans aide, il se relève quand même tout seul après
20 s à 25% de vie — jamais bloqué définitivement, seul ou abandonné.

### Marqueurs tactiques
Pas besoin d'un micro pour coordonner l'équipe : pointer la souris quelque
part et appuyer sur **G** (Focus ici) ou **H** (Besoin d'aide), touches
réassignables dans les réglages, pose un marqueur pulsant visible par tous
les joueurs à cet endroit pendant quelques secondes, avec le nom de qui l'a
posé.

### Vagues
Des vagues d'ennemis arrivent à intervalles réguliers, de plus en plus
nombreux ET de plus en plus forts (+9% de vie et de dégâts par vague,
composé — la vague 10 fait environ 2,4× plus mal que la vague 1) : la
difficulté ne vient pas juste du nombre.
Entre chaque vague : phase de construction pour améliorer la station.

### Ennemis
| Ennemi | Forme | Description |
|--------|-------|-------------|
| Basic | Triangle rouge | Standard |
| Fast | Diamant orange | Rapide, peu de vie |
| Tank | Hexagone violet | Lent, très résistant |
| Ranged (dès la vague 3) | Diamant magenta | Garde ses distances et tire sur la station |
| Saboteur (dès la vague 4) | Diamant violet à pointes | Ignore la station, fonce sur un module construit au hasard et le désactive temporairement à son contact |
| Bouclier (dès la vague 3) | Cercle bleu avec arc frontal | Bloque les dégâts venant de face (arc ~140°) — il faut le flanquer pour le toucher |
| Splitter (dès la vague 5) | Pentagone jaune | Se scinde en 2 Fast à sa mort |
| Kamikaze (dès la vague 6) | Cercle orange hérissé | Fonce vite, explose au contact (dégâts de zone à la station et aux joueurs proches) — à abattre à distance |
| Élite (dès la vague 7) | Hexagone doré à pointes | Buffe (vitesse + dégâts) tous les ennemis dans son aura — à cibler en priorité pour couper le buff |
| Aberration (dès la vague 15) | Silhouette violette irrégulière | Se rend invulnérable en alternance (~1s toutes les 3s) — première d'une seconde faction, oblige à rythmer les tirs |

### Carte et avant-postes
Depuis le panneau 🌳 Arbre de compétences, deux nouvelles options en plus
des emplacements et des paliers :
- 🗺 **Agrandir la carte** : repousse la limite jouable par paliers (3 max)
  — plus d'espace pour se déplacer, et les ennemis apparaissent
  proportionnellement plus loin. La limite actuelle est visible comme un
  cercle sur le terrain. La caméra suit le joueur et se dézoome
  progressivement à mesure que la carte s'agrandit, pour garder le terrain
  visible.
- 🏳 **Avant-postes** : jusqu'à 2 avant-postes constructibles (le second
  demandant un agrandissement de carte supplémentaire), chacun avec sa
  propre barre de vie et 4 vrais emplacements de modules (mêmes types que
  la station principale, hors modules à charge unique). Ils sont placés
  loin de la station, dans des directions opposées, et de plus en plus
  loin à mesure que la carte s'agrandit. Les perdre ne termine pas la
  partie, mais une partie des ennemis les prennent pour cible tant qu'ils
  tiennent — les abandonner n'est pas gratuit, et les négliger prive
  d'emplacements de modules utiles.

### Modificateurs de partie
Avant d'héberger, un menu déroulant "Modificateur" laisse choisir un
mutateur qui s'applique à toute la partie (façon graine de roguelite) :

| Modificateur | Effet |
|---|---|
| ➖ Aucun | Partie standard |
| 💎 Canon de verre | +20% dégâts, -20% vie de la station |
| 🏰 Forteresse | +30% vie de la station, -15% dégâts |
| ⚡ Ruée | +25% énergie passive, mais ennemis +10% de vie |
| 💰 Économe | -15% coût de construction/amélioration, -10% dégâts |

### Profil local, classement et statistiques
Le pseudo et les sorts choisis dans le menu principal sont mémorisés
localement (`user://profile.json`) — pas besoin de les ressaisir à chaque
lancement. Un bouton 🏆 **Classement local** sur le menu principal affiche le
top 10 des meilleures vagues atteintes lors des parties **hébergées** depuis
cette machine (les scores en tant qu'invité d'une partie ne sont pas
enregistrés — seul l'hôte a une source fiable du numéro de vague). À la fin
d'une partie, un écran de statistiques (vague atteinte, dégâts totaux
infligés, temps de survie) s'affiche avant le retour au menu.

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
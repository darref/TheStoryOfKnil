# The Story of Knil — charte du jeu

## 1. Le jeu en une phrase — DÉCIDÉ (Jordan, 10 octobre 2026)

> **Un action-aventure vu de dessus, dans la veine des Zelda : Knil, un anti-héros SANS AUCUNE VERTU — un vrai
> bourrin qui ne respecte rien de ce qui est sacré — sauve le monde quand même.**

« The Story of Knil » : le titre fait un clin d'œil (Knil, c'est Link à l'envers). Le projet s'appelait **Resolve**
jusqu'au 10 octobre 2026 : il a été vidé de ce qui en faisait la singularité (le moteur de décision et sa barre
d'actions, « Mépriser », le sommeil obligatoire toutes les 72 h). Tout cela est gardé dans git : le commit `7c1506d`,
étiquette **`resolve-final`**.

- **LE GAMEPLAY** : celui d'un Zelda vu de dessus (exploration, donjons, objets qui ouvrent le monde, cœurs).
  Une mécanique de jeu ne se protège pas : c'est libre.
- **LE TON** : la touche disgracieuse, l'humour, le gore. **Knil** : un bully au gros ventre, avec des dents en moins
  et une coupe militaire dégradée. Sa singularité vient du PERSONNAGE (« qu'est-ce qu'un bully porterait, vénérerait,
  casserait ? »), pas d'un objet de Zelda transformé un à un.
- **SON ALLURE — DESSINÉE (Jordan, 10 octobre 2026)** : `assets/concept/knil_reference_tpose.png` (planche en T, la
  référence pour le modèle 3D) et `assets/icone/knil_icone.png` (l'icône du jeu). Tunique écrue
  déchirée trop courte (le ventre dépasse), lacée au col, poils au torse et aux bras ; pantalon brun rapiécé tenu par
  une corde nouée ; bottes avachies ; deux brassards cloutés de pointes (l'un cuir brun, l'autre fer gris) ; coupe
  militaire dégradée sur les côtés, nez rouge, joues roses, une dent en moins au sourire, sourcils épais.
- **L'ICÔNE — DÉTOURÉE (10 octobre 2026)** : `knil_icone.png` est Knil SEUL sur fond transparent (le fond gris et
  l'anneau blanc retirés : `tools/detoure_icone.py`, un remplissage depuis les bords qui ne prend que le gris NEUTRE
  et clair — la tunique écrue n'est pas neutre, le trait noir l'arrête ; l'original : `knil_icone_fond_gris.png`).
  Elle est PARTOUT : `config/icon` (fenêtre, éditeur), `knil_icone.ico` (16 à 256 px : `config/windows_native_icon`
  et l'icône de l'EXE, `application/icon` du preset), `knil_splash.png` (l'écran de démarrage, sur brun très sombre),
  la vignette « Jouer » du livre. Une nouvelle icône : refaire les trois depuis le PNG (le script, puis PIL).
- ⚠ **LE DROIT — à garder en tête (ce n'est pas un avis juridique)** : AUCUN élément propre à Zelda (tunique verte et
  bonnet, oreilles pointues, Triforce, Master Sword, bouclier hylien, Hyrule, Ganon, musiques et bruitages) ; JAMAIS
  « Link » ni « Zelda » dans la communication du jeu ; peu de clins d'œil, et assumés comme des gags (la
  « Quadriforce » : quatre CARRÉS — pas en 2 × 2 avec quatre couleurs, c'est le logo de Windows). Avant la sortie
  commerciale : chercher « Knil » dans les bases de marques (INPI, EUIPO, USPTO) et voir un avocat en propriété
  intellectuelle.
- **LA CAMÉRA NE TREMBLE PLUS, NE TRAVERSE PLUS (11 octobre 2026)** : l'INTERPOLATION PHYSIQUE est activée
  (`physics/common/physics_interpolation`) — Knil avance aux pas de la physique (60/s), la caméra suit sa position
  INTERPOLÉE (`CameraRig._target_position`) ; ce qui bouge dans `_process` (la caméra, le soleil, la lune) a
  `PHYSICS_INTERPOLATION_MODE_OFF`. Un nœud 3D neuf déplacé dans `_process` : pareil, sinon il saccade. Un saut de
  position (téléport) : `reset_physics_interpolation()`. Et LE BRAS-RESSORT DU PLAY TEST DE MB (`app/vue.gd`,
  `_suivre`), dans TOUTES les vues : une SPHÈRE (0,2) lancée de la tête vers l'œil, rentre sans délai, ressort en
  douceur. **LA BASCULE VERTICALE** (comme Spirit3D, refaite ici) : dehors, si le décor coupe la vue OBLIQUE vers
  le torse de Knil, la caméra passe DROIT AU-DESSUS de lui (même distance, haut de l'écran gardé : les commandes ne
  tournent pas — `Player._camera_relative` prend le haut de l'écran quand la caméra regarde droit en bas) ; la vue
  testée est toujours l'oblique, même en vertical ; entrer après 0,08 s, revenir après 0,5 s libre, fondu 0,35 s
  (`overhead_*`). ÉPROUVÉ : `sonde_camera` (8 ; mutation : bascule coupée → 4 rouges). Vu sur la carte (49,5 ; −49,5).
  ⚠ Le « FilDeSecours » (une boîte invisible de 400 m à y = −5,5) est RETIRÉ de `main.tscn` : il coupait
  tout ce qui est peint plus bas ; la chute est rattrapée par `Player.fall_limit`.
- **LA VUE** (gardée) : de dessus dehors ; troisième personne dans un intérieur (bâtiment, grotte, galerie) ; la
  bascule est AUTOMATIQUE (`Interior` → `CameraRig`).
- **LA RÈGLE D'ARCHITECTURE** (gardée) : **le backend ne connaît pas la présentation.** Il émet sur l'`EventBus` ;
  caméra, UI, animations, lumière écoutent.
- **LA CARTE SE PEINT À LA MAIN** dans le logiciel MarchingBlocks (Jordan). On ne la regénère pas par script.

## 2. MarchingBlocks dans ce projet — VÉRIFIÉ (8 octobre 2026)

**Oui, c'est installable dans un autre projet, et c'est fait.** Mais pas comme on s'en souvenait :

- ⚠ **CE QUI SERT, C'EST LE GREFFON GRATUIT `addons/marchingblocks_paint/`, ET LUI SEUL.** Il est AUTONOME : il ne
  charge RIEN du cœur (charte de MB, « LE GREFFON GODOT À PARITÉ »). Il réécrit la règle de pose depuis le texte
  du format (`rules_text` dans `tileset.json`), en GDScript. Il donne :
  - dans l'ÉDITEUR : le pinceau (barre au-dessus de la vue 3D) pour peindre / retoucher le terrain, et
    **Project → Tools → Import MarchingBlocks world…** ;
  - en JEU : le nœud `MarchingBlocksWorld` (un par couche) qui pose ses tuiles au `_ready`, et `apply_cells()` pour
    changer le monde en cours de partie. **Mesuré ici : il marche à l'exécution, pas seulement dans l'éditeur.**
- ⚠ **LA GDEXTENSION DU CŒUR C++ (`MBNatif`, `MBMonde`) N'EST PAS UTILISABLE PAR UN JEU AUJOURD'HUI.** Elle ne
  part que dans l'exe de l'appli ; son pont dépend de `marching_blocks.gd` (l'addon `marchingblocks_core`, la
  partie qui se vend) pour sa table. Que les greffons embarquent la GDExtension est l'étape (4) du plan de MB, et
  **l'API de jeu** (`GetCell`, `Raycast`, `TileAt`, `OnCellsChanged`, `SaveCells`…) l'étape (5) — PROPOSÉES, pas
  écrites. Ce n'est pas bloquant : on n'en a besoin que pour la VITESSE (voir §6, le monde large).
- **LE LOGICIEL MARCHINGBLOCKS FAIT LES DEUX** :
  - **les TUILES** — ateliers Geometry / Texturing / Animation / Transitions / Foliage, puis « Export to engines » :
    un dossier `<nom>.mbset/` (`tileset.json` + `tiles.glb`), une couche ;
  - **le MONDE** — atelier World (peindre, formes spéciales, salles, eau, couches), exporté en `<nom>.mbworld/`
    (`world.json` + un `.mbset` par couche + eau, transitions, feuillage). Importé dans Godot, il donne un
    `MarchingBlocksWorld` par couche, `MarchingBlocksWater`, `MarchingBlocksTransitions`, `MarchingBlocksFoliage`.
  - **Recommandé** : peindre le monde DANS MarchingBlocks (outils plus complets, eau, feuillage), l'importer ici
    sous `mondes/`, le CUIRE (ci-dessous). On ne retouche pas le terrain dans Godot : on repeint dans MB, on recuit.

**Installer / mettre à jour le greffon** : copier `D:\MarchingBlocks\addons\marchingblocks_paint` dans `addons\`
(ici : copie du commit `9ec4403` de MB, 8 octobre 2026). Une mise à jour = recopier le dossier. Le greffon REFUSE un
format plus récent que le sien : greffon et appli doivent avancer ensemble.

⚠ **UN `.mbset` D'AVANT LE 30 SEPTEMBRE 2026 EST REFUSÉ** (« must be one tile name (one tile per key) ») :
`D:\MarchingBlocks\global_blender_bevel_and_tripo_texture.mbset` en est un. Le jeu d'essai d'ici est
`assets/tilesets/temoin.mbset`, copié de `engines/unity/test-project/Assets/witness.mbset` (format actuel ; il lui
manque 20 tuiles sur le terrain d'essai — cubes rouges, cachés en jeu). **Le vrai jeu de tuiles est à faire dans
MarchingBlocks.**

~~**Ce que le jeu ajoute au greffon** (`MBTerrain`)~~ — retiré le 8 octobre 2026 : le jeu ne pose plus de tuiles
par le greffon, il charge des morceaux cuits (ci-dessous). ⚠ **Ne jamais poser de `MarchingBlocksWorld` dans une scène
du jeu** : ouverte dans l'éditeur, la scène enregistre les grilles générées par le greffon (vu : `main.tscn` passé de
190 à 2 278 lignes, 3 MeshLibrary et 104 maillages embarqués).

### LE MONDE SE FAIT DANS LE LOGICIEL MB — DÉCIDÉ (Jordan, 8 octobre 2026)

« On laissera le greffon pour les acheteurs de MB. » Le monde de Knil se peint dans l'appli MarchingBlocks, pas
dans Godot. ⚠ Il faut quand même LIRE son export (`.mbworld`) côté jeu : le greffon reste la référence de lecture,
mais seulement dans la CHAÎNE DE CUISSON (outil d'éditeur, §6) — le jeu livré n'embarque ni le greffon ni la règle
de pose, il charge des morceaux cuits. À terme, un « Export baked world » dans l'appli MB elle-même ferait la
cuisson à la source (une fonction utile aussi aux acheteurs) : à proposer à MarchingBlocks.

### LES COUCHES DU MONDE — DÉCIDÉ (Jordan, 8 octobre 2026), ÉCRIT LE MÊME JOUR

Le monde de Knil est **UN `.mbworld` à plusieurs COUCHES**, peintes dans le logiciel MB :

| Couche MB (nom) | Rôle (`tools/cuisson/couches.json`) | Ce qu'elle porte | Piste, distance |
|---|---|---|---|
| **Batiments** | `batiments` | l'atelier **Houses** de MB 1.0.0 (c'est son nom dans la charte de MB) — rien à peindre avant | ~64 |
| **GrosObstacles** | `gros` | un volcan, une montagne : ce qui se voit de LOIN | ~400 |
| **Obstacles** | `obstacles` | les massifs qui bordent chemins et places | ~72 |
| **Sol** | `sol` | le relief (« une carte de hauteur », arches comprises), les GALERIES sous presque toute la carte ; l'eau et le feuillage | ~56 |

- ⚠ **UN SEUL MONDE, PAS QUATRE** : la règle de pose lit les couches ENSEMBLE (pas de mur où un massif touche le sol ;
  où elles se touchent, la PREMIÈRE couche l'emporte). Ordre conseillé dans MB : Batiments, GrosObstacles, Obstacles, Sol.
  Une couche est reconnue par son NOM (casse et espaces ignorés) ; un nom inconnu va au Sol, et la cuisson le dit.
- **CHAQUE RÔLE SA PISTE** : la cuisson range chaque couche dans ses propres fichiers (`cuit/<monde>/<rôle>/m_*.scn`),
  le `ChunkStreamer` les charge chacune à sa distance (un volcan se voit de loin, un massif de près). La COLLISION et le
  SOUS-SOL, toutes couches ensemble, restent à part et tout près (~20).
- **LE SOUS-SOL EST AUTOMATIQUE** : les galeries courent sous presque toute la carte — on ne les borde pas de volumes
  à la main. Une tuile est SOUTERRAINE quand chacune de ses cases vides a au moins `profondeur_souterrain` (2) cases
  pleines au-dessus : une galerie oui ; une ARCHE, un surplomb, l'entrée d'une grotte (une case de couvert) non. La
  cuisson range ces tuiles dans « Souterrain » (cachées vues de dessus) et écrit, par morceau, les tronçons d'air
  ENFOUI. En jeu, si les pieds du joueur sont dans cet air, `Interior.set_underground(true)` (après 0,25 s) : caméra
  en troisième personne, torche, ambiante d'intérieur, tuiles souterraines montrées.
- **PAR FENÊTRES** : la cuisson pose le monde fenêtre par fenêtre (4 × 4 morceaux), une case de marge — un sommet ne
  lit que les cases v..v+1 et leurs colonnes. La règle tourne UNE fois par fenêtre pour toutes les couches
  (`Rule.placements_layered`, la référence du greffon), au lieu d'une fois par couche dans le greffon.
  ⚠ **VU PAR L'ÉPREUVE** : une fenêtre qui n'a que des cases de MARGE porte les sommets du bord du monde (devant la
  première case) — sautée, le pourtour perdait ses tuiles (aire 52 181 au lieu de 54 765).
- **ÉPROUVÉ** (`test_cuisson`, 94 vérifications, 36 fenêtres d'un morceau sur le monde d'essai à trois couches : Sol
  157 252 cases avec galeries et arche, Obstacles en anneau autour de la place, un volcan) : **chaque rôle a la MÊME
  géométrie que le monde ENTIER bâti par le greffon** (`WorldFile.build`, couche par couche) ; les pistes ; le volcan
  chargé de loin ; sous terre dans la galerie, à l'air sous l'arche et sur la place ; les tuiles souterraines
  montrées puis cachées ; le sol de la galerie se marche. **Mutations rouges** : marge supprimée (sol ET volcan
  faux), profondeur 1 (l'arche devient souterraine). `sonde_scene` : dans la galerie, souterrain, troisième personne,
  torche allumée. Vu à l'image (`capture_couches`).

### LE MONDE DE KNIL (ex-« Val de Résolve ») — LE PREMIER MONDE, FAIT PAR LE LOGICIEL MB (Jordan, 8 octobre 2026 : « utilise l'exemple de test
### qui a déjà 3 matières, rajoute 7 matières bien pensées et fais un monde à thème »)

**`Knil_MB_project/`** (un `.gdignore` : le projet Godot ne le lit pas) — le projet MarchingBlocks du jeu :
**`monde_knil.mbproj`, UN SEUL PROJET** (Jordan, 9 octobre 2026 : « je ne veux pas avoir plusieurs sous-maps »), à
ouvrir dans MB pour repeindre ; `matieres/` (l'exemple de MB et les sept matières neuves), `modeles/arbres/` (les arbres
de HEARTWORLD), `outils/fabriquer_val.gd` (le script qui l'a fait, LANCÉ DANS LE PROJET MB — rien du format n'est
réécrit), `outils/banc_ouverture_mb.gd` (ouvre un projet dans la fenêtre de MB et mesure : `--tenir=s`, `--vues=26;60;
monde@300`, `--sans-feuillage`, `--octant=n`, `--sans-physique`, `--chronos` ; remet les réglages de MB) :

```
"$GODOT" --headless --path D:/MarchingBlocks --script D:/TheStoryOfKnil/Knil_MB_project/outils/fabriquer_val.gd [-- --taille=784]
"$GODOT" --path D:/MarchingBlocks --script D:/TheStoryOfKnil/Knil_MB_project/outils/banc_ouverture_mb.gd -- --projet=<.mbproj>
"$GODOT" --headless --path D:/TheStoryOfKnil --import
"$GODOT" --headless --path D:/TheStoryOfKnil res://tools/cuisson/cuire.tscn -- --monde=res://mondes/monde_knil.mbworld/world.json
"$GODOT" --headless --path D:/TheStoryOfKnil res://tests/sonde_collision.tscn -- --monde=res://cuit/monde_knil
```

- ⚠ **MB PLANTAIT SUR LE VAL — RÉPARÉ DANS MB (9 octobre 2026, Jordan : « il ne doit pas planter »)**, deux fichiers et
  une épreuve (voir la charte de MB, « LES GRANDS MONDES NE PLANTENT PLUS ») : « FATAL: Index p_index = 4294967294 is
  out of bounds (count = 32771) » venait du moteur PHYSIQUE de Godot, débordé par les formes de collision que les
  grilles d'affichage de l'appli portaient pour rien (`MassifPeint.collision_des_pieces`, faux dans l'appli). Et le
  feuillage de MB était une MultiMesh pour tout le monde (299 M primitives, 4 img/s de près) : par morceaux de 32,
  portée 400, LOD. **Le Val entier s'ouvre** (5,5 s, 4,1 Go) : 25 img/s à l'ouverture, 12 à 60 m de recul, 6 à
  150 m ; tout cadré (F) : 1 img/s — les vues lointaines de MB restent lentes (OUVERT dans MB). Épreuves de MB
  vertes : `test_massif_peint` 130, `test_feuillage` 70, `test_repli_procedural` 3 922, `fumee_appli` 937.
  ⚠ PAS COMMITÉ dans MB (`git diff` : `massif_peint.gd`, `vue.gd`, `feuillage_vue.gd`, `test_massif_peint.gd`, sa charte).
  ⚠ **L'APPLI INSTALLÉE NE LE SAVAIT PAS** (« plante encore malgré réinstallation ») : l'installeur `build/` datait du
  8 octobre. Rebâtie le 9 au soir par `DEV_TOOLS/exporter_marchingblocks.sh` depuis un arbre git À PART
  (`D:/MarchingBlocks_wt_resolve` : HEAD + ces seuls correctifs, fins de ligne LF, projet importé — un autre travail en
  cours dans `D:/MarchingBlocks` cassait la fumée), 28 suites vertes, sortie `D:/SpannerGames/ATELIER/MarchingBlocks/builds/build_resolve/` ; l'exe
  et sa DLL copiés dans `%LOCALAPPDATA%/Programs/MarchingBlocks` (l'ancien gardé à côté, `ancienne_version_8_octobre/`).
  Vu à l'image : le Val s'ouvre (5,6 Go). ⚠ Réinstaller depuis `D:/MarchingBlocks/build/installeur` remettrait l'ancien.
  ⚠ La FUMÉE de MB réécrit `reglages.cfg` de l'appli (où vit la CLÉ DE LICENCE) : tuée en route, elle l'a perdue — remise
  depuis une copie.
- **DIX MATIÈRES** (une matière = une couche MB = un jeu de tuiles). De l'exemple : **Prairie** (Grass), **Roche**
  (GreyRock), **Désert** (Desert). Neuves, sur le témoin de MB, DEUX textures chacune (le dessus et les flancs, choisis
  par la normale de chaque face), générées sans couture (une période par case), projection « boîte », cartes PBR
  déduites par MB : **Pavés** (pierres arrondies / moellons en assises), **Chemins** (terre battue et gravillons /
  terre en strates), **Sous-bois** (mousse et litière / humus et racines), **Marais** (vase luisante / boue),
  **Neige** (neige / roche glacée), **Basalte** (cendre et braises / orgues), **Profondeurs** (gravier / strates de grès).
- **ONZE COUCHES**, dans l'ordre de MB : Neige, Volcan (Basalte), Montagnes (Roche), Massifs (Roche aussi : deux couches,
  une source, un `.mbset`), Paves, Chemins, SousBois, Marais, Desert, Prairie, Profondeurs — et leur rôle dans
  `couches.json` (gros : Neige, Volcan, Montagnes ; obstacles : Massifs ; sol : le reste).
- **LE PLAN, v2 (Jordan, 9 octobre 2026 : « de grandes étendues plates… un réseau irrégulier de massifs qui bordent
  la zone parcourable, d'au moins 4 de haut… des bords montagneux qui encadrent toute la map » ; la v1 — un relief
  qui faisait trop sauter, « ça ressemble à Minecraft » — est remplacée)**, 784² cases de 1 m :
  - **LA DALLE** : une case (dessus à y = 1), sa matière selon la région (Prairie, Pavés, Chemins, Sous-bois, Marais,
    Désert) — on marche À PLAT partout ; les lacs sont des cuvettes d'une case.
  - **LE RÉSEAU DE MASSIFS** (Massifs, 4 à 7 de haut) entre de grandes étendues (un pavage de Voronoï, ~100 m),
    percé de passages (un arbre couvrant : toutes les étendues sont reliées, plus un tiers de passages en plus) ; les
    routes et les villages les écartent ; **18 ESCALIERS** (marches d'une case) montent sur leurs dessus : les ÉTAGES
    où l'on s'infiltre — ailleurs, on n'y monte pas.
  - **LE CADRE** (Montagnes, 7 à 13 de haut, 6 à 9 d'épaisseur, enneigé en haut) sur tout le pourtour ; les LIMITES
    (±385 m, au pied du cadre là où il est le plus mince) le doublent en jeu (§4).
  - la capitale Haute-Résolve au centre (place pavée de 30 m, remparts de 4 percés aux routes), quatre villages
    (Bois-Joli à l'ouest, La Sablière au sud-est, Les Joncs au sud-ouest, Pied-Mont au nord), une route à chacun ; le
    volcan du nord-est (Basalte, 24 de haut, lave au cratère) ; le lac du Val, l'étang du marais.
  - **LES GALERIES** (Profondeurs) : des TUBES sous la dalle (sol à y = −4, plafond à −1), un couloir tous les 64 m,
    29 escaliers qui y descendent.
    ⚠ **CETTE v2 EST IMPRATICABLE** (Jordan, 10 octobre 2026 : « l'étroitesse et les escaliers ne permettent pas de
    rentrer dedans ») : 2 cases de large, 2 de haut, et au bas de l'escalier le PLAFOND du couloir coupait la tête
    (dernière marche à −2,25, plafond à −0,75, le joueur fait 1,8 m). **v3 dans `fabriquer_val.gd`** (`GALLERY_W`,
    `GALLERY_FLOOR`, `STAIR_*`) : 4 de large, 3 cases d'air (sol en −5, plafond en −1), l'escalier sur toute la largeur,
    4 marches d'une case (2 de long) puis un PALIER de 3 à ciel ouvert au sol de la galerie. ÉPROUVÉ sur un Val d'essai
    256² fait par MB et cuit (`tests/sonde_galerie.tscn`) : 4,00 m libres, 3,00 m sous plafond, une capsule du joueur
    descend, longe et remonte en sautant les marches. ⚠ **LE VAL N'EST PAS REGÉNÉRÉ, ET NE LE SERA PAS** (Jordan : « je
    vais peindre la map moi-même ») : ces cotes sont la RÈGLE POUR PEINDRE une galerie dans MB — au moins 3 cases d'air
    en hauteur, 3 à 4 de large, des marches d'une case avec 2 de long, et en bas un palier À CIEL OUVERT avant le
    plafond. `sonde_galerie` vérifie une galerie peinte (`--escalier=x,z`, le couloir le long de x).
  - **LES ARBRES DE HEARTWORLD** (`D:/Spirit3D/HEART_WORLD/biomes/maps`, copiés dans `modeles/arbres/`), 5,5 m
    (plaines) et 6,5 m (bois) — SAUF LES DÉCIMÉS, reconnus À LEUR COMPTE DE TRIANGLES ROND (une cible de
    décimation ; aucune liste écrite n'a été trouvée) : jungle 01–03 (30 000 pile), palmier, « stylized tree », arbre
    des marais (~5 000), woodland 08 (9 996), woodland 01 (24 978). Gardés : plains 01–04, woodland 02–07 et 09.
    **Leur collision** : un cylindre par tronc (rayon du quart bas du modèle, hauteur ≤ 4 m), cuit dans la piste de
    collision, couche physique 5.
  Les régions de `main.tscn` suivent ce plan.
- **MESURÉ (v2)** : MB le fabrique en 4 min (dont 2,8 de réparation des diagonales) : **1,36 M cases** (la v1 : 6,7 M),
  587 contacts diagonaux comblés, 3 eaux (lac 806 cases, étang 380, lave 1 024), 3 383 arbres ; `.mbproj` 22 Mo,
  `.mbworld` 284 Mo. Cuisson : 8 min 25, 1,55 Go au plus, **1,7 Go** cuits, 1,71 M tuiles, 2 500 morceaux. Collision
  fidèle (0 écart sur 9 morceaux, 900 rayons), scène, saut, galerie, triche et limites : verts.
- **L'ENTRÉE DES MORCEAUX, SORTIE DU FIL PRINCIPAL (11 octobre 2026, Jordan : « ça lag à chaque chargement quand on
  court »)** : la lecture et l'instanciation étaient déjà en fond ; restait l'ENTRÉE dans la scène, mesurée (`banc_course`,
  le vrai jeu, Knil qui court) à 22–30 ms par morceau de sol, dont le FEUILLAGE (ses MultiMesh, 30 à 48 ms). Remède : le
  feuillage est bâti dans le FIL DE TRAVAIL juste après l'instanciation (`FeuillageMorceau.prepare`), et l'entrée est
  ÉTALÉE (`ChunkStreamer.STAGED_PARTS`) : la racine (et la collision) d'abord, puis UN enfant visible par image ; un
  saut (`load_around_now`), d'un coup. Entrées mesurées ensuite : 0,0–0,1 ms. ⚠ L'accrochage d'un enfant mesurait
  encore 12–15 ms EN JEU, mais 0,14 ms SEUL : la machine était chargée (MB ouvert sur la carte, un jeu lancé depuis
  l'éditeur resté ouvert) — à remesurer MB FERMÉ.
  ⚠ **MB OUVERT SUR LA CARTE PARTAGE LA CARTE GRAPHIQUE** : mesuré, le jeu plein écran tombait à 25–49 img/s (même à
  l'arrêt, rien en chargement) alors qu'il tient ~250 img/s seul. Le « 20 img/s dans l'éditeur » de Jordan : sans doute
  ça. Fermer MB (ou le réduire) pour juger le jeu.
- **LES CHUTES À TRAVERS LE SOL — CHERCHÉES (11 octobre 2026)** : `sonde_chute` fait courir Knil dans 8 directions à ×3
  et ×8 (jusqu'à 56 m/s) : AUCUNE chute due à la collision (chargée à temps, coutures soudées). La seule chute est un
  TROU PEINT : deux passages sous les murs (x 2..6 et x 31..35, z −25..−15) creusés jusqu'en bas — plus aucune case de
  sol à y = 0, la plus basse à y = 5. À reboucher dans MB (une case de sol au fond du passage). Fusionner toute la
  collision en une forme (3,3 M triangles) n'y changerait rien et empêcherait de la charger par morceaux : non.
- **LES À-COUPS DE LA TRAVERSÉE APRÈS LES ARBRES — RÉGLÉS (9 octobre 2026)** : 7 à 13 images > 33 ms → **0** (deux
  traversées aller-retour, pire image 28 ms, ~200 img/s). Trouvé par `banc_marche --detail` (il dit la piste, la clé
  et ce qui se lisait en même temps) : l'ENTRÉE des morceaux de COLLISION, 26 à 45 ms. ⚠ **UNE FORME CONCAVE CRÉÉE
  DANS UN FIL** (la lecture en fond) **LAISSE SON TRAVAIL AU MOTEUR PHYSIQUE, QUI LE FAIT D'UN BLOC SUR LE FIL
  PRINCIPAL** quand le morceau entre — mesuré, le même morceau : 0,1 ms lu sur le fil principal, 24 ms lu dans un fil ;
  et tout lire sur le fil principal coûtait pire (13 ms en moyenne, 44 au pire). **Remède** : la cuisson range les
  triangles de collision en DONNÉES (`world/collision_morceau.gd`, des pièces de 3 000 triangles) et le ChunkStreamer
  en fait des formes sur le fil principal, à petites doses (`_build_shapes`, `shape_budget_ms` = 2 ms par image, les
  plus proches d'abord) ; le morceau sous la cible, et les sauts (`load_around_now`), d'un coup. Et la collision est
  SOUDÉE avant d'être simplifiée (`_collision_of` : positions seules, arrondies au 1/10 de mm ; même borne de 5 cm) :
  22,8 M triangles au lieu de 27,2. Essayé et retiré : n'entrer qu'avec rien en lecture (8 à-coups au lieu de 13).
- ⚠ **LES CONTACTS DIAGONAUX FONT DES TROUS** (la charte de MB : « le monde sans contact diagonal ») : un relief
  procédural en crée (les pics), et le peintre de MB ne les pose pas. Vus : des trous bleus (le ciel) dans les
  montagnes et le volcan. Réparés par la règle même du bouton « Fix diagonal contacts » ; et la cuisson COMPTE
  désormais les tuiles manquantes (`tiles_missing`) et le DIT.
- ⚠ **LA COLLISION SIMPLIFIÉE PAR UNE PART DE TRIANGLES A SUPPRIMÉ DES SOLS DE GALERIE** (le joueur y tombait,
  y = −5,5) : elle est désormais bornée par l'ERREUR de chaque LOD (`collision_max_error`, 5 cm), et
  `tests/sonde_collision.tscn` compare la collision cuite à la collision complète, rayon par rayon (509 écarts
  avant, 0 après). ⚠ La sonde ne tire jamais sur une coordonnée entière : c'est l'arête d'une marche.
- **LES À-COUPS — RÉGLÉS (9 octobre 2026)**. Mesuré d'abord (`banc_marche -- --detail`, `--aller-retour`, `--garder`) :
  ni le code du streamer (0,04 ms par image), ni le rendu (CPU 0,3 ms, GPU 2 à 4), ni les transitions (23 avec, 23
  sans), ni la compilation des shaders ; et en revenant SANS RIEN CHARGER (`--garder`) : 0 à-coup. C'était le
  CHARGEMENT : un morceau de 32 du Val envoie ~15 Mo à la carte graphique (~300 000 sommets, trois par triangle —
  chaque triangle a sa normale, la soudure ne gagne rien), et plusieurs se lisaient à la fois. Le rendu multi-fil de
  Godot n'y change rien (23). **Remède : des morceaux de 16 (≈ 4 Mo chacun) et au plus DEUX lectures à la fois, les
  plus proches d'abord (`ChunkStreamer.max_loading`) → 0 image > 33 ms (pire 32,8 ms)** sur la traversée en courant ;
  les morceaux de 32 avec la même limite : encore 25. 460 appels de dessin au lieu de 206, ~110 img/s.
- ⚠ **UN MONDE CUIT NE SE DÉPLACE PAS** : ses morceaux renvoient à `partage/` par un chemin `res://` ABSOLU — renommé,
  plus rien ne se charge (vu : « Cannot call method 'instantiate' on a null value »). On recuit dans le bon dossier.
- **LE WORKFLOW — PEINDRE DANS MB, JOUER DANS GODOT (Jordan, 9 octobre 2026 : « le plus simplement possible »)** :
  1. MB : ouvrir `Knil_MB_project/monde_knil.mbproj`, peindre, enregistrer (Ctrl+S) ;
  2. MB : World → « Export the world… » → le dossier `D:\TheStoryOfKnil\mondes` (l'export s'appelle comme le projet :
     `mondes/monde_knil.mbworld`, réécrit sur place) ;
  3. **double-clic sur `D:\TheStoryOfKnil\recuire.bat`** (le jeu fermé ; l'éditeur Godot peut rester ouvert) : l'import, la
     cuisson (~8 min), la sonde de collision ; il dit « C'EST PRÊT » ou ce qui ne va pas (`cuit/derniere_cuisson.txt`) ;
  4. lancer le jeu. Oublié l'étape 3 ? Le jeu le DIT (`ChunkStreamer._warn_if_stale` : l'export plus récent que la
     cuisson → un message à l'écran et un avertissement).
  ⚠ **L'EXPORT SE FAIT DANS `mondes`, PAS DANS `mondes/monde_knil.mbworld`** (vu le 11 octobre 2026) : MB rangeait le
  nouveau monde DANS l'ancien dossier, et `recuire.bat` recuisait l'ANCIEN sans rien dire. Il le refuse désormais.
  La sonde de collision de `recuire.bat` prend ses points dans le monde cuit (`--points=auto`) : elle vaut pour toute carte.
- **LE MONDE PEINT À LA MAIN — EN PLACE (11 octobre 2026)** : 354 × 465 m (x −153 à 201, z −278 à 187), quatre
  couches peintes (Prairie, Pavés, SousBois, Marais), une eau de marais ; cuit en 1 min 42 : 515 morceaux, 307 000
  tuiles, 280 Mo, collision fidèle (0 écart). Les LIMITES suivent sa boîte (`monde_knil.limites.json`). Le Val v2 de
  `fabriquer_val.gd` est rangé dans `Knil_MB_project/archives/val_v2_fabrique.mbworld` (hors git, hors projet Godot).
  ⚠ `main.tscn` est encore celui du Val : les RÉGIONS (La Sablière, Désert, Volcan, Montagnes… hors de la carte),
  le bourg, l'auberge et les PNJ sont à replacer sur la nouvelle carte.
  ⚠ `fabriquer_val.gd` refait TOUT le projet : il refuse d'écraser un `monde_knil.mbproj` existant (`--ecraser`).
  ⚠ Les LIMITES du monde (±385 m) sont dans `mondes/monde_knil.limites.json`, hors du dossier que MB réécrit : un
  cadre repeint ailleurs → les y changer. ⚠ Les RÉGIONS, PNJ, lits, l'auberge sont posés dans `scenes/main.tscn` : une
  ville déplacée dans MB → les déplacer dans Godot.
- La piste « gros » est ramenée à 200 m (400 chargeait 114 morceaux de la chaîne du nord au départ).

### LES TRANSITIONS ENTRE TOUTES LES MATIÈRES — DEMANDÉ (Jordan, 8 octobre 2026), ÉCRIT ET VU LE MÊME JOUR

- **CÔTÉ MB** (`fabriquer_val.gd`) : l'état de l'atelier Transitions dans le projet et l'export — les 55 paires des 11
  couches ACTIVES, réglages par défaut de l'atelier ; représentant d'une matière neuve : son DESSUS ; d'une matière de
  l'exemple : son matériau le plus porté (le défaut de l'atelier). Tout se règle ensuite dans MB, et se réexporte.
- **CÔTÉ CUISSON** : le matériau des transitions est bâti par les fonctions du greffon (`Trans.table`,
  `Trans.cell_texture`, les représentants), posé en passe suivante sur TOUS les matériaux des tuiles. Le shader du
  greffon lit le centre de la tuile dans sa matrice (`MODEL_MATRIX`) — que la fusion efface : chaque sommet cuit porte
  le centre de SA tuile (CUSTOM0), et la COPIE CUITE du shader le lit là (`_patch_material`). Le même remède vaut pour
  la phase des textures ANIMÉES (l'ancien OUVERT (1) de la cuisson : fermé).
- ⚠ **SANS FENÊTRE, LES TEXTURES FAITES À LA VOLÉE S'ENREGISTRENT VIDES** (comme les MultiMesh) : la texture 3D des
  cases, le tableau des représentants, LA TABLE DES PAIRES. Et la couleur des représentants (un tableau de couleurs sur
  un `vec4[15]`) ne survit pas à l'enregistrement. Vu deux fois : rien ne se dessinait (« img.is_null() » au
  chargement), puis des bords NOIRS là où le greffon les dessine verts (`tests/capture_reference.tscn` : le greffon
  lui-même, au même endroit). Tout part en DONNÉES (`world/transitions_cuites.gd` : octets, images, table, couleurs),
  que le ChunkStreamer repose UNE fois sur le matériau partagé au chargement du monde.
- **ÉPROUVÉ** (`test_cuisson`, 105) : passe posée, shader cuit lisant CUSTOM0, un centre par sommet et le BON
  (v + 1 entier, à moins d'une tuile), textures, table et couleurs rebâties sur le matériau même des morceaux. Vu : le
  pied du volcan d'essai bordé de vert, comme par le greffon. Le Val : 110 entrées de table (55 paires, deux sens), une
  texture des cases de 796 × 57 × 796 ; 1,9 Go cuits (le centre par sommet empêche la soudure des sommets).

### LE SAUT — DEMANDÉ (Jordan, 9 octobre 2026), ÉCRIT LE MÊME JOUR

Espace : une impulsion pour 1,4 m (une marche du monde MB fait une case, 1 m : elle se franchit) ; on saute encore
0,12 s après avoir quitté un bord, et un appui fait 0,12 s avant de toucher le sol est retenu ; en l'air, 60 % de la
commande. Tombé à plus de 30 m sous le dernier sol touché : retour à ce sol. L'animation reçoit
`parameters/conditions/airborne` (ou joue « jump »). MESURÉ (`sonde_scene`) : +1,44 m, retour au sol.

### LES ZOOMS — DEMANDÉS (Jordan, 8 octobre 2026), ÉCRITS LE MÊME JOUR

- **La MOLETTE** : le zoom continu (`CameraRig.zoom`, 0,35 à 4, ×1,15 par cran), dans les deux vues.
- **CTRL + MOLETTE** : deux états, indépendants du zoom — vers le bas, la VUE HAUTE (130 m au-dessus du joueur) ; vers
  le haut, le retour à sa hauteur (le zoom de la molette est gardé).
- La caméra dit ce qu'elle voit au sol (`EventBus.view_radius_changed`) : le ChunkStreamer charge les pistes VISIBLES
  jusqu'à 1,3 × ce rayon + 24 m (la collision, non) ; le feuillage s'efface plus loin. MESURÉ (`capture_zoom`) : rayon
  vu 15 m, 31 m après cinq crans, 127 m en vue haute — 18, 19 puis 35 à 46 morceaux de sol chargés ; ~200 à 360 img/s.
  ⚠ En vue haute, le bord de ce qui est chargé se voit un moment (les morceaux arrivent un par image) : une vue
  LOINTAINE cuite (un maillage très simple du monde entier) le remplacerait — à faire si la vue haute reste.

### LA CUISSON PAR MORCEAUX — ÉCRITE ET MESURÉE (8 octobre 2026)

**Le chemin d'un monde** : peint dans le logiciel MB → World, « Export the world… » → le dossier `.mbworld` copié
sous `mondes/` → **cuit** → `cuit/<nom>/` → chargé en jeu par `ChunkStreamer` (le nœud `Monde` de `main.tscn`).

```
"$GODOT" --headless --path D:/TheStoryOfKnil --import      # après avoir copié un .mbworld (ses .glb s'importent)
"$GODOT" --headless --path D:/TheStoryOfKnil res://tools/cuisson/cuire.tscn -- --monde=res://mondes/<nom>.mbworld/world.json
         [--sortie=res://cuit/<nom>] [--morceau=32] [--sans-lod] [--compression] [--sans-collision]
```

- **RIEN N'EST RÉÉCRIT** (`tools/cuisson/cuisson.gd`) : le monde est bâti hors écran PAR LE GREFFON (`WorldFile.build` :
  règle de pose, eau, feuillage, matériaux), puis récolté et découpé. Le greffon ne sert qu'à la cuisson : **le jeu ne
  le charge jamais** (vérifié : aucun morceau ne renvoie à `addons/`).
- **UN MORCEAU** (32 × 32 colonnes, toute la hauteur) : `Surface` (tuiles à l'air libre) et `Couvert` (sous couvert :
  grottes, surplombs — la règle d'air libre du greffon), fusionnées, UNE surface par matériau (les matériaux aux mêmes
  réglages fusionnés), avec LOD ; `Eau` (la nappe, découpée par triangle) ; `Feuillage` (les plants en DONNÉES, faits
  MultiMesh au chargement par `world/feuillage_morceau.gd`, effacés au-delà de 80) ; et À PART `collision/c_*.scn`.
  Ce qui est partagé (matériaux, textures, shaders, maillages des plants) est écrit une fois dans `partage/`.
  `monde.json` : les morceaux, leurs boîtes, leurs comptes, l'empreinte md5 de la source.
- **ÉPROUVÉ, PREMIÈRE VERSION (avant les couches)** (`test_cuisson`, 47 vérifications, sur le monde d'essai fait par
  `tests/fabriquer_monde_essai.tscn` : collines, plateau, butte percée d'un tunnel, lac, 551 arbres) : chaque triangle
  du greffon une fois et un seul ; la MÊME GÉOMÉTRIE (somme des aires et des centres des triangles — un compte de
  triangles ne voyait pas une tuile mal tournée) ; le tunnel en `Couvert` ; la nappe ; chaque arbre à sa place ; LOD ;
  collision ; le chargement : peu de morceaux au départ, la collision seulement tout près, un saut recharge d'un coup,
  la marche suit en fond. **Mutations rouges** : tuiles non tournées, tout « à l'air libre ».
- ⚠ **SANS FENÊTRE, UNE MULTIMESH NE GARDE PAS SES INSTANCES** (le rendu factice de `--headless`) : lue, elle rendait
  551 arbres à l'origine ; écrite, elle les aurait perdus. D'où les poses refaites par `instances()` du greffon, et le
  feuillage cuit en données.
- ⚠ **UN PACKED*ARRAY ALLONGÉ DANS UN DICTIONARY EST RECOPIÉ À CHAQUE AJOUT** (copie sur écriture) : la fusion se fait
  dans des variables locales (`_merge`) ; et la clé d'un matériau se calcule une fois, pas par tuile (31 s → 0,6 s).
- **MESURÉ — la cuisson** : 128² colonnes 11 s (1,24 M triangles, 26 morceaux, 25 Mo) ; **256² colonnes 34 s**
  (4,8 M triangles, 81 morceaux, **100 Mo**). La fusion des sommets identiques ne gagne RIEN sur le témoin (chaque
  triangle y a sa propre normale) ; elle gagnera sur des tuiles lissées. La compression 16 bits : 26 → 25 Mo pour
  ~1 mm d'écart et des fentes possibles entre morceaux — éteinte par défaut (`--compression`).
- **MESURÉ — en jeu** (`tests/banc_marche.tscn`, traversée du 256² en courant, vue de dessus, RTX 2060) : ~210 img/s,
  ~86 appels de dessin, 26 morceaux montrés au plus sur 81. **Les à-coups venaient de la COLLISION** : forme concave
  pleine dans chaque morceau montré, 46 images > 33 ms (pire 273) ; sans collision : 0. Remèdes : la forme bâtie sur
  un LOD (¼ des triangles), l'instanciation dans un fil de travail, la lecture sans sous-fils, et **la collision à
  part, chargée à 20 de la cible seulement → 3 à 4 images > 33 ms par traversée** (pire 60 à 97 ms). Jolt n'y change
  presque rien (36 au lieu de 46, essayé avant les remèdes). La physique sur son propre fil
  (`physics/3d/run_on_separate_thread`) : 3 au lieu de 4 — PAS activée (elle change le fil des rappels physiques du
  jeu ; à décider).


## 3. L'architecture — ÉCRITE (8 octobre 2026, recentrée sur Knil le 10)

Godot 4.7, GDScript. Commentaires et données en français, identifiants en anglais (l'API de Godot l'est).

```
core/        LE BACKEND — autoloads, sans aucune présentation
  event_bus.gd        EventBus : tous les signaux (lieux, vue, dialogue, temps, partie)
  game_clock.gd       GameClock : LE temps (minutes depuis le début), phases, saisons, avance accélérée
  game_state.gd       GameState : l'état sauvé, par CHEMINS (« player.money ») — Knil (vie en demi-cœurs, argent,
                      objets), le lieu, l'état des entités du monde, les faits
  save_system.gd      SaveSystem : un JSON par emplacement (F5 / F9)
  inputs.gd           les touches (PHYSIQUES : W A S D = Z Q S D en AZERTY) et la manette, déclarées en code
  triche.gd           la triche (§4)
data/        triche.json
tools/cuisson/  la cuisson d'un .mbworld en morceaux (§2), et `couches.json` : le rôle de chaque couche — outil,
             ne part pas dans le jeu
mondes/      les .mbworld exportés par le logiciel MB (les SOURCES) · cuit/ : les mondes cuits (générés, hors git)
world/       les nœuds posés dans le monde
  region.gd           Region (Area3D) : ville, capitale, forêt, lac, montagne, désert… — emboîtables
  interior.gd         Interior (Area3D) : maison, auberge… — passe la caméra en 3e personne ; « souterrain » :
                      l'intérieur AUTOMATIQUE des galeries (`set_underground`, dit par le ChunkStreamer)
  interactable.gd     Interactable (Area3D) : ce à quoi on parle — ses répliques (`lines`), une par appui
  frappable.gd        Frappable (Area3D, couche 6) : ce que les coups de Knil touchent — il DIT le coup (`struck`),
                      son porteur en fait ce qu'il veut (perdre de la vie, reculer, se briser)
  chunk_streamer.gd   ChunkStreamer : les morceaux cuits chargés autour du joueur (le visible, puis la collision)
  feuillage_morceau.gd  les plants d'un morceau, faits MultiMesh au chargement
  souterrain_morceau.gd  le sous-sol d'un morceau (l'air enfoui) : le joueur est-il sous terre ?
  day_night.gd        le soleil et le ciel suivent l'horloge ; la nuit, une LUNE (ombrée : sans ombre elle éclairait
                      l'auberge à travers le toit, vu) et un plancher d'ambiante ; dans un intérieur l'ambiante baisse
  prefabs/            pnj.tscn (provisoire)
  contour/            LE CONTOUR NOIR, repris de Spirit3D (HEART_WORLD) tel quel : `OutlineHull` (la coque inversée,
                      2 px d'écran, enfant INTERNE sans ombre, liée au squelette ; normales recuites aux arêtes vives)
                      et `SubtreeOutline` (un nœud sous un objet : tout son sous-arbre souligné). Posé sur Knil
                      (`player.tscn`, `Contour` → `Modele`) et de lui-même par CHAQUE `Interactable` — un objet
                      d'intérêt neuf : en faire un Interactable, ou lui poser un `SubtreeOutline`. Méta
                      `_outline_skip` : un nœud et son sous-arbre exclus. Le monde et les bâtiments : jamais.
ennemis/     ennemi.gd (Ennemi : voit, court, frappe, chancelle, meurt — §3, LE PREMIER ENNEMI), dealer.tscn
player/      player.gd/.tscn (CharacterBody3D : Knil), camera_rig.gd (les deux vues et leur fondu), torche.gd (la
             torche : allumée d'elle-même hors du plein jour et dans un intérieur, T la force)
ui/          hud.gd (provisoire) : cœurs, argent, heure, lieu, le COMPTEUR (img/s et pire image, à droite) ; la boîte de dialogue
  livre/              LE LIVRE, le menu copié de Spirit3D (§4) : book.gd, cell.gd, la cellule de base, les flèches,
                      la touche de coin ; cells/ : game_cell (le jeu), page_cell et ses pages (commandes, options,
                      sauvegardes, quitter)
scenes/      livre.tscn — LA SCÈNE PRINCIPALE : le livre, le monde (main.tscn) dans la cellule « Jouer »
             main.tscn — le bac à sable : le monde cuit, les régions, une auberge, quatre PNJ qui parlent (les
             épreuves le chargent seul, sans le livre)
tests/       les épreuves (§5)
```

**Couches physiques** : 1 le monde (tuiles, bâtiments) · 2 le joueur · 4 les interactables · 5 (valeur 16) les troncs ·
6 (valeur 32) les Frappables · 7 (valeur 64) les ennemis (Knil les heurte : `Player.WORLD_MASK`).

**LE DIALOGUE** : `E` / `X` près d'un Interactable → `interact()` montre la réplique suivante
(`EventBus.dialogue_shown`) ; après la dernière, ou `Échap` / `B`, la boîte se ferme (`dialogue_closed`). Pendant un
dialogue, Knil ne bouge pas et ne saute pas.

**LE COMBAT — PRÉPARÉ (Jordan, 11 octobre 2026 : « prépare les attaques de Knil, coup de genou, et se mettre en boule
avec le bouclier sur la tête, même s'il manque les anims »)** — dans `player.gd` (`Action` : NONE, KNEE, GUARD, KICK) :
- **LE COUP DE GENOU** (`attack`) : armée 0,12 s (Knil s'élance à 3 m/s, ne se dirige plus), frappe 0,14 s — chaque
  Frappable dans une boule de 0,55 m, 0,75 m devant lui, UNE fois par coup : 2 demi-cœurs, poussé à 6 m/s —,
  rétablissement 0,28 s ; un appui pendant le rétablissement ENCHAÎNE. Pas en dialogue, pas en vol de triche.
  ⚠ À LA MANETTE, X EST AUSSI « PARLER » (Jordan, 11 octobre 2026 : « X genou Y kick ») : quelqu'un à portée, X
  parle et ne frappe pas ; seul, X frappe. F et le clic gauche ne font jamais parler.
- **LE COUP DE PIED** (`kick` : G, Y — demandé le 11 octobre 2026) : le même déroulé que le genou, plus lent, plus
  loin, plus fort (`kick_*`) — armée 0,22 s (élan 1,5 m/s), frappe 0,19 s dans une boule de 0,55 m à 1,1 m devant,
  0,8 m du sol : 3 demi-cœurs, poussé à 9 m/s —, rétablissement 0,31 s. Animé : « Kicking » de Mixamo → « pied »
  (0,40–1,55 s joué ×1,6 = 0,72 s, le pied au sommet à 0,34 s, à hauteur de ventre). Vu à l'image.
- **EN BOULE** (`guard`, tenu) : recroquevillé, le bouclier sur la tête ; il ne marche, ne saute, ne frappe plus.
  Après 0,15 s (`guard_enter_time`), tout coup est PARÉ, de tous les côtés (en boule, pas de face) : poussé à 30 %.
- **KNIL FRAPPÉ** : `Player.take_hit(demi-cœurs, poussée)` — paré en boule, sinon `player.health` baisse et il est
  invulnérable 0,6 s. ⚠ À zéro, rien encore : LA MORT est à faire (les ennemis cessent seulement de frapper).
- L'EventBus : `player_attacked`, `player_hit`, `player_guard_changed`, `player_damaged`.
- **LE GENOU EST ANIMÉ (11 octobre 2026)** : « Illegal Knee » de MIXAMO (`assets/personnages/knil/animations/
  illegal_knee.fbx`), Knil lui-même passé dans Mixamo — MÊME squelette que le .glb de Tripo (65 os, mêmes repos) :
  pas de reciblage. L'import de `knil.glb` (`MIXAMO` dans `tools/import/knil_animations.gd`) en fait « genou » :
  0,30–1,35 s joué ×2,1 = 0,5 s, le sommet du genou à 0,21 s (dans la frappe, 0,12–0,26), hanches à l'aplomb. Vu à
  l'image : le genou droit part devant, sous le ventre. Une autre animation de Mixamo : le .fbx dans `animations/`,
  une ligne dans `MIXAMO`, puis RÉIMPORTER `knil.glb` (effacer `.godot/imported/knil.glb-*.scn`, `--import` — un .fbx
  changé ne le fait pas, effacer le .md5 non plus). Les .fbx ne partent pas dans l'export (filtre).
- **LA BOULE N'EST PAS ANIMÉE** : `anim_guard` (« boule ») manque — la DOUBLURE (le modèle s'écrase) tient lieu.
  Un AnimationTree recevrait `parameters/conditions/knee`, `kick` et `guarding`.
- Le BOUCLIER n'est pas un objet du GameState : Knil l'a toujours. À trancher (le trouver dans un donjon ?).
- **LE PREMIER ENNEMI : LE DEALER (Jordan, 12 octobre 2026 : « fais ce mob qui s'approche et attaque ensuite, je les
  placerai moi-même dans la map »)** — `ennemis/dealer.tscn`, à poser où l'on veut (dans `main.tscn` ou ailleurs) : il
  garde l'endroit où il est posé (`home`). `ennemis/ennemi.gd` (`Ennemi`, générique — un autre mob : une autre scène,
  le même script, ses réglages) : en garde chez lui ; VOIT Knil à 9 m (un rayon contre le décor : pas à travers un mur) ;
  COURT vers lui (4,5 m/s : Knil à la course le sème) ; à 1,3 m il FRAPPE — armée 0,36 s (il se tourne vers Knil),
  frappe 0,16 s (Knil devant lui, à 1,6 m, cône de 60° : 2 demi-cœurs, poussé à 7 m/s ; la BOULE pare), rétablissement
  0,4 s, souffle 0,6 s ; semé (16 m, ou caché 3 s) il RENTRE en marchant. Frappé : il perd de la vie (6 demi-cœurs :
  trois genoux, deux pieds), recule, CHANCELLE 0,45 s — son armée est COUPÉE ; il ne lâche plus Knil. Mort : il tombe,
  ne heurte plus rien, s'enfonce et disparaît (4 s). Rien n'est sauvé : la partie relue, il est de retour.
  **POUR LES POSER : L'APERÇU DU MONDE DANS L'ÉDITEUR** (`world/apercu_monde.gd`, le nœud `Monde/ApercuMonde` de
  `main.tscn`, @tool) : dans l'éditeur seulement, TOUS les morceaux cuits (1 030 avec la collision, ~30 s, en fond),
  le feuillage et la COLLISION — glisser `dealer.tscn` dans la vue le pose sur le sol, Page Down le colle au sol.
  Rien n'est enregistré (enfants internes sans propriétaire) ; en jeu il s'efface ; verrouillé. Recuit : rouvrir la
  scène. Vérifié dans un éditeur (copie du projet) : la carte vue, 257 rayons sur 391 touchent le sol (le reste : hors
  carte). Le nœud `Ennemis` de `main.tscn` est là pour les ranger. Les épreuves qui chargent `main.tscn` y retirent
  les ennemis (ils frapperaient Knil au milieu d'une autre épreuve).
  LE MONDE PAR MORCEAUX : à plus de 45 m de Knil il DORT (et, semé hors de chez lui, y est ramené d'un coup, vie
  refaite) ; sans collision chargée sous lui, il ne tombe pas. Une marche d'une case : il la saute. Pas de navigation :
  il va droit sur Knil (un mur entre eux, il le perd de vue et rentre).
  L'EventBus : `enemy_alerted`, `enemy_attacked`, `enemy_damaged`, `enemy_died`.
  **LE MODÈLE** : `assets/personnages/dealer/dealer.fbx` (Tripo, sweat à capuche, ~19 600 triangles, échelle 1,8 →
  ~1,77 m), MÊME SQUELETTE MIXAMO que Knil mais PAS LES MÊMES REPOS (jusqu'à 118° d'écart, du roulis). ⚠ Son FBX ne
  porte qu'UNE animation (le nom en annonce cinq — run, front_kick_02, walk, hit_to_head, hit_to_stomach — mais il
  n'y a qu'une pile de 2,33 s : une GARDE de boxe sur place → « garde »). Les autres sont CELLES DE KNIL, RECALÉES
  (`tools/import/recaler_animations.gd`, le mouvement vu dans le monde recopié os par os ; la commande est en tête du
  script) dans `dealer_animations.res` : course ← run_001, marche ← walk_001, coup ← pied, genou ← genou, touche ←
  hit_to_side_001, mort ← defeat_03_001. Vu à l'image : toutes justes. ⚠ Les animations de Knil changées : relancer
  l'outil. Ses propres animations venues (un export Tripo par animation) : les mettre dans `--propres`.
- ÉPROUVÉ : `sonde_ennemi` (25 : caché par un mur il ne voit pas ; il voit, court, s'arrête à portée, frappe — Knil
  6 → 4 ; la boule pare ; un genou dans son armée la coupe ; il meurt, disparaît ; semé il rentre ; endormi loin ;
  ne tombe pas sans collision ; mutation : la vue à travers les murs → 2 rouges). Vu à l'image dans le monde : il court
  vers Knil et lui met le pied.
- ÉPROUVÉ : `sonde_combat` (34, sans le monde cuit ; « genou » et « pied » se jouent, sans doublure ; le pied touche, pousse plus fort, pas à 3 m). Mutations rouges : un coup qui touche à chaque image ; la boule
  qui pare dès l'appui.

## 4. Commandes de jeu (provisoires)

À LA MANETTE (Xbox) : stick gauche se déplacer · clic du stick ou RB courir · A sauter · X parler (près de
quelqu'un) ou coup de genou · Y coup de pied · B fermer · croix ↑ torche · stick droit ← → tourner la troisième personne, ↑ ↓ zoomer · Back vue haute · Start le livre. Les textes à l'écran suivent
le dernier appareil touché (`core/inputs.gd`, la table des deux). ÉPROUVÉ par de faux événements (`sonde_manette`,
17) — PAS ENCORE TENU EN MAIN avec une vraie manette.
COMBAT : F / clic gauche / X le coup de genou · G / Y le coup de pied · R / LT (tenus) en boule sous le bouclier (LT descend aussi en vol de
triche — jamais les deux à la fois).
AU CLAVIER : W A S D (Z Q S D en AZERTY) se déplacer · Maj courir · Espace sauter (1,4 m) · E parler · T torche
(automatique → allumée → éteinte) · molette : zoom · Ctrl + molette : vue haute / retour · Échap fermer ·
F5 / F9 sauvegarde rapide · clic droit + souris : tourner la vue en troisième personne · Échap (hors dialogue) le livre.

**LE LIVRE — LE MENU DE SPIRIT3D, COPIÉ ET BRANCHÉ (Jordan, 10 octobre 2026 : « copie le menu de spirit3d (le système
de book) et branche-le au jeu, PC et manette »)** — `ui/livre/`, `scenes/livre.tscn` (la scène principale). Copié de
`D:/Spirit3D/BOOKS` : `Book`, `Cell`, `BOOKCELL_BASE` (→ `cell_base.tscn`), la vignette brillante, les flèches, la
touche de coin ESC / MNU. Une planche de 1600 × 900 (16:9 : le jeu remplit l'écran ; Spirit3D est en 2:1), huit
cellules de 400 × 450 : **Jouer** (le monde, dans un SubViewport rendu à la résolution de l'ÉCRAN, l'icône de Knil
dessus), **Commandes**, **Options** (plein écran, synchro verticale, volume, résolution 3D ; `user://options.cfg`),
**Sauvegardes** (la rapide et trois emplacements ; charger rend le jeu), **Quitter** ; trois emplacements vides.
- Le jeu DÉMARRE agrandi. Échap / Start / la touche MNU : le livre s'ouvre, **le jeu est EN PAUSE**
  (`get_tree().paused` ; le livre est PROCESS_MODE_ALWAYS), le HUD caché, le monde figé derrière « Jouer ».
- Livre ouvert : croix / stick gauche / flèches choisissent une cellule (la souris aussi, au survol), A / Entrée /
  clic l'ouvrent, B / Échap referment une page ; Start, Échap ou B rendent le jeu ; F1–F8 ouvrent la cellule n° N.
- ⚠ **F1–F8 NE MARCHENT QUE LIVRE OUVERT** (dans Spirit3D, partout) : en jeu, F1–F5 et F9 sont à la triche et à la
  sauvegarde. ⚠ Échap EN DIALOGUE ferme le dialogue, PAS le jeu (`GameCell._should_reset_on_escape`).
- ⚠ **START EST AU LIVRE** : le vol de triche est passé sur **LB**. Et Godot ne met pas A dans `ui_accept` (ni B dans
  `ui_cancel`) : `Inputs.ensure()` les ajoute — sans eux, la manette ne presse aucun bouton des pages.
- ⚠ La cellule de base de Spirit3D donnait à `Cell_Contain` une taille minimale de 450 (leurs cellules) : en 400, le
  monde débordait de 25 de chaque côté — retirée.
- Retiré de Spirit3D (sans objet ici) : la session et les comptes, la cellule ADMIN, la chaîne d'accueil
  (`BookCellsSystem`, le voile, le bouton « Jouer »), le double appui des touches de fonction.
- ÉPROUVÉ : `sonde_livre` (29). Vu à l'image : le jeu, le livre (le monde figé derrière Knil), Options, Commandes.

**L'EXPORT WINDOWS — PRÊT (10 octobre 2026)** : `export_presets.cfg`, preset « Windows PC » (x86_64, release, le
`.pck` à côté de l'exe, l'icône de Knil dans l'exe). `"$GODOT" --headless --path D:/TheStoryOfKnil --export-release
"Windows PC" export/windows/TheStoryOfKnil.exe` (`export/` est hors git) : **exe 109 Mo + pck 1,8 Go** (presque tout :
`cuit/monde_knil`), ~2 min. Lancé : le monde se charge, aucune erreur, ~560 img/s. Dehors : les autres cuissons
(`cuit/val_e12`, `cuit/essai` : 1,75 Go), les sources `mondes/`, `tests/`, `tools/`, `addons/` (le greffon : le jeu
ne le charge jamais), la planche de référence. Dedans en plus des ressources : `data/*.json`, `cuit/monde_knil/
monde.json`, l'`.ico`. ⚠ Un AUTRE monde cuit à livrer : l'ajouter aux filtres. ⚠ **LA TRICHE PART DANS L'EXPORT**
tant que `data/triche.json` dit `"actif": true`. ⚠ `application/company_name` et `copyright` sont VIDES : à remplir.

**LA TRICHE — ACTIVE (Jordan, 9 octobre 2026 : « active le cheat et tu le désactiveras quand je te le demanderai »).**
`data/triche.json` → `"actif": true` ; À ÉTEINDRE (`false`) QUAND JORDAN LE DEMANDE, pas avant. `core/triche.gd` :
F1 / LB le VOL (Espace / A monte, C / gâchette gauche descend, pas de gravité) · F2 le FANTÔME (on traverse tout ;
vol compris) · F3 / clic du stick droit la VITESSE ×1, ×3, ×8 · F4 +1 h. Le HUD l'affiche en orange. Éteinte, ses
touches ne font rien. ÉPROUVÉE : `sonde_triche_limites` (11).

**LES LIMITES DU MONDE — RADICALES (même demande).** Le monde cuit porte `play_bounds` (±385 m, lues dans
`mondes/<nom>.limites.json`, à côté du dossier `.mbworld`) ; le ChunkStreamer en fait QUATRE MURS invisibles de 600 m
de haut (`Monde/Limites`) et les donne au joueur (`Player.world_bounds`), qui est ramené en dedans À CHAQUE IMAGE
(position et vitesse), en marchant, en volant, en fantôme : grimper sur le cadre par un bug ne fait sortir de rien.
Les troncs d'arbre sont sur la couche physique 5 (valeur 16) : le joueur les heurte, la caméra non.

## 5. Les épreuves

```
GODOT=/c/Users/jorda/Desktop/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe
"$GODOT" --headless --path D:/TheStoryOfKnil --import                          # la première fois
"$GODOT" --headless --path D:/TheStoryOfKnil res://tests/fabriquer_monde_essai.tscn   # le monde d'essai (.mbworld)
"$GODOT" --headless --path D:/TheStoryOfKnil res://tests/test_cuisson.tscn     # la cuisson par couches et fenêtres, le chargement, le sous-sol : 94
"$GODOT" --headless --path D:/TheStoryOfKnil res://tests/sonde_scene.tscn      # la scène : morceaux, sol, région, caméra, dialogue, saut, galerie
"$GODOT" --path D:/TheStoryOfKnil --windowed res://tests/banc_marche.tscn       # la traversée du grand monde : à-coups
"$GODOT" --path D:/TheStoryOfKnil --windowed res://tests/capture_nuit.tscn      # la nuit : lune, ambiante, torche (user://captures)
"$GODOT" --path D:/TheStoryOfKnil --windowed res://tests/capture_couches.tscn   # la place et ses massifs, le volcan, une galerie
"$GODOT" --path D:/TheStoryOfKnil --windowed res://tests/capture_monde.tscn -- --monde=res://cuit/monde_knil [--lieux=x,y,z;…]
"$GODOT" --headless --path D:/TheStoryOfKnil res://tests/sonde_collision.tscn -- --monde=…  # collision cuite = rendu ?
"$GODOT" --headless --path D:/TheStoryOfKnil res://tests/sonde_galerie.tscn -- --monde=… [--escalier=x,z]  # la galerie se parcourt ?
"$GODOT" --path D:/TheStoryOfKnil --windowed res://tests/capture_zoom.tscn       # molette, Ctrl + molette, ce qui se charge
"$GODOT" --headless --path D:/TheStoryOfKnil res://tests/sonde_manette.tscn     # la manette (faux événements) : 17 vérifications
"$GODOT" --headless --path D:/TheStoryOfKnil res://tests/sonde_triche_limites.tscn   # la triche et les limites : 11 vérifications
"$GODOT" --path D:/TheStoryOfKnil res://tests/banc_course.tscn [-- --gel --arret --dir=0,1]   # le VRAI jeu, Knil court : les images lentes détaillées
"$GODOT" --headless --path D:/TheStoryOfKnil res://tests/sonde_chute.tscn [-- --vitesse=8]   # Knil traverse-t-il le sol ?
"$GODOT" --headless --path D:/TheStoryOfKnil res://tests/sonde_camera.tscn    # la bascule verticale, le bras-ressort : 8
"$GODOT" --headless --path D:/TheStoryOfKnil res://tests/sonde_combat.tscn    # le genou, le pied, la boule, les coups reçus : 34
"$GODOT" --headless --path D:/TheStoryOfKnil res://tests/sonde_ennemi.tscn    # le dealer : voir, courir, frapper, chanceler, mourir, rentrer : 25
"$GODOT" --headless --path D:/TheStoryOfKnil res://tests/sonde_livre.tscn       # le livre (menu) : pause, sélection, pages, manette : 29
"$GODOT" --path D:/TheStoryOfKnil --windowed res://tests/sonde_contour.tscn   # le contour noir : 15 (headless aussi ; avec fenêtre, des captures)
"$GODOT" --path D:/TheStoryOfKnil --windowed res://tests/capture_reference.tscn -- --monde=… --lieu=x,y,z  # le GREFFON, pour comparer
"$GODOT" --headless --path D:/TheStoryOfKnil res://tests/banc_taille.tscn      # le temps de pose selon la taille du monde
"$GODOT" --path D:/TheStoryOfKnil res://tests/capture_scene.tscn                # des captures (user://captures)
"$GODOT" --path D:/TheStoryOfKnil res://tests/banc_rendu.tscn --disable-vsync [-- --cuit]   # le rendu, GridMap ou cuit
```

**MESURÉ le 10 octobre 2026, après le passage à Knil** : `sonde_manette` 13 / 13 (le stick avance, A saute, X fait
parler la marchande, on ne bouge pas pendant le dialogue, B ferme, zoom, vue haute, retour au clavier) ;
`sonde_triche_limites` 11 / 11 ; `sonde_scene` : le joueur au sol (y = 0,75) dans la région « capitale » en vue de
dessus ; dans l'auberge → intérieur « auberge », TROISIÈME PERSONNE, l'aubergiste parle ; saut +1,44 m ; dans une
galerie → souterrain, troisième personne, torche allumée.

## 6. OUVERT

- **LE RENDU D'UN GRAND MONDE — MESURÉ (8 octobre 2026, RTX 2060, `tests/banc_rendu.tscn`, monde de 256² colonnes,
  152 000 tuiles du témoin).** Le GridMap du greffon : vue de dessus du jeu **4 370 appels de dessin, 189 img/s** ;
  tout le monde à l'écran **8 655 appels, 48 img/s** — pour 0,17 à 0,31 M triangles seulement. **Ce ne sont pas les
  triangles qui coûtent, ce sont les APPELS DE DESSIN** (une MultiMesh par tuile différente et par octant de 8³).
  Les mêmes tuiles CUITES en morceaux de 32 × 32 colonnes, UN maillage par morceau, une surface par matériau
  (`-- --cuit`) : vue de dessus **66 appels, 419 img/s** ; tout le monde **183 appels, 247 img/s** (4,8 M triangles :
  il reste de la marge, et des LOD à gagner). ⚠ La cuisson a pris **80 s en GDScript** : elle se fait HORS DU JEU,
  une fois par export du monde, jamais au chargement.
  **DONC, LA STRATÉGIE — PROPOSÉE** : (1) cuire le monde en MORCEAUX (maillage fusionné par matériau + LOD +
  collision cuite) ; (2) les charger / décharger autour du joueur en fond (`ResourceLoader.load_threaded_request`) ;
  (3) `visibility_range` et brouillard au loin — la vue de dessus voit peu de monde, c'est un atout ; (4) les
  intérieurs et grottes dans leurs propres morceaux, montrés seulement quand on y est (la vue de dessus cache le
  sous-sol, la 3e personne est enfermée) ; (5) l'eau cuite par morceaux, l'OCÉAN au loin en un seul plan de shader ;
  (6) le feuillage en MultiMesh PAR MORCEAU, avec `visibility_range` et fondu ; (7) les PNJ n'existent comme nœuds
  qu'autour du joueur — au loin ils vivent dans le GameState seul, animation coupée hors champ. Et à mesurer avec le VRAI jeu de tuiles : le nombre de matériaux
  (l'export MB en donne un par maillage — « sand », « sand2 »… — à fusionner, sinon les appels remontent).
- **LE MONDE DE 2048² — À DÉCIDER AVANT DE LE PEINDRE (mesuré le 8 octobre 2026).** Sur le monde d'essai en
  **512²** (Sol épais de 10 cases, galeries sous presque toute la carte : 2,5 M cases, 834 000 tuiles) : `world.json`
  **28 Mo**, cuisson **161 s**, **1 Go** de mémoire au plus, **511 Mo** cuits, **28 M triangles** (tuiles du témoin,
  ~34 triangles par tuile). Mis à l'échelle de **2048²** (× 16) : ~40 M cases, `world.json` ~450 Mo, cuisson ~45 min,
  **~16 Go de mémoire** (le .mbworld se lit d'un bloc), **~8 Go cuits**, ~450 M triangles. Et le plus grand monde
  MESURÉ dans le logiciel MB fait ~500 000 cases (sa charte) : 80 fois moins.
  **MESURÉ EN 1024²** (même monde, 10 M cases, 3,3 M tuiles) : `world.json` **116 Mo**, cuisson **10 min 45 s**
  (dont la règle 82 s), **4,2 Go** de mémoire au plus, **2,0 Go** cuits, **113 M triangles**, 1 089 morceaux. En jeu
  (`banc_marche`, traversée en courant) : ~550 img/s en moyenne, 123 appels de dessin, au plus 22 morceaux chargés —
  mais **16 images > 33 ms** (pire 69 ms) contre 3 à 4 en 256² sans galeries : la collision des galeries alourdit
  chaque morceau (26 000 triangles de collision en moyenne). ⚠ Le lac de ce monde d'essai est VIDE : la nappe déduite
  par le greffon (GDScript) sur 10 M cases n'a rien donné — un défaut du FABRICANT d'essai, pas de la cuisson (MB cuit
  la nappe lui-même). **784²** (déduit : la mise à l'échelle 512² → 1024² est linéaire à ±5 %) : ~5,9 M cases,
  `world.json` ~68 Mo, cuisson ~6 min 20, ~2,5 Go de mémoire, ~1,2 Go cuits, ~66 M triangles.
  **LES BASCULES DE VUE — MESURÉ** (`tests/banc_vues.tscn`, 1024², RTX 2060) : la vue ne charge rien, le
  ChunkStreamer charge autour du JOUEUR quelle que soit la caméra — la troisième personne face à l'horizon ne voit que
  les morceaux déjà là (17 de sol, 4 du volcan), jamais la carte entière. De dessus 661 img/s, 127 appels, 0,73 M
  triangles ; troisième personne en surface 629 img/s ; dans une galerie 605 img/s, 1,19 M triangles (la surface
  au-dessus est dessinée aussi). Pire image PENDANT une bascule : 2 à 3,4 ms (entrée, sortie de galerie, surface).
  ⚠ Un SAUT de plus de 40 (réveil ailleurs, sauvegarde relue) recharge d'un coup, sur le fil principal : 181 ms vu —
  à couvrir d'un fondu au noir à ces moments-là. Les leviers, à trancher : (1) la TAILLE
  D'UNE CASE (`cell_size` : 2048 cases de 1 m ou 1024 de 2 m — quatre fois moins de tout) ; (2) la DENSITÉ des tuiles
  (le vrai jeu de tuiles, plus léger que le témoin ?) ; (3) des galeries MOINS partout ; (4) côté MB, un export du monde
  PAR RÉGIONS (ou un format binaire des cases) — la cuisson par fenêtres est prête pour, la lecture d'un bloc ne l'est
  pas ; et la tenue du logiciel MB lui-même sur des dizaines de millions de cases.
- **CE QUI RESTE DE LA CUISSON — OUVERT** : ~~(1) les shaders d'animation et de transitions et l'origine de la
  tuile~~ — FAIT (§2, les transitions : CUSTOM0) ; (2) le POIDS : 100 Mo pour 256² avec le témoin (~32 triangles par tuile) — à
  remesurer avec le vrai jeu de tuiles ; (3) 3 à 4 à-coups par traversée, à chercher au profileur de Godot ; (4) la
  cuisson est en GDScript : un « Export baked world » dans le logiciel MB la ferait à la source, plus vite ; (5) une
  cuisson PÉRIMÉE (le .mbworld changé depuis) se voit à `source_md5`, mais rien ne la refuse encore.
- ~~**LE MONDE LARGE, LE CHARGEMENT — À DÉCIDER AVANT DE PEINDRE LE MONDE.**~~ Décidé et écrit : la cuisson (§2). Mesuré (`banc_taille`) : le greffon pose
  ~13 µs par case, linéaire — 64² colonnes 175 ms, 128² 0,7 s, **256² 3,0 s** (227 000 cases). Un monde de 1 024²
  colonnes prendrait ~50 s au chargement. Trois voies, cumulables : (a) **découper en morceaux** (une scène par
  région, chargées / déchargées autour du joueur) — ⚠ à vérifier : deux mondes voisins séparés se ferment chacun
  à leur bord (une paroi à la couture) ; (b) **cuire** les tuiles posées dans la scène (le greffon les refait à
  chaque `_ready` aujourd'hui) ; (c) **le cœur C++ dans le greffon** (étape 4 de MB : la pose y est 3,6× plus
  rapide, mesuré dans l'appli). Recommandation : (a) d'abord, et demander (c) à MarchingBlocks.
- **LES RÉGIONS** sont des volumes posés à la main (`Region`). Alternative : les déduire des couches MB (une couche
  « sable » = désert). À trancher quand le vrai monde existe.
- **LE PERSONNAGE ANIMÉ** : `Player` attend un `AnimationTree` (`parameters/move/blend_position`,
  `parameters/conditions/sleeping`) ou un `AnimationPlayer` (`idle`, `walk`, `run`, `sleep`).
  **LE MODÈLE EST LÀ (10 octobre 2026)** : `assets/personnages/knil/knil.glb` (Tripo, ~20 700 triangles, squelette
  MIXAMO de 65 os `mixamorig_*`, 22 animations PRÉRÉGLÉES de Tripo — idle, walk, run, jump, swagger, angry, laugh,
  hit_to_side, defeat, dive, swim…), posé dans `player.tscn` (`Modele`, échelle 1,9 : 0,92 m → ~1,75 m, la taille
  de la capsule ; il regarde vers +Z, le sens d'avance). Le Player trouve l'AnimationPlayer DANS le modèle ; les noms
  se règlent (`anim_idle` = `idle_001`, `anim_walk` = `walk_001`, `anim_run` = `run_001`, `anim_jump` = `saut`).
  **REMISES EN ÉTAT À L'IMPORT** (`tools/import/knil_animations.gd`, le script d'import du .glb) : les boucles
  (idle, walk, run, swagger) bouclées, coupées au plus près du début et FONDUES sur 0,15 s (`run_001` sautait de
  0,2 m aux pieds) ; hanches ramenées sur place (`run_001` courait 0,78 m DEVANT la capsule) ; `saut` = UN bond de
  `jump_001` (qui en fait cinq), 0,5 → 0,8 s, hanches tenues — la physique monte le corps, la pose du sommet tient
  jusqu'au sol. ⚠ Un nouvel export de Tripo : le recopier sous le MÊME nom (`knil.glb`), l'import refait tout.
  **LES PIEDS ET LE SOL** : la marche est animée à 0,91 m/s, la course à 3,09 m/s (mesuré, à l'échelle) ; la lecture
  suit la vitesse réelle (`anim_max_speed_scale` = 4 dans `player.tscn`) : avec `walk_speed` 3,5 et `run_speed` 7,
  la marche joue ×3,85 et la course ×2,27 — LES PIEDS NE GLISSENT PLUS (Jordan, 11 octobre 2026 : « scaler
  l'anim ? »). La cadence : marche ~3,2 pas/s (l'anim d'origine, 0,84, est très lente), course ~3,5 pas/s. Vu à l'image : attente, marche, course, saut (+1,44 m), retour à l'attente.
  **LES PROMPTS POUR TRIPO** (text to motion), s'il en faut d'autres : en ANGLAIS, < 60 mots, « A person … », la
  mécanique du corps SEULE (ni « gros », ni « arrogant », ni décor) — l'attitude se traduit en gestes (« chest pushed
  out, arms held away from the body » : le ventre de Knil se fait traverser par des bras le long du corps) ; ni boucle
  ni « sur place » ne se demandent (le modèle ne sait pas) : des pas droits à vitesse constante, l'import fait le reste.
- **LES PNJ** sont immobiles. Leurs routines (horaires, déplacements, foyers) se brancheront sur `GameClock` et
  le GameState, comme le reste.
- La collision en formes CONCAVES par tuile est la plus fidèle et la plus chère ; à mesurer sur le vrai monde.

- **TOUT LE GAMEPLAY DE KNIL EST À FAIRE** : combat (d'autres ENNEMIS, LA MORT de Knil — le genou, le pied, la boule et le
  dealer sont prêts, §3 ; les ennemis tués ne restent pas morts : à décider), objets et inventaire,
  coffres, donjons et clés, boutiques. Le GameState a déjà `player.health` (demi-cœurs), `max_health`, `money`, `items`.

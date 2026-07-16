## Directory structure

```text
.
└── luciemn-automatisation-environnement-securise/
    ├── README.md
    ├── mise_en_place_environnement_securise.sh
    └── montage_coffre/
        ├── aliases/
        │   └── evsh_aliases
        └── ssh/
            ├── config_ssh
            └── keys/
                ├── id_ed25519_projet
                └── id_ed25519_projet.pub
```

# automatisation-environnement-securise

## Objectif

Ce dépôt contient un script Bash d’administration Linux permettant de gérer un environnement sécurisé chiffré.

Le script permet de:

- mettre en place un coffre sécurisé de 5 Go
- ouvrir le coffre
- fermer le coffre
- gérer des clefs GPG
- préparer une configuration SSH
- créer un alias `evsh`
- importer une configuration SSH existante par `Host`

Le projet répond au sujet de partiel **Linux administration avancée**.

## Résultat attendu

Le coffre est construit selon cette chaîne:

~~~text
coffre.img
→ LUKS
→ /dev/mapper/sec_env
→ ext4
→ montage_coffre/
~~~

| Élément | Rôle |
|---|---|
| `coffre.img` | fichier conteneur de 5 Go |
| LUKS | chiffrement du coffre |
| `/dev/mapper/sec_env` | volume déchiffré temporaire |
| ext4 | système de fichiers utilisé dans le coffre |
| `montage_coffre/` | point de montage du coffre |

## Prérequis

Le script doit être lancé sur une machine Linux avec:

- Bash
- les droits `sudo`
- plus de 5 Go d’espace disponible
- `cryptsetup`
- `mkfs.ext4`
- `mount`
- `umount`
- `mountpoint`
- `gpg`
- `awk`
- `sed`
- `find`
- `cp`
- `ln`
- `truncate`

Vérification rapide:

~~~bash
command -v cryptsetup
command -v mkfs.ext4
command -v mount
command -v umount
command -v mountpoint
command -v gpg
command -v truncate
~~~

## Fichiers du dépôt

| Fichier | Rôle |
|---|---|
| `mise_en_place_environnement_securise.sh` | script principal du projet |
| `README.md` | documentation d’utilisation |
| `.gitignore` | fichier conseillé pour exclure le coffre, le montage et les secrets |

## Conventions du projet

| Élément | Valeur |
|---|---|
| Fichier conteneur | `coffre.img` |
| Taille du coffre | `5G` |
| Mapping LUKS | `sec_env` |
| Point de montage | `montage_coffre` |
| Script principal | `mise_en_place_environnement_securise.sh` |
| Alias SSH | `evsh` |

## Installation et lancement

Cloner le dépôt:

~~~bash
git clone "https://github.com/luciemn/automatisation-environnement-securise.git"
cd automatisation-environnement-securise
~~~

Rendre le script exécutable:

~~~bash
chmod +x mise_en_place_environnement_securise.sh
~~~

Vérifier la syntaxe:

~~~bash
bash -n mise_en_place_environnement_securise.sh
~~~

Lancer le script:

~~~bash
./mise_en_place_environnement_securise.sh
~~~

Le script affiche un menu interactif.

## Menu principal

~~~text
=== Environnement sécurisé ===
1) Installer l’environnement
2) Ouvrir l’environnement
3) Fermer l’environnement
4) Vérifier l’environnement
5) Cryptographie GPG
6) Configuration SSH
7) Quitter
~~~

## Partie I — Mise en place

L’option **Installer l’environnement** crée le coffre sécurisé.

Elle réalise les actions suivantes:

1. création du fichier `coffre.img` de 5 Go
2. application des permissions `600`
3. initialisation LUKS
4. ouverture du conteneur avec le mapping `sec_env`
5. formatage en ext4
6. montage dans `montage_coffre`
7. création de l’arborescence interne
8. application des permissions
9. fermeture propre du coffre

Commandes principales utilisées par le script:

~~~bash
truncate -s 5G coffre.img
chmod 600 coffre.img
sudo cryptsetup luksFormat coffre.img
sudo cryptsetup open coffre.img sec_env
sudo mkfs.ext4 /dev/mapper/sec_env
sudo mount /dev/mapper/sec_env montage_coffre
~~~

## Arborescence du coffre

Après installation, le coffre contient:

~~~text
montage_coffre/
├── gpg/
│   ├── public/
│   └── private/
├── ssh/
│   ├── config/
│   └── keys/
└── aliases/
~~~

| Dossier | Rôle |
|---|---|
| `gpg/public` | stockage des clefs publiques GPG exportées |
| `gpg/private` | stockage des clefs privées GPG exportées |
| `ssh/config_ssh` | fichier de configuration SSH |
| `ssh/keys` | clefs SSH importées |
| `aliases` | fichier d’alias contenant `evsh` |

## Partie II — Cryptographie GPG

Le menu GPG permet de:

~~~text
=== Cryptographie GPG ===
1) Créer une clef GPG et exporter la clef publique
2) Exporter une clef publique vers le coffre
3) Exporter une clef privée vers le coffre
4) Importer une clef publique depuis le coffre
5) Importer une clef privée depuis le coffre
6) Retour
~~~

### Création de clef GPG

Le script utilise:

~~~bash
gpg --full-generate-key
~~~

GPG demande directement les paramètres de la clef et la phrase secrète.

La phrase secrète n’est jamais stockée dans le script.

### Export de clef publique

Une clef publique est exportée dans:

~~~text
montage_coffre/gpg/public/
~~~

Commande utilisée:

~~~bash
gpg --export --armor <identifiant>
~~~

### Export de clef privée

Une clef privée est exportée dans:

~~~text
montage_coffre/gpg/private/
~~~

Commande utilisée:

~~~bash
gpg --export-secret-keys --armor <identifiant>
~~~

Le script demande une confirmation avant l’export privé.

## Partie III — Configuration SSH

Le menu SSH permet de:

~~~text
=== Configuration SSH ===
1) Créer un template SSH et l’alias evsh
2) Importer une configuration SSH existante par host
3) Retour
~~~

### Template SSH

Le fichier de configuration est créé ici:

~~~text
montage_coffre/ssh/config_ssh
~~~

Il peut être utilisé avec:

~~~bash
ssh -F montage_coffre/ssh/config_ssh exemple
~~~

### Alias `evsh`

Le script crée un fichier d’alias dans:

~~~text
montage_coffre/aliases/evsh_aliases
~~~

Il contient au minimum:

~~~bash
alias evsh="ssh -F montage_coffre/ssh/config_ssh"
~~~

Un lien symbolique est créé vers:

~~~text
~/.evsh_aliases
~~~

Pour utiliser l’alias:

~~~bash
source ~/.evsh_aliases
evsh exemple
~~~

### Import SSH par `Host`

Le script lit:

~~~text
$HOME/.ssh/config
~~~

Il liste les hôtes disponibles, par exemple:

~~~text
p1
p2
p3
~~~

Après le choix d’un hôte, le script:

1. importe le bloc `Host` correspondant dans le coffre
2. cherche la ligne `IdentityFile`
3. copie la clef privée SSH dans `ssh/keys`
4. copie la clef publique si elle existe
5. modifie `IdentityFile` pour pointer vers la clef stockée dans le coffre

## Partie IV — Utilisation

Le script permet directement:

| Besoin | Option du menu |
|---|---|
| installer l’environnement | `Installer l’environnement` |
| ouvrir l’environnement | `Ouvrir l’environnement` |
| fermer l’environnement | `Fermer l’environnement` |
| exporter des clefs GPG vers le coffre | `Cryptographie GPG` |
| importer des clefs GPG vers le trousseau | `Cryptographie GPG` |
| créer une configuration SSH | `Configuration SSH` |
| importer une configuration SSH existante | `Configuration SSH` |

## Validation

Vérifier que le coffre existe:

~~~bash
ls -lh coffre.img
~~~

Vérifier les permissions:

~~~bash
stat -c "%a %n" coffre.img
~~~

Résultat attendu:

~~~text
600 coffre.img
~~~

Vérifier que le fichier est bien un conteneur LUKS:

~~~bash
sudo cryptsetup isLuks coffre.img
~~~

Vérifier que le coffre est fermé:

~~~bash
mountpoint -q montage_coffre || echo "Coffre non monté"
test ! -e /dev/mapper/sec_env && echo "Mapping fermé"
~~~

## Permissions

| Élément | Permission | Raison |
|---|---|---|
| `coffre.img` | `600` | protéger le fichier conteneur |
| `montage_coffre/` | `700` | limiter l’accès au coffre monté |
| `gpg/private/` | `700` | protéger les exports de clefs privées |
| `ssh/keys/` | `700` | protéger les clefs SSH |
| clef privée GPG | `600` | limiter la lecture au propriétaire |
| clef privée SSH | `600` | respecter les attentes SSH |

## Points de vigilance

- ne jamais stocker la phrase secrète LUKS dans le script
- ne jamais stocker une phrase secrète GPG dans le script
- ne jamais versionner `coffre.img`
- ne jamais versionner `montage_coffre/`
- ne jamais versionner une clef privée
- ne jamais lancer `cryptsetup luksFormat` sur un disque réel
- ne pas relancer l’installation si le coffre existe déjà
- toujours fermer le coffre après utilisation

## `.gitignore` conseillé

~~~gitignore
coffre.img
montage_coffre/
*.asc
*.gpg
*.key
*.pem
.env
*.log
*.tmp
~~~

## Résumé

Ce projet fournit un script Bash simple et fonctionnel qui répond aux quatre parties du sujet:

- **mise en place**: coffre de 5 Go dans un fichier, LUKS, ext4
- **cryptographie**: création, export et import de clefs GPG
- **configuration**: template SSH, alias `evsh`, import par `Host`
- **utilisation**: menu pour installer, ouvrir et fermer l’environnement



FILE: mise_en_place_environnement_securise.sh

Voir la tâche dédiée au code final pour la version complète du script.

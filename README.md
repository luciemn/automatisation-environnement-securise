# automatisation-environnement-securise

## Objectif

Ce dépôt contient un script Bash qui met en place un environnement sécurisé dans un fichier conteneur de 5 Go. Le conteneur est chiffré avec LUKS, formaté en ext4, monté temporairement, puis préparé pour recevoir des éléments GPG, SSH et des alias.

## État actuel

Le script `mise_en_place_environnement_securise.sh` réalise uniquement la mise en place initiale du coffre. Il crée le conteneur, initialise LUKS, crée le système de fichiers ext4, prépare l’arborescence interne, puis démonte et ferme le coffre.

Les fonctions réutilisables d’ouverture, de fermeture, de gestion GPG, de configuration SSH et d’installation de l’alias `evsh` restent à développer.

## Prérequis

- une machine Linux ou une machine virtuelle Linux;
- un terminal;
- les droits `sudo`;
- plus de 5 Go d’espace disponible;
- les commandes `cryptsetup`, `mkfs.ext4`, `mount`, `umount`, `mkdir`, `chmod` et `truncate`.

Vérification rapide:

~~~bash
command -v cryptsetup
command -v mkfs.ext4
command -v mount
command -v umount
command -v mkdir
command -v chmod
command -v truncate
~~~

## Fichiers du dépôt

- `mise_en_place_environnement_securise.sh`: script de création du coffre;
- `README.md`: procédure et conventions du projet;
- `.gitignore`: exclusions des coffres, clefs, secrets, montages et fichiers temporaires.

## Conventions actuelles

| Élément | Valeur |
|---|---|
| Fichier conteneur | `coffre-luks.img` |
| Mapping LUKS | `coffre_luks` |
| Point de montage | `montage_coffre` |
| Script principal | `mise_en_place_environnement_securise.sh` |

Ces chemins sont relatifs au dossier du dépôt.

## Utilisation

Cloner le dépôt, entrer dans son dossier et vérifier le script:

~~~bash
git clone "https://github.com/luciemn/automatisation-environnement-securise.git"
cd automatisation-environnement-securise
chmod +x mise_en_place_environnement_securise.sh
bash -n mise_en_place_environnement_securise.sh
~~~

Vérifier ensuite l’espace disponible et l’absence d’un ancien conteneur:

~~~bash
df -h .
test ! -e coffre-luks.img
~~~

Lancer la mise en place:

~~~bash
./mise_en_place_environnement_securise.sh
~~~

Le script demande une confirmation et une phrase secrète pendant l’initialisation LUKS. La phrase secrète ne doit être enregistrée ni dans le script, ni dans le dépôt, ni dans les journaux.

## Arborescence créée dans le coffre

~~~text
gpg/
├── public/
└── private/
ssh/
├── config/
└── keys/
aliases/
~~~

Les dossiers `gpg/private` et `ssh/keys` reçoivent les permissions `700`. Le fichier conteneur reçoit les permissions `600`.

## Validation

Après l’exécution, vérifier le conteneur:

~~~bash
ls -lh coffre-luks.img
stat -c "%a %n" coffre-luks.img
sudo cryptsetup isLuks coffre-luks.img
mount | grep "montage_coffre" || true
ls -l "/dev/mapper/coffre_luks" || true
~~~

Résultats attendus:

- le fichier `coffre-luks.img` existe et affiche une taille de 5 Go;
- ses permissions sont `600`;
- `cryptsetup isLuks` reconnaît le conteneur;
- aucun montage `montage_coffre` ne reste actif;
- le mapping `/dev/mapper/coffre_luks` est fermé.

## Points de vigilance

- relire la cible avant chaque commande `cryptsetup luksFormat` ou `mkfs.ext4`;
- ne jamais remplacer le fichier conteneur par un disque ou une partition réelle;
- ne jamais stocker la phrase secrète LUKS dans Git;
- ne pas supprimer un conteneur existant sans vérifier son contenu;
- toujours démonter le système de fichiers avant de fermer le mapping LUKS.

## Limites actuelles

- le script refuse de continuer si `coffre-luks.img` existe déjà;
- il ne fournit pas encore de commandes dédiées pour ouvrir ou fermer un coffre existant;
- il ne gère pas encore les clefs GPG, les configurations SSH ou l’alias `evsh`;
- la gestion avancée des erreurs et le nettoyage automatique restent à ajouter.

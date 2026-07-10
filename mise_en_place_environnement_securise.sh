#!/usr/bin/env bash
set -euo pipefail

# Variables à confirmer.
COFFRE_FICHIER="coffre-luks.img"
COFFRE_MAPPING="coffre_luks"
COFFRE_MONTAGE="montage_coffre"

# Vérifications minimales avant création.
test -n "$COFFRE_FICHIER"
test -n "$COFFRE_MAPPING"
test -n "$COFFRE_MONTAGE"
test ! -e "$COFFRE_FICHIER"

# Créer le fichier conteneur de 5 Go.
truncate -s 5G "$COFFRE_FICHIER"
chmod 600 "$COFFRE_FICHIER"

# Initialiser LUKS.
echo "$COFFRE_FICHIER"
ls -lh "$COFFRE_FICHIER"
sudo cryptsetup luksFormat "$COFFRE_FICHIER"
sudo cryptsetup isLuks "$COFFRE_FICHIER"

# Ouvrir le coffre et créer ext4.
sudo cryptsetup open "$COFFRE_FICHIER" "$COFFRE_MAPPING"
ls -l "/dev/mapper/$COFFRE_MAPPING"
sudo mkfs.ext4 "/dev/mapper/$COFFRE_MAPPING"

# Monter temporairement.
sudo mkdir -p "$COFFRE_MONTAGE"
sudo mount "/dev/mapper/$COFFRE_MAPPING" "$COFFRE_MONTAGE"

# Créer l’arborescence minimale.
sudo mkdir -p "$COFFRE_MONTAGE/gpg/public"
sudo mkdir -p "$COFFRE_MONTAGE/gpg/private"
sudo mkdir -p "$COFFRE_MONTAGE/ssh/config"
sudo mkdir -p "$COFFRE_MONTAGE/ssh/keys"
sudo mkdir -p "$COFFRE_MONTAGE/aliases"

# Protéger les premiers dossiers sensibles.
sudo chmod 700 "$COFFRE_MONTAGE/gpg/private"
sudo chmod 700 "$COFFRE_MONTAGE/ssh/keys"

# Refermer proprement.
sudo umount "$COFFRE_MONTAGE"
sudo cryptsetup close "$COFFRE_MAPPING"

#!/usr/bin/env bash
set -euo pipefail

COFFRE_FICHIER="${COFFRE_FICHIER:-coffre.img}"
COFFRE_MAPPING="${COFFRE_MAPPING:-sec_env}"
COFFRE_MONTAGE="${COFFRE_MONTAGE:-montage_coffre}"
TAILLE_COFFRE="${TAILLE_COFFRE:-5G}"

ALIAS_FICHIER="${ALIAS_FICHIER:-$HOME/.evsh_aliases}"

DOSSIER_GPG_PUBLIC="gpg/public"
DOSSIER_GPG_PRIVATE="gpg/private"
DOSSIER_SSH_CONFIG="ssh/config"
DOSSIER_SSH_KEYS="ssh/keys"
DOSSIER_ALIAS="aliases"

GPG_PUBLIC="$COFFRE_MONTAGE/gpg/public"
GPG_PRIVATE="$COFFRE_MONTAGE/gpg/private"
SSH_CONFIG_DIR="$COFFRE_MONTAGE/ssh/config"
SSH_KEYS_DIR="$COFFRE_MONTAGE/ssh/keys"
ALIAS_DIR="$COFFRE_MONTAGE/aliases"
ALIAS_LINK="$HOME/.evsh_aliases"

info() {
    echo "[INFO] $1"
}

erreur() {
    echo "[ERREUR] $1" >&2
}

mapper() {
    echo "/dev/mapper/$COFFRE_MAPPING"
}

pause() {
    read -r -p "Appuyer sur Entrée pour continuer..."
}

verifier_commandes() {
    for commande in cryptsetup mkfs.ext4 mount umount mountpoint mkdir chmod chown truncate gpg awk sed find cp ln basename; do
        command -v "$commande" >/dev/null 2>&1 || {
            erreur "Commande manquante: $commande"
            return 1
        }
    done
}

installer() {
    verifier_commandes || return 1

    if [ -e "$COFFRE_FICHIER" ]; then
        erreur "Le fichier $COFFRE_FICHIER existe déjà"
        return 1
    fi

    info "Création du fichier conteneur de 5 Go"
    truncate -s "$TAILLE_COFFRE" "$COFFRE_FICHIER"
    chmod 600 "$COFFRE_FICHIER"

    info "Initialisation LUKS"
    sudo cryptsetup luksFormat "$COFFRE_FICHIER"

    info "Ouverture du coffre"
    sudo cryptsetup open "$COFFRE_FICHIER" "$COFFRE_MAPPING"

    info "Formatage ext4"
    sudo mkfs.ext4 "$(mapper)"

    info "Montage du coffre"
    sudo mkdir -p "$COFFRE_MONTAGE"
    sudo mount "$(mapper)" "$COFFRE_MONTAGE"

    info "Création des dossiers internes"
    sudo mkdir -p "$GPG_PUBLIC" "$GPG_PRIVATE" "$SSH_CONFIG_DIR" "$SSH_KEYS_DIR" "$ALIAS_DIR"

    sudo chown -R "$(id -u):$(id -g)" "$COFFRE_MONTAGE"

    chmod 600 "$COFFRE_FICHIER"
    chmod 700 "$COFFRE_MONTAGE"
    chmod 700 "$COFFRE_MONTAGE/gpg"
    chmod 755 "$GPG_PUBLIC"
    chmod 700 "$GPG_PRIVATE"
    chmod 700 "$COFFRE_MONTAGE/ssh"
    chmod 700 "$SSH_KEYS_DIR"
    chmod 700 "$ALIAS_DIR"

    fermer

    info "Installation terminée"
}

ouvrir() {
    verifier_commandes || return 1

    if [ ! -f "$COFFRE_FICHIER" ]; then
        erreur "Le coffre $COFFRE_FICHIER est introuvable"
        return 1
    fi

    if [ ! -e "$(mapper)" ]; then
        info "Ouverture du conteneur LUKS"
        sudo cryptsetup open "$COFFRE_FICHIER" "$COFFRE_MAPPING"
    fi

    sudo mkdir -p "$COFFRE_MONTAGE"

    if ! mountpoint -q "$COFFRE_MONTAGE"; then
        info "Montage du système de fichiers"
        sudo mount "$(mapper)" "$COFFRE_MONTAGE"
    fi

    info "Coffre ouvert dans $COFFRE_MONTAGE"
}

fermer() {
    if mountpoint -q "$COFFRE_MONTAGE"; then
        info "Démontage du coffre"
        sudo umount "$COFFRE_MONTAGE"
    fi

    if [ -e "$(mapper)" ]; then
        info "Fermeture du mapping LUKS"
        sudo cryptsetup close "$COFFRE_MAPPING"
    fi

    info "Coffre fermé"
}

verifier() {
    if [ ! -f "$COFFRE_FICHIER" ]; then
        erreur "Le coffre est introuvable"
        return 1
    fi

    ls -lh "$COFFRE_FICHIER"
    stat -c "%a %n" "$COFFRE_FICHIER"
    sudo cryptsetup isLuks "$COFFRE_FICHIER"

    ouvrir || return 1

    find "$COFFRE_MONTAGE" -maxdepth 3 -type d | sort
    stat -c "%a %n" "$GPG_PRIVATE" "$SSH_KEYS_DIR"

    fermer
}

generer_gpg() {
    verifier_commandes || return 1

    gpg --full-generate-key

    read -r -p "Identifiant de la clef à exporter publiquement dans le coffre: " identifiant

    if [ -n "$identifiant" ]; then
        export_gpg_public "$identifiant"
    fi
}

export_gpg_public() {
    identifiant="$1"

    if [ -z "$identifiant" ]; then
        erreur "Identifiant vide"
        return 1
    fi

    ouvrir || return 1

    gpg --export --armor "$identifiant" > "$GPG_PUBLIC/$identifiant.asc"
    chmod 644 "$GPG_PUBLIC/$identifiant.asc"

    info "Clef publique exportée dans $GPG_PUBLIC/$identifiant.asc"
}

export_gpg_prive() {
    identifiant="$1"

    if [ -z "$identifiant" ]; then
        erreur "Identifiant vide"
        return 1
    fi

    ouvrir || return 1

    echo "Attention: une clef privée est sensible."
    read -r -p "Exporter la clef privée ? Écrire OUI: " confirmation

    if [ "$confirmation" != "OUI" ]; then
        erreur "Export privé annulé"
        return 1
    fi

    gpg --export-secret-keys --armor "$identifiant" > "$GPG_PRIVATE/$identifiant-private.asc"
    chmod 600 "$GPG_PRIVATE/$identifiant-private.asc"

    info "Clef privée exportée dans $GPG_PRIVATE/$identifiant-private.asc"
}

import_gpg_public() {
    ouvrir || return 1

    read -r -p "Nom du fichier public dans gpg/public: " fichier

    if [ -f "$GPG_PUBLIC/$fichier" ]; then
        gpg --import "$GPG_PUBLIC/$fichier"
        info "Clef publique importée dans le trousseau"
    else
        erreur "Fichier introuvable"
    fi
}

import_gpg_prive() {
    ouvrir || return 1

    read -r -p "Nom du fichier privé dans gpg/private: " fichier

    if [ -f "$GPG_PRIVATE/$fichier" ]; then
        echo "Attention: import d’une clef privée."
        read -r -p "Confirmer avec OUI: " confirmation

        if [ "$confirmation" = "OUI" ]; then
            gpg --import "$GPG_PRIVATE/$fichier"
            info "Clef privée importée dans le trousseau"
        else
            erreur "Import annulé"
        fi
    else
        erreur "Fichier introuvable"
    fi
}

creer_config_ssh() {
    ouvrir || return 1

    config="$SSH_CONFIG_DIR/config"
    alias_file="$ALIAS_DIR/evsh_aliases"

    printf '%s\n' \
        'Host exemple' \
        '    HostName 192.0.2.10' \
        '    User utilisateur' \
        "    IdentityFile $SSH_KEYS_DIR/id_exemple" \
        '    IdentitiesOnly yes' \
        > "$config"

    chmod 600 "$config"

    printf 'alias evsh="ssh -F %s"\n' "$config" > "$alias_file"
    chmod 600 "$alias_file"

    ln -sf "$alias_file" "$ALIAS_LINK"

    info "Template SSH créé dans $config"
    info "Alias créé. À charger avec: source $ALIAS_LINK"
}

import_ssh() {
    ouvrir || return 1

    fichier_config="$HOME/.ssh/config"

    if [ ! -f "$fichier_config" ]; then
        erreur "Le fichier $fichier_config est introuvable"
        return 1
    fi

    echo "Hosts disponibles:"
    awk '/^[[:space:]]*Host[[:space:]]+/ { for (i=2; i<=NF; i++) print " - " $i }' "$fichier_config"

    read -r -p "Host à importer: " hote

    if [ -z "$hote" ]; then
        erreur "Host vide"
        return 1
    fi

    bloc="$(awk -v host="$hote" '
        /^[[:space:]]*Host[[:space:]]+/ {
            capture=0
            for (i=2; i<=NF; i++) {
                if ($i == host) {
                    capture=1
                }
            }
        }
        capture {
            print
        }
    ' "$fichier_config")"

    if [ -z "$bloc" ]; then
        erreur "Host introuvable"
        return 1
    fi

    identity="$(printf '%s\n' "$bloc" | awk 'tolower($1)=="identityfile" {print $2; exit}')"
    identity="${identity/#\~/$HOME}"

    if [ -n "$identity" ] && [ -f "$identity" ]; then
        cp "$identity" "$SSH_KEYS_DIR/"
        chmod 600 "$SSH_KEYS_DIR/$(basename "$identity")"

        if [ -f "$identity.pub" ]; then
            cp "$identity.pub" "$SSH_KEYS_DIR/"
            chmod 644 "$SSH_KEYS_DIR/$(basename "$identity").pub"
        fi

        bloc="$(printf '%s\n' "$bloc" | sed "s#^[[:space:]]*IdentityFile[[:space:]].*#    IdentityFile $SSH_KEYS_DIR/$(basename "$identity")#I")"
    fi

    printf '\n%s\n' "$bloc" >> "$SSH_CONFIG_DIR/config"
    chmod 600 "$SSH_CONFIG_DIR/config"

    info "Configuration SSH importée pour $hote"
}

menu_gpg() {
    while true; do
        echo
        echo "Cryptographie GPG"
        echo "1) Créer une clef GPG et exporter la clef publique"
        echo "2) Exporter une clef publique vers le coffre"
        echo "3) Exporter une clef privée vers le coffre"
        echo "4) Importer une clef publique depuis le coffre"
        echo "5) Importer une clef privée depuis le coffre"
        echo "6) Retour"

        read -r -p "Choix: " choix

        case "$choix" in
            1)
                generer_gpg
                pause
                ;;
            2)
                read -r -p "Identifiant de la clef publique: " identifiant
                export_gpg_public "$identifiant"
                pause
                ;;
            3)
                read -r -p "Identifiant de la clef privée: " identifiant
                export_gpg_prive "$identifiant"
                pause
                ;;
            4)
                import_gpg_public
                pause
                ;;
            5)
                import_gpg_prive
                pause
                ;;
            6)
                return
                ;;
            *)
                echo "Choix invalide"
                ;;
        esac
    done
}

menu_ssh() {
    while true; do
        echo
        echo " Configuration SSH"
        echo "1) Créer un template SSH et l’alias evsh"
        echo "2) Importer une configuration SSH existante par host"
        echo "3) Retour"

        read -r -p "Choix: " choix

        case "$choix" in
            1)
                creer_config_ssh
                pause
                ;;
            2)
                import_ssh
                pause
                ;;
            3)
                return
                ;;
            *)
                echo "Choix invalide"
                ;;
        esac
    done
}

menu_principal() {
    while true; do
        echo
        echo "Environnement sécurisé"
        echo "1) Installer l’environnement"
        echo "2) Ouvrir l’environnement"
        echo "3) Fermer l’environnement"
        echo "4) Vérifier l’environnement"
        echo "5) Cryptographie GPG"
        echo "6) Configuration SSH"
        echo "7) Quitter"

        read -r -p "Choix: " choix

        case "$choix" in
            1)
                installer
                pause
                ;;
            2)
                ouvrir
                pause
                ;;
            3)
                fermer
                pause
                ;;
            4)
                verifier
                pause
                ;;
            5)
                menu_gpg
                ;;
            6)
                menu_ssh
                ;;
            7)
                exit 0
                ;;
            *)
                echo "Choix invalide"
                ;;
        esac
    done
}

menu_principal

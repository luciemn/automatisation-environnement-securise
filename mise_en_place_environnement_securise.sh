#!/usr/bin/env bash
set -Eeuo pipefail


SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

COFFRE_FICHIER="coffre-luks.img"
COFFRE_MAPPING="coffre_luks"
COFFRE_MONTAGE="montage_coffre"
TAILLE_COFFRE="5G"

info() {
    printf '[INFO] %s\n' "$*"
}

succes() {
    printf '[OK] %s\n' "$*"
}

erreur() {
    printf '[ERREUR] %s\n' "$*" >&2
}

mapping_present() {
    test -e "/dev/mapper/$COFFRE_MAPPING"
}

montage_actif() {
    mountpoint -q "$COFFRE_MONTAGE"
}

verifier_commandes() {
    local commande
    local -a commandes=(
        bash sudo cryptsetup mkfs.ext4 mount umount mountpoint
        mkdir chmod truncate df tail stat find dirname
    )

    for commande in "${commandes[@]}"; do
        if command -v "$commande" >/dev/null 2>&1; then
            continue
        else
            erreur "Commande manquante: $commande"
            return 1
        fi
    done

    succes "Toutes les commandes nécessaires sont disponibles."
}

verifier_espace_disponible() {
    local espace_disponible

    espace_disponible="$(df --output=avail -k . | tail -n 1)"

    if (( espace_disponible < 5 * 1024 * 1024 )); then
        erreur "Moins de 5 Gio sont disponibles dans le dossier du projet."
        return 1
    fi

    succes "L’espace disponible est suffisant."
}

verifier_conteneur_luks() {
    if test -f "$COFFRE_FICHIER"; then
        info "Le fichier conteneur existe."
    else
        erreur "Le conteneur $COFFRE_FICHIER est introuvable."
        return 1
    fi

    if sudo cryptsetup isLuks "$COFFRE_FICHIER"; then
        succes "Le conteneur LUKS est valide."
    else
        erreur "$COFFRE_FICHIER n’est pas un conteneur LUKS valide."
        return 1
    fi
}

verifier_arborescence() {
    local dossier
    local permission
    local -a dossiers=(
        gpg/public
        gpg/private
        ssh/config
        ssh/keys
        aliases
    )

    if montage_actif; then
        info "Le coffre est monté; vérification de l’arborescence."
    else
        erreur "Le coffre doit être monté pour vérifier son arborescence."
        return 1
    fi

    for dossier in "${dossiers[@]}"; do
        if sudo test -d "$COFFRE_MONTAGE/$dossier"; then
            continue
        else
            erreur "Dossier manquant dans le coffre: $dossier"
            return 1
        fi
    done

    permission="$(sudo stat -c '%a' "$COFFRE_MONTAGE/gpg/private")"
    if [[ "$permission" == "700" ]]; then
        info "Les permissions de gpg/private sont correctes."
    else
        erreur "Permission inattendue pour gpg/private: $permission"
        return 1
    fi

    permission="$(sudo stat -c '%a' "$COFFRE_MONTAGE/ssh/keys")"
    if [[ "$permission" == "700" ]]; then
        info "Les permissions de ssh/keys sont correctes."
    else
        erreur "Permission inattendue pour ssh/keys: $permission"
        return 1
    fi

    succes "L’arborescence et les permissions internes sont valides."
}

nettoyer_etat_partiel() {
    info "Nettoyage de l’état partiel."

    if montage_actif; then
        if sudo umount "$COFFRE_MONTAGE"; then
            succes "Le montage partiel est démonté."
        else
            erreur "Le nettoyage n’a pas pu démonter $COFFRE_MONTAGE."
            return 1
        fi
    fi

    if mapping_present; then
        if sudo cryptsetup close "$COFFRE_MAPPING"; then
            succes "Le mapping partiel est fermé."
        else
            erreur "Le nettoyage n’a pas pu fermer $COFFRE_MAPPING."
            return 1
        fi
    fi
}

installer_coffre() {
    info "Vérification avant installation."

    if test -e "$COFFRE_FICHIER"; then
        if sudo cryptsetup isLuks "$COFFRE_FICHIER"; then
            info "Le coffre existe déjà. Aucune réinstallation n’est effectuée."
            return 0
        fi

        erreur "$COFFRE_FICHIER existe mais n’est pas un conteneur LUKS valide."
        erreur "Le fichier n’est ni supprimé ni écrasé."
        return 1
    fi

    if verifier_espace_disponible; then
        info "La création du conteneur peut commencer."
    else
        return 1
    fi

    info "Création du conteneur de $TAILLE_COFFRE."
    if truncate -s "$TAILLE_COFFRE" "$COFFRE_FICHIER"; then
        succes "Le fichier conteneur est créé."
    else
        erreur "Impossible de créer le fichier conteneur."
        return 1
    fi

    if chmod 600 "$COFFRE_FICHIER"; then
        succes "Les permissions 600 sont appliquées au conteneur."
    else
        erreur "Impossible d’appliquer les permissions au conteneur."
        return 1
    fi

    if [[ "$(stat -c '%a' "$COFFRE_FICHIER")" == "600" ]]; then
        succes "Les permissions du conteneur sont confirmées."
    else
        erreur "Les permissions du conteneur ne sont pas 600."
        return 1
    fi

    info "Initialisation LUKS de $COFFRE_FICHIER."
    if sudo cryptsetup luksFormat "$COFFRE_FICHIER"; then
        succes "L’initialisation LUKS est terminée."
    else
        erreur "Échec de l’initialisation LUKS."
        return 1
    fi

    if verifier_conteneur_luks; then
        info "Le conteneur peut être ouvert."
    else
        return 1
    fi

    info "Ouverture temporaire du mapping $COFFRE_MAPPING."
    if sudo cryptsetup open "$COFFRE_FICHIER" "$COFFRE_MAPPING"; then
        succes "Le mapping temporaire est ouvert."
    else
        erreur "Échec de l’ouverture LUKS."
        return 1
    fi

    info "Création du système de fichiers ext4."
    if sudo mkfs.ext4 "/dev/mapper/$COFFRE_MAPPING"; then
        succes "Le système de fichiers ext4 est créé."
    else
        erreur "Échec de la création du système de fichiers ext4."
        nettoyer_etat_partiel
        return 1
    fi

    if sudo mkdir -p "$COFFRE_MONTAGE"; then
        info "Le point de montage est prêt."
    else
        erreur "Impossible de créer le point de montage."
        nettoyer_etat_partiel
        return 1
    fi

    if sudo mount "/dev/mapper/$COFFRE_MAPPING" "$COFFRE_MONTAGE"; then
        succes "Le coffre est monté temporairement."
    else
        erreur "Échec du montage du coffre."
        nettoyer_etat_partiel
        return 1
    fi

    info "Création de l’arborescence interne."
    if sudo mkdir -p \
        "$COFFRE_MONTAGE/gpg/public" \
        "$COFFRE_MONTAGE/gpg/private" \
        "$COFFRE_MONTAGE/ssh/config" \
        "$COFFRE_MONTAGE/ssh/keys" \
        "$COFFRE_MONTAGE/aliases"; then
        succes "L’arborescence interne est créée."
    else
        erreur "Échec de la création de l’arborescence."
        nettoyer_etat_partiel
        return 1
    fi

    if sudo chmod 700 \
        "$COFFRE_MONTAGE/gpg/private" \
        "$COFFRE_MONTAGE/ssh/keys"; then
        succes "Les permissions internes sont appliquées."
    else
        erreur "Échec de l’application des permissions internes."
        nettoyer_etat_partiel
        return 1
    fi

    if verifier_arborescence; then
        info "La structure interne est validée."
    else
        nettoyer_etat_partiel
        return 1
    fi

    if sudo umount "$COFFRE_MONTAGE"; then
        succes "Le coffre est démonté après l’installation."
    else
        erreur "Le coffre n’a pas pu être démonté après l’installation."
        return 1
    fi

    if sudo cryptsetup close "$COFFRE_MAPPING"; then
        succes "Le mapping LUKS est fermé après l’installation."
    else
        erreur "Le mapping LUKS n’a pas pu être fermé après l’installation."
        return 1
    fi

    if montage_actif || mapping_present; then
        erreur "L’installation est terminée, mais le coffre n’est pas complètement fermé."
        return 1
    fi

    succes "Installation terminée: le coffre est démonté et fermé."
}

ouvrir_coffre() {
    local mapping_cree=0

    if verifier_conteneur_luks; then
        info "Le conteneur est prêt à être ouvert."
    else
        return 1
    fi

    if montage_actif; then
        if mapping_present; then
            info "Le coffre est déjà ouvert et monté."
            return 0
        else
            erreur "État incohérent: le point est monté sans mapping $COFFRE_MAPPING."
            return 1
        fi
    fi

    if mapping_present; then
        info "Le mapping existe déjà; tentative de montage uniquement."
    else
        info "Ouverture du mapping LUKS."
        if sudo cryptsetup open "$COFFRE_FICHIER" "$COFFRE_MAPPING"; then
            mapping_cree=1
            succes "Le mapping LUKS est ouvert."
        else
            erreur "Impossible d’ouvrir le coffre."
            return 1
        fi
    fi

    if sudo mkdir -p "$COFFRE_MONTAGE"; then
        info "Le point de montage est prêt."
    else
        erreur "Impossible de créer le point de montage."
        if (( mapping_cree == 1 )); then
            sudo cryptsetup close "$COFFRE_MAPPING"
        fi
        return 1
    fi

    if sudo mount "/dev/mapper/$COFFRE_MAPPING" "$COFFRE_MONTAGE"; then
        succes "Le coffre est monté."
    else
        erreur "Impossible de monter le coffre."
        if (( mapping_cree == 1 )); then
            info "Fermeture du mapping créé par cette action."
            sudo cryptsetup close "$COFFRE_MAPPING"
        fi
        return 1
    fi

    if mapping_present && montage_actif; then
        succes "L’état ouvert est confirmé."
    else
        erreur "L’état ouvert n’a pas pu être confirmé."
        nettoyer_etat_partiel
        return 1
    fi

    if verifier_arborescence; then
        succes "Le coffre est ouvert sur $COFFRE_MONTAGE."
    else
        nettoyer_etat_partiel
        return 1
    fi
}

fermer_coffre() {
    if montage_actif || mapping_present; then
        info "Fermeture du coffre en cours."
    else
        info "Le coffre est déjà fermé."
        return 0
    fi

    if montage_actif; then
        info "Démontage de $COFFRE_MONTAGE."
        if sudo umount "$COFFRE_MONTAGE"; then
            succes "Le coffre est démonté."
        else
            erreur "Le démontage a échoué. Le mapping reste ouvert par sécurité."
            return 1
        fi
    fi

    if mapping_present; then
        info "Fermeture du mapping $COFFRE_MAPPING."
        if sudo cryptsetup close "$COFFRE_MAPPING"; then
            succes "Le mapping LUKS est fermé."
        else
            erreur "La fermeture du mapping LUKS a échoué."
            return 1
        fi
    fi

    if montage_actif || mapping_present; then
        erreur "L’état fermé n’a pas pu être confirmé."
        return 1
    else
        succes "Le coffre est démonté et fermé."
    fi
}

afficher_etat() {
    printf '\n--- État du coffre ---\n'

    if test -f "$COFFRE_FICHIER"; then
        printf 'Conteneur : présent\n'
        printf 'Permissions : %s\n' "$(stat -c '%a' "$COFFRE_FICHIER")"

        if sudo cryptsetup isLuks "$COFFRE_FICHIER"; then
            printf 'LUKS : valide\n'
        else
            printf 'LUKS : invalide\n'
        fi
    else
        printf 'Conteneur : absent\n'
    fi

    if mapping_present; then
        printf 'Mapping : présent\n'
    else
        printf 'Mapping : absent\n'
    fi

    if montage_actif; then
        printf 'Montage : actif sur %s\n' "$COFFRE_MONTAGE"
    else
        printf 'Montage : inactif\n'
    fi

    printf '%s\n\n' '-----------------------'
}

menu_principal() {
    local choix

    while true; do
        printf '\n=== Coffre sécurisé ===\n'
        printf '1) Installer\n'
        printf '2) Ouvrir\n'
        printf '3) Fermer\n'
        printf '4) Quitter\n'

        if read -r -p 'Choix: ' choix; then
            info "Choix reçu."
        else
            printf '\n'
            info "Fin de l’entrée; arrêt du script."
            return 0
        fi

        case "$choix" in
            1)
                if installer_coffre; then
                    afficher_etat
                else
                    erreur "L’installation a échoué."
                fi
                ;;
            2)
                if ouvrir_coffre; then
                    afficher_etat
                else
                    erreur "L’ouverture a échoué."
                fi
                ;;
            3)
                if fermer_coffre; then
                    afficher_etat
                else
                    erreur "La fermeture a échoué."
                fi
                ;;
            4)
                info "Arrêt sans autre opération."
                return 0
                ;;
            *)
                erreur "Choix invalide. Saisir 1, 2, 3 ou 4."
                ;;
        esac
    done
}

main() {
    if verifier_commandes; then
        menu_principal
    else
        erreur "Le script ne peut pas démarrer."
        exit 1
    fi
}

main "$@"

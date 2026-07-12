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
        mkdir chmod chown truncate df tail stat find dirname sort awk gpg id
    )

    for commande in "${commandes[@]}"; do
        if command -v "$commande" >/dev/null 2>&1; then
            info "Commande disponible: $commande"
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

    if (( espace_disponible >= 5 * 1024 * 1024 )); then
        succes "L’espace disponible est suffisant."
    else
        erreur "Moins de 5 Gio sont disponibles dans le dossier du projet."
        return 1
    fi
}

verifier_conteneur_luks() {
    if test -f "$COFFRE_FICHIER"; then
        if sudo cryptsetup isLuks "$COFFRE_FICHIER"; then
            succes "Le conteneur LUKS est valide."
        else
            erreur "$COFFRE_FICHIER n’est pas un conteneur LUKS valide."
            return 1
        fi
    else
        erreur "Le conteneur $COFFRE_FICHIER est introuvable."
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
        info "Le coffre est monté."
    else
        erreur "Le coffre doit être monté pour vérifier son arborescence."
        return 1
    fi

    for dossier in "${dossiers[@]}"; do
        if sudo test -d "$COFFRE_MONTAGE/$dossier"; then
            info "Dossier présent: $dossier"
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
}

nettoyer_etat_partiel() {
    if montage_actif; then
        if sudo umount "$COFFRE_MONTAGE"; then
            succes "Le montage partiel est démonté."
        else
            erreur "Le montage partiel n’a pas pu être démonté."
            return 1
        fi
    else
        info "Aucun montage partiel à démonter."
    fi

    if mapping_present; then
        if sudo cryptsetup close "$COFFRE_MAPPING"; then
            succes "Le mapping partiel est fermé."
        else
            erreur "Le mapping partiel n’a pas pu être fermé."
            return 1
        fi
    else
        info "Aucun mapping partiel à fermer."
    fi
}

installer_coffre() {
    if test -e "$COFFRE_FICHIER"; then
        if sudo cryptsetup isLuks "$COFFRE_FICHIER"; then
            info "Le coffre existe déjà. Aucune réinstallation n’est effectuée."
            return 0
        fi

        erreur "$COFFRE_FICHIER existe mais n’est pas un conteneur LUKS valide."
        return 1
    fi

    if verifier_espace_disponible; then
        info "La création du conteneur peut commencer."
    else
        return 1
    fi

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

    if sudo cryptsetup open "$COFFRE_FICHIER" "$COFFRE_MAPPING"; then
        succes "Le mapping LUKS est ouvert."
    else
        erreur "Échec de l’ouverture LUKS."
        return 1
    fi

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

    sudo mkdir -p \
        "$COFFRE_MONTAGE/gpg/public" \
        "$COFFRE_MONTAGE/gpg/private" \
        "$COFFRE_MONTAGE/ssh/config" \
        "$COFFRE_MONTAGE/ssh/keys" \
        "$COFFRE_MONTAGE/aliases"

    # Les fonctions GPG s’exécutent avec l’utilisateur courant, pas avec sudo.
    sudo chown -R "$(id -u):$(id -g)" "$COFFRE_MONTAGE/gpg"
    chmod 700 "$COFFRE_MONTAGE/gpg" "$COFFRE_MONTAGE/gpg/private"
    chmod 755 "$COFFRE_MONTAGE/gpg/public"

    sudo chmod 700 "$COFFRE_MONTAGE/ssh/keys"

    verifier_arborescence
    sudo umount "$COFFRE_MONTAGE"
    sudo cryptsetup close "$COFFRE_MAPPING"
    succes "Installation terminée: le coffre est démonté et fermé."
}

ouvrir_coffre() {
    local mapping_cree=0

    if verifier_conteneur_luks; then
        info "Le conteneur peut être utilisé."
    else
        return 1
    fi

    if montage_actif; then
        if mapping_present; then
            info "Le coffre est déjà ouvert et monté."
            return 0
        else
            erreur "État incohérent: montage actif sans mapping $COFFRE_MAPPING."
            return 1
        fi
    else
        info "Le point de montage n’est pas actif."
    fi

    if mapping_present; then
        info "Le mapping existe déjà. Seul le montage sera effectué."
    else
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
        return 1
    fi

    if sudo mount "/dev/mapper/$COFFRE_MAPPING" "$COFFRE_MONTAGE"; then
        succes "Le coffre est monté."
    else
        erreur "Impossible de monter le coffre."
        if (( mapping_cree == 1 )); then
            sudo cryptsetup close "$COFFRE_MAPPING"
        else
            info "Le mapping existait avant cette action."
        fi
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
    if montage_actif; then
        if sudo umount "$COFFRE_MONTAGE"; then
            succes "Le coffre est démonté."
        else
            erreur "Le démontage a échoué. Le mapping reste ouvert."
            return 1
        fi
    else
        info "Le coffre est déjà démonté."
    fi

    if mapping_present; then
        if sudo cryptsetup close "$COFFRE_MAPPING"; then
            succes "Le mapping LUKS est fermé."
        else
            erreur "La fermeture du mapping LUKS a échoué."
            return 1
        fi
    else
        info "Le mapping LUKS est déjà fermé."
    fi
}

verifier_coffre_gpg() {
    if mapping_present; then
        if montage_actif; then
            info "Le coffre est ouvert et monté."
        else
            erreur "Le mapping existe, mais le coffre n’est pas monté."
            return 1
        fi
    else
        erreur "Le mapping LUKS est absent."
        return 1
    fi

    if test -d "$COFFRE_MONTAGE/gpg/public"; then
        info "Le dossier gpg/public est accessible."
    else
        erreur "Le dossier gpg/public est absent ou inaccessible."
        return 1
    fi

    if test -d "$COFFRE_MONTAGE/gpg/private"; then
        info "Le dossier gpg/private est accessible."
    else
        erreur "Le dossier gpg/private est absent ou inaccessible."
        return 1
    fi

    if [[ "$(stat -c '%a' "$COFFRE_MONTAGE/gpg/private")" == "700" ]]; then
        info "Les permissions de gpg/private sont correctes."
    else
        erreur "Le dossier gpg/private doit avoir les permissions 700."
        return 1
    fi

    if test -w "$COFFRE_MONTAGE/gpg/public"; then
        if test -w "$COFFRE_MONTAGE/gpg/private"; then
            succes "Les dossiers GPG sont accessibles en écriture."
        else
            erreur "Le dossier gpg/private n’est pas accessible en écriture."
            return 1
        fi
    else
        erreur "Le dossier gpg/public n’est pas accessible en écriture."
        return 1
    fi
}

empreinte_publique() {
    local identifiant="$1"
    gpg --batch --with-colons --list-keys "$identifiant" 2>/dev/null \
        | awk -F: '$1 == "fpr" { print $10; exit }'
}

empreinte_secrete() {
    local identifiant="$1"
    gpg --batch --with-colons --list-secret-keys "$identifiant" 2>/dev/null \
        | awk -F: '$1 == "fpr" { print $10; exit }'
}

generer_clef_gpg() {
    info "GnuPG va demander les paramètres et la phrase secrète de la nouvelle clef."

    if gpg --full-generate-key; then
        succes "La génération GPG est terminée."
        gpg --list-secret-keys --keyid-format LONG --fingerprint
    else
        erreur "La génération GPG a échoué ou a été annulée."
        return 1
    fi
}

exporter_clef_publique() {
    local identifiant
    local empreinte
    local destination

    if verifier_coffre_gpg; then
        info "Le coffre peut recevoir l’export public."
    else
        return 1
    fi

    read -r -p 'Identifiant ou empreinte de la clef publique: ' identifiant
    if test -n "$identifiant"; then
        info "Identifiant reçu."
    else
        erreur "Identifiant vide."
        return 1
    fi

    empreinte="$(empreinte_publique "$identifiant")"
    if test -n "$empreinte"; then
        info "Empreinte trouvée: $empreinte"
    else
        erreur "Aucune clef publique n’a été trouvée."
        return 1
    fi

    destination="$COFFRE_MONTAGE/gpg/public/$empreinte.asc"
    if test -e "$destination"; then
        erreur "Le fichier existe déjà: $destination"
        return 1
    fi

    if gpg --armor --output "$destination" --export "$empreinte"; then
        chmod 644 "$destination"
    else
        erreur "L’export de la clef publique a échoué."
        return 1
    fi

    if test -s "$destination"; then
        succes "Clef publique exportée vers $destination."
    else
        erreur "Le fichier exporté est vide."
        return 1
    fi
}

exporter_clef_privee() {
    local identifiant
    local confirmation
    local empreinte
    local destination

    if verifier_coffre_gpg; then
        info "Le coffre peut recevoir l’export privé."
    else
        return 1
    fi

    printf '%s\n' 'Attention: une clef privée permet d’usurper son propriétaire si elle est compromise.'
    read -r -p 'Confirmer l’export privé en saisissant EXPORTER: ' confirmation
    if [[ "$confirmation" == "EXPORTER" ]]; then
        info "Export privé confirmé."
    else
        info "Export privé annulé."
        return 0
    fi

    read -r -p 'Identifiant ou empreinte de la clef secrète: ' identifiant
    if test -n "$identifiant"; then
        info "Identifiant reçu."
    else
        erreur "Identifiant vide."
        return 1
    fi

    empreinte="$(empreinte_secrete "$identifiant")"
    if test -n "$empreinte"; then
        info "Empreinte secrète trouvée."
    else
        erreur "Aucune clef secrète n’a été trouvée."
        return 1
    fi

    destination="$COFFRE_MONTAGE/gpg/private/$empreinte-secret.asc"
    if test -e "$destination"; then
        erreur "Le fichier existe déjà: $destination"
        return 1
    fi

    if (
        umask 077
        gpg --armor --output "$destination" --export-secret-keys "$empreinte"
    ); then
        chmod 600 "$destination"
    else
        erreur "L’export de la clef privée a échoué."
        return 1
    fi

    if test -s "$destination"; then
        succes "Clef privée exportée vers $destination avec les permissions 600."
    else
        erreur "Le fichier privé exporté est vide."
        return 1
    fi
}

selectionner_fichier_gpg() {
    local dossier="$1"
    local invite="$2"
    local -a fichiers=()
    local choix

    mapfile -t fichiers < <(
        find "$dossier" -maxdepth 1 -type f \
            \( -name '*.asc' -o -name '*.gpg' \) -print | sort
    )

    if (( ${#fichiers[@]} > 0 )); then
        printf '%s\n' "$invite" >&2
    else
        erreur "Aucun fichier .asc ou .gpg dans $dossier."
        return 1
    fi
    select choix in "${fichiers[@]}" 'Annuler'; do
        if [[ "$choix" == "Annuler" ]]; then
            return 1
        fi

        if test -n "${choix:-}"; then
            printf '%s\n' "$choix"
            return 0
        fi

        erreur "Sélection invalide."
    done
}

importer_clef_publique() {
    local fichier

    if verifier_coffre_gpg; then
        info "Le coffre peut fournir une clef publique."
    else
        return 1
    fi

    if fichier="$(selectionner_fichier_gpg \
        "$COFFRE_MONTAGE/gpg/public" \
        'Choisir une clef publique à importer:')"; then
        if gpg --import "$fichier"; then
            succes "La clef publique est importée."
            gpg --list-keys --keyid-format LONG --fingerprint
        else
            erreur "L’import de la clef publique a échoué."
            return 1
        fi
    else
        info "Aucune clef publique n’a été sélectionnée."
    fi
}

importer_clef_privee() {
    local fichier
    local confirmation

    if verifier_coffre_gpg; then
        info "Le coffre peut fournir une clef privée."
    else
        return 1
    fi

    printf '%s\n' 'Attention: importer une clef privée donne accès aux opérations de signature et de déchiffrement associées.'
    read -r -p 'Confirmer l’import privé en saisissant IMPORTER: ' confirmation
    if [[ "$confirmation" == "IMPORTER" ]]; then
        info "Import privé confirmé."
    else
        info "Import privé annulé."
        return 0
    fi

    if fichier="$(selectionner_fichier_gpg \
        "$COFFRE_MONTAGE/gpg/private" \
        'Choisir une clef privée à importer:')"; then
        if gpg --import "$fichier"; then
            succes "La clef privée est importée."
            gpg --list-secret-keys --keyid-format LONG --fingerprint
        else
            erreur "L’import de la clef privée a échoué."
            return 1
        fi
    else
        info "Aucune clef privée n’a été sélectionnée."
    fi
}

menu_gpg() {
    local choix

    while true; do
        printf '\n=== Gestion GPG ===\n'
        printf '1) Générer une paire de clefs\n'
        printf '2) Exporter une clef publique vers le coffre\n'
        printf '3) Exporter une clef privée vers le coffre\n'
        printf '4) Importer une clef publique depuis le coffre\n'
        printf '5) Importer une clef privée depuis le coffre\n'
        printf '6) Retour\n'

        if read -r -p 'Choix GPG: ' choix; then
            case "$choix" in
                1) generer_clef_gpg ;;
                2) exporter_clef_publique ;;
                3) exporter_clef_privee ;;
                4) importer_clef_publique ;;
                5) importer_clef_privee ;;
                6) return 0 ;;
                *) erreur "Choix invalide. Saisir un nombre de 1 à 6." ;;
            esac
        else
            info "Fin de l’entrée. Retour au menu principal."
            return 0
        fi
    done
}

afficher_etat() {
    printf '\n--- État du coffre ---\n'

    if test -f "$COFFRE_FICHIER"; then
        printf 'Conteneur: présent\n'
        printf 'Permissions: %s\n' "$(stat -c '%a' "$COFFRE_FICHIER")"
    else
        printf 'Conteneur: absent\n'
    fi

    if mapping_present; then
        printf 'Mapping: présent\n'
    else
        printf 'Mapping: absent\n'
    fi

    if montage_actif; then
        printf 'Montage: actif sur %s\n' "$COFFRE_MONTAGE"
    else
        printf 'Montage: inactif\n'
    fi
}

menu_principal() {
    local choix

    while true; do
        printf '\n=== Coffre sécurisé ===\n'
        printf '1) Installer\n'
        printf '2) Ouvrir\n'
        printf '3) Fermer\n'
        printf '4) GPG\n'
        printf '5) Quitter\n'

        if read -r -p 'Choix: ' choix; then
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
                    menu_gpg
                    ;;
                5)
                    return 0
                    ;;
                *)
                    erreur "Choix invalide. Saisir un nombre de 1 à 5."
                    ;;
            esac
        else
            info "Fin de l’entrée. Arrêt du script."
            return 0
        fi
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

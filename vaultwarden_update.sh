#!/bin/bash

# Vaultwarden Update Script - by Joshua Werner
# Updated: 2025-04-14

set -euo pipefail

LOGFILE="/var/log/vaultwarden-update.log"
INSTALL_DIR="/root/Install"
VAULTWARDEN_DIR="$INSTALL_DIR/vaultwarden"
GITHUB_API_WEBUI="https://api.github.com/repos/dani-garcia/bw_web_builds/releases/latest"
GITHUB_API_VW="https://api.github.com/repos/dani-garcia/vaultwarden/releases/latest"
BACKUP_DIR="/root/vaultwarden-backup-$(date +'%Y%m%d-%H%M%S')"

function log {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

function check_root {
    if [ "$(id -u)" -ne 0 ]; then
        log "Dieses Script muss als root ausgeführt werden."
        exit 1
    fi
}

function check_dependencies {
    log "Prüfe benötigte Programme..."
    for cmd in curl cargo git wget; do
        if ! command -v "$cmd" &> /dev/null; then
            log "Fehler: '$cmd' ist nicht installiert."
            exit 1
        fi
    done
    log "Alle benötigten Programme sind vorhanden."
}

function system_update {
    log "Starte System-Update..."
    apt-get update -y && apt-get upgrade -y && apt-get dist-upgrade -y
    log "System-Update abgeschlossen."
}

function backup_existing_installation {
    log "Starte Backup der aktuellen Installation..."
    mkdir -p "$BACKUP_DIR"

    if [ -f /usr/bin/vaultwarden ]; then
        cp /usr/bin/vaultwarden "$BACKUP_DIR/"
        log "Vaultwarden Binary gesichert."
    fi

    if [ -d /var/lib/vaultwarden/web-vault ]; then
        cp -r /var/lib/vaultwarden/web-vault "$BACKUP_DIR/"
        log "WebUI gesichert."
    fi

    log "Backup abgeschlossen: $BACKUP_DIR"
}

function fetch_latest_vaultwarden_version {
    log "Ermittle neueste Vaultwarden-Version..."
    VW_VERSION=$(curl -s "$GITHUB_API_VW" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    log "Neueste Vaultwarden-Version: $VW_VERSION"
}

function update_vaultwarden {
    fetch_latest_vaultwarden_version

    log "Starte Vaultwarden Update..."
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"

    if [ -d "$VAULTWARDEN_DIR" ]; then
        rm -rf "$VAULTWARDEN_DIR"
    fi

    git clone --branch "$VW_VERSION" https://github.com/dani-garcia/vaultwarden "$VAULTWARDEN_DIR"
    cd "$VAULTWARDEN_DIR"

    cargo clean
    cargo build --features sqlite --release

    systemctl stop vaultwarden.service
    cp target/release/vaultwarden /usr/bin/vaultwarden
    systemctl start vaultwarden.service

    VAULTWARDEN_VERSION=$(vaultwarden --version)
    log "Vaultwarden Version nach Update: $VAULTWARDEN_VERSION"

    log "Vaultwarden Update abgeschlossen."
}

function fetch_latest_webui_version {
    log "Ermittle neueste WebUI-Version..."
    WEBUI_VERSION=$(curl -s "$GITHUB_API_WEBUI" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    log "Neueste WebUI-Version: $WEBUI_VERSION"
}

function update_webui {
    fetch_latest_webui_version

    WEBUI_TAR="bw_web_${WEBUI_VERSION}.tar.gz"
    WEBUI_URL="https://github.com/dani-garcia/bw_web_builds/releases/download/${WEBUI_VERSION}/${WEBUI_TAR}"

    log "Starte WebUI Update (${WEBUI_VERSION})..."
    cd "$INSTALL_DIR"

    wget "$WEBUI_URL"
    tar -xzf "$WEBUI_TAR"

    if [ -d "web-vault" ]; then
        systemctl stop vaultwarden.service
        cp -R web-vault/ /var/lib/vaultwarden/
        systemctl start vaultwarden.service
        log "WebUI Update abgeschlossen."
    else
        log "Fehler: web-vault Verzeichnis nicht gefunden."
        exit 1
    fi
}

function cleanup {
    log "Starte Aufräumarbeiten..."
    rm -rf "$VAULTWARDEN_DIR"
    rm -f "$INSTALL_DIR/bw_web_*.tar.gz"
    log "Aufräumarbeiten abgeschlossen."
}

function finish {
    log "Update abgeschlossen. Bitte kontrolliere die Version über das WebUI:"
    log "https://{your-domain}/admin/diagnostics"
}

function main {
    check_root
    check_dependencies
    system_update
    backup_existing_installation
    update_vaultwarden
    update_webui
    cleanup
    finish
}

trap 'log "Fehler während der Ausführung."; exit 1' ERR

main

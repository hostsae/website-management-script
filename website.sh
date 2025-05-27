#!/bin/bash
clear

# === Styling ===
CYAN="\e[36m"
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
BOLD="\e[1m"
RESET="\e[0m"

# === Path & Konfigurasi ===
WEBROOT="/var/www"
NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
PHP_SOCKET="/run/php/php8.3-fpm.sock"
BACKUP_DIR="/home/$USER/backups"
CLOUDFLARED_CONFIG="/etc/cloudflared/config.yml"

# === Banner ===
echo -e "${BOLD}${CYAN}"
echo "      )     )   (           (                   "
echo "   ( /(  ( /(   )\ )  *   ) )\ )    (           "
echo "   )\()) )\()) (()/(\` )  /((()/(    )\     (    "
echo "  ((_)\ ((_)\   /(_))( )(_))/(_))((((_)(   )\   "
echo "   _((_)  ((_) (_)) (_(_())(_))   )\ _ )\ ((_)  "
echo "  | || | / _ \ / __||_   _|/ __|  (_)_\(_)| __| "
echo "  | __ || (_) |\__ \  | |  \__ \   / _ \  | _|  "
echo "  |_||_| \___/ |___/  |_|  |___/  /_/ \_\ |___| "
echo -e "${RESET}"

install_all() {
    echo -e "${CYAN}⚙️ Menginstall web stack...${RESET}"
    sudo apt update
    sudo apt install -y nginx mariadb-server php8.3 php8.3-fpm php8.3-mysql phpmyadmin cloudflared
    sudo systemctl enable nginx mariadb php8.3-fpm cloudflared
    sudo systemctl start nginx mariadb php8.3-fpm cloudflared
    echo -e "${GREEN}✅ Web stack selesai di-install.${RESET}"
}

check_domains() {
    echo -e "${CYAN}🌐 Domain aktif:${RESET}"
    ls $NGINX_SITES_AVAILABLE
}

add_domain() {
    read -p "📝 Masukkan domain: " domain
    if [ ! -d "$WEBROOT/$domain/html" ]; then
        sudo mkdir -p $WEBROOT/$domain/html
        echo "<?php phpinfo(); ?>" | sudo tee $WEBROOT/$domain/html/index.php > /dev/null
        sudo chown -R www-data:www-data $WEBROOT/$domain
    fi

    sudo tee $NGINX_SITES_AVAILABLE/$domain > /dev/null <<EOF
server {
    listen 80;
    server_name $domain www.$domain;
    root $WEBROOT/$domain/html;
    index index.php index.html;
    location / {
        try_files \$uri \$uri/ =404;
    }
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$PHP_SOCKET;
    }
    location ~ /\.ht {
        deny all;
    }
}
EOF

    sudo ln -sf $NGINX_SITES_AVAILABLE/$domain $NGINX_SITES_ENABLED/$domain
    sudo nginx -t && sudo systemctl reload nginx

    if [ -f "$CLOUDFLARED_CONFIG" ] && ! grep -q "$domain" "$CLOUDFLARED_CONFIG"; then
        sudo sed -i "/ingress:/a\  - hostname: $domain\n    service: http://localhost:80" "$CLOUDFLARED_CONFIG"
        sudo systemctl restart cloudflared
    fi
    echo -e "${GREEN}✅ Domain $domain aktif.${RESET}"
}

remove_domain() {
    read -p "❌ Masukkan domain: " domain
    sudo rm -rf $WEBROOT/$domain
    sudo rm -f $NGINX_SITES_AVAILABLE/$domain $NGINX_SITES_ENABLED/$domain
    sudo nginx -t && sudo systemctl reload nginx
    if grep -q "$domain" "$CLOUDFLARED_CONFIG"; then
        sudo sed -i "/hostname: $domain/,+1d" "$CLOUDFLARED_CONFIG"
        sudo systemctl restart cloudflared
    fi
}

edit_config() {
    read -p "✏️ Masukkan domain yang ingin diedit: " domain
    local config="$NGINX_SITES_AVAILABLE/$domain"
    if [[ -f "$config" ]]; then
        sudo nano "$config"
        sudo nginx -t && sudo systemctl reload nginx
    else
        echo -e "${RED}❌ Konfigurasi tidak ditemukan.${RESET}"
    fi
}

restart_services() {
    echo -e "${CYAN}🔄 Restarting Nginx, PHP, MariaDB, Cloudflared...${RESET}"
    sudo systemctl restart nginx php8.3-fpm mariadb cloudflared
    echo -e "${GREEN}✅ Semua layanan telah di-restart.${RESET}"
}

check_status() {
    echo -e "${CYAN}📊 Status Layanan:${RESET}"
    for service in nginx php8.3-fpm mariadb cloudflared; do
        systemctl is-active --quiet $service \
        && echo -e "🟢 $service: aktif" \
        || echo -e "🔴 $service: tidak aktif"
    done
}

list_backups() {
    echo -e "${YELLOW}🕒 Daftar backup yang tersedia di $BACKUP_DIR:${RESET}"
    if compgen -G "$BACKUP_DIR/*.tar.gz" > /dev/null; then
        ls -lh --time-style=long-iso "$BACKUP_DIR"/*.tar.gz | sort -k6,7
    else
        echo -e "${RED}(Belum ada backup ditemukan)${RESET}"
    fi
}

backup_all() {
    mkdir -p "$BACKUP_DIR"

    echo -e "${YELLOW}🕒 Riwayat backup sebelumnya:${RESET}"
    list_backups

    echo ""
    read -p "📦 Lanjutkan membuat backup baru? [y/N]: " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && echo -e "${YELLOW}❌ Backup dibatalkan.${RESET}" && return

    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    TMP="$BACKUP_DIR/tmp"
    TARGET="$BACKUP_DIR/backup_hosting_$TIMESTAMP.tar.gz"

    echo -e "${CYAN}📦 Membuat backup...${RESET}"
    sudo mkdir -p "$TMP"

    sudo cp -r $WEBROOT "$TMP/"
    sudo cp -r /etc/nginx "$TMP/"
    sudo cp -r /etc/php "$TMP/"
    sudo cp -r /etc/phpmyadmin "$TMP/" 2>/dev/null
    sudo cp -r /etc/cloudflared "$TMP/" 2>/dev/null
    sudo mysqldump -u root -p --all-databases > "$TMP/mariadb.sql"
    dpkg --get-selections | grep php > "$TMP/php-packages.txt"

    sudo tar -czf "$TARGET" -C "$TMP" .
    sudo rm -rf "$TMP"

    echo -e "${GREEN}✅ Backup selesai: $TARGET${RESET}"
}

restore_all() {
    read -p "🗂 Masukkan path file backup (.tar.gz): " archive
    [[ ! -f "$archive" ]] && echo -e "${RED}❌ File tidak ditemukan.${RESET}" && return

    TMP="/tmp/restore_temp"
    sudo rm -rf "$TMP"
    mkdir -p "$TMP"

    echo -e "${CYAN}🔄 Mengekstrak backup...${RESET}"
    sudo tar -xzf "$archive" -C "$TMP"

    sudo cp -r "$TMP/www" "$WEBROOT"
    sudo cp -r "$TMP/nginx" /etc/
    sudo cp -r "$TMP/php" /etc/
    sudo cp -r "$TMP/phpmyadmin" /etc/ 2>/dev/null
    sudo cp -r "$TMP/cloudflared" /etc/ 2>/dev/null

    if [[ -f "$TMP/mariadb.sql" ]]; then
        echo -e "${CYAN}📂 Mengembalikan database...${RESET}"
        sudo mysql -u root -p < "$TMP/mariadb.sql"
    fi

    if [[ -f "$TMP/php-packages.txt" ]]; then
        echo -e "${CYAN}📦 Mengembalikan paket PHP...${RESET}"
        xargs -a "$TMP/php-packages.txt" sudo apt install -y
    fi

    sudo rm -rf "$TMP"
    restart_services

    echo -e "${GREEN}✅ Restore selesai.${RESET}"
}

while true; do
    echo ""
    echo -e "${BOLD}${CYAN}===== MENU MANAJEMEN WEBSITE =====${RESET}"
    echo -e "1. ⚙️ Install semua (Nginx, MariaDB, PHP, phpMyAdmin, Cloudflared)"
    echo -e "2. 🌐 Cek domain/subdomain aktif"
    echo -e "3. ➕ Tambah domain/subdomain"
    echo -e "4. ❌ Hapus domain/subdomain"
    echo -e "5. ✏️ Edit konfigurasi domain"
    echo -e "6. 🔄 Restart semua layanan"
    echo -e "7. 📦 Backup semua data (Web, DB, Configs)"
    echo -e "8. 🔁 Restore data dari backup"
    echo -e "9. 📊 Cek status layanan"
    echo -e "10. 🕒 Lihat riwayat backup"
    echo -e "11. 🚪 Keluar"
    echo -e "${CYAN}===================================${RESET}"
    read -p "🔸 Pilih opsi [1-11]: " choice

    case $choice in
        1) install_all ;;
        2) check_domains ;;
        3) add_domain ;;
        4) remove_domain ;;
        5) edit_config ;;
        6) restart_services ;;
        7) backup_all ;;
        8) restore_all ;;
        9) check_status ;;
        10) list_backups ;;
        11) echo -e "${YELLOW}👋 Keluar.${RESET}"; break ;;
        *) echo -e "${RED}❗ Pilihan tidak valid.${RESET}" ;;
    esac
done


# Website Management Script

Script bash untuk mengelola webserver di Linux Mint/Ubuntu dengan fitur:

- Install Nginx, MariaDB, PHP (8.1-8.3) dan ekstensi
- Konfigurasi domain dan virtual host Nginx
- Backup & restore lengkap data website, database, konfigurasi, dan Cloudflare tunnel
- Manajemen domain, restart layanan, cek status
- Backup otomatis daftar paket PHP dan database

## Cara Pakai

1. Download atau clone repo ini.
2. Pastikan `website.sh` executable:

   ```bash
   chmod +x website.sh

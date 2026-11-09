# Cloudflare ile dışarıdan erişim ve telefon uygulaması

Amaç: telefonlara hiçbir şey kurmadan, güvenli ve geçerli sertifikalı bir adresten (ör. `https://app.tezgahpanel.com`) uygulamayı açmak ve "Ana ekrana ekle" ile tam ekran uygulama olarak kullanmak. Girişi Cloudflare yapar: sadece izin verilen e-postalar, e-postaya gelen kodla girer.

Ücret: tünel ve giriş koruması (50 kişiye kadar) ücretsiz. Sadece alan adı (yaklaşık yılda 10 dolar). Otomatik yenileme kapalı; süre bitmeden 30 gün kala uygulamada kırmızı uyarı çıkar.

Cloudflare'in ekran adları zamanla değişebilir. Bir adım tutmazsa ekran görüntüsü atın.

## A. Hesap ve alan adı (telefondan da yapılabilir)
1. https://dash.cloudflare.com adresinden hesap açın. Şifreyi kimseyle paylaşmayın.
2. Sol menü **Domains → Registrations** → **Register domain** düğmesi (eski ekranlarda Domain Registration → Register Domains). İstediğiniz adı arayın (ör. `tezgahpanel.com`), 1 yıllık satın alın.
3. Satın aldıktan sonra alan adının ayarlarında **Auto-Renew** kapalı olsun.

## B. Zero Trust (ücretsiz plan)
4. Sol menü **Zero Trust**. Takım adı isterse kısa ve nötr bir ad yazın (ör. `tezgah`). Plan olarak **Free** seçin. Kart bilgisi isterse ücretsiz planda para çekilmez.

## C. Tünel (dükkan kapalıyken, kasa bilgisayarında)
5. Zero Trust → **Networks → Tunnels → Create a tunnel** → **Cloudflared** → ad: `dukkan` → işletim sistemi **Windows**.
6. Ekranda `cloudflared.exe service install eyJ...` ile başlayan bir komut çıkar. Bu komut tünelin anahtarıdır, kimseyle paylaşmayın (bana da yazmayın).
7. Kasa bilgisayarında PowerShell'i **yönetici olarak** açın:
   ```
   winget install --id Cloudflare.cloudflared
   ```
   Kurulum bitince PowerShell'i kapatıp yine yönetici olarak açın ve 6. adımdaki komutu yapıştırın. Cloudflare ekranında tünel **Healthy / Connected** olmalı.
8. Aynı ekranda **Public Hostname** ekleyin:
   - Subdomain: `app`
   - Domain: aldığınız alan adı
   - Service Type: **HTTPS**
   - URL: `localhost:8443`
   - Additional application settings → TLS → **No TLS Verify: açık** (sunucu kendi imzalı sertifika kullandığı için)

## D. Giriş koruması (Access)
9. Zero Trust → **Access → Applications → Add an application → Self-hosted**.
   - Application domain: `app.tezgahpanel.com`
   - Session Duration: **1 month** (ayda bir kod ister)
10. Policy ekleyin: Action **Allow**, Include → **Emails** → kullanacak herkesin e-posta adresi.
11. Kaydedin. Artık adresi açan herkes e-postasını yazar, gelen 6 haneli kodu girer. Listede olmayan giremez.

## D2. Uygulama yükleme dosyaları için girişsiz izin
Telefon "Uygulamayı yükle" derken simge ve tanım dosyasını (manifest) çerezsiz ister; Access bunları giriş sayfasına yönlendirirse telefon yüklemeyi reddeder. Bu dosyalar `/pwa/` klasöründe ve içlerinde gizli bilgi yok.
- Access → Applications → Add → Self-hosted, ad: `Tezgah yukleme`
- Domain: `app` + `tezgahpanel.com`, **Path:** `pwa`
- Policy: Action **Bypass**, Include → **Everyone**
- Kaydedin. Sadece `/pwa/...` girişsiz açılır, uygulamanın geri kalanı yine e-posta koduyla korunur.

## E. Uygulama tarafı
12. Kasa bilgisayarında `C:\FiyatGor\alanadi.txt` dosyası oluşturup içine sadece alan adını yazın (ör. `tezgahpanel.com`). Sunucu bitiş tarihini buradan takip eder.
13. Telefonda `https://app.tezgahpanel.com` adresini açın, e-posta kodu ile girin.
    - **iPhone (Safari):** Paylaş → **Ana Ekrana Ekle**.
    - **Android (Chrome):** ⋮ menü → **Uygulamayı yükle** / **Ana ekrana ekle**.
14. Kasa bilgisayarında da Edge/Chrome ile aynı adresi açıp **Uygulama olarak yükle** diyebilirsiniz.

Tailscale çalışmaya devam eder; ikisi aynı anda kullanılabilir.

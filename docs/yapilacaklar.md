# Yapılacaklar

## Bekleyen
### Dükkanda denenecek (yazıldı)
- [ ] Dönem devri (Stok → Dönem devri): kaynak dönemde SUM(DEPOENVANTER.ENVANTER) > 0 olan ürünler hedef döneme tek devir giriş fişiyle (ALTBELGENO = DEVIR-<kaynak>, ikinci kez engellenir). Şimdilik sadece Önizle denenecek; Devret yılbaşında, Vega yeni dönemi açtıktan ve izin.sql yeniden çalıştırıldıktan sonra.
- [ ] Fiyat sorguda bulunamayan ürün için ＋ Ekle düğmesi.

### Yapılacak
- [x] Kullanıcı girişi ve roller (ilk yönetici kuruldu, giriş çalışıyor): kayıt ol yok, hesapları yönetici açar. PIN kaldırıldı. Roller: Yönetici (her şey) ve Kullanıcı (işaretlenen izinler: fiyat değiştirme, ürün ekleme/düzenleme, stok girişi, etiket, içerik, dönem devri). Yetkiler sunucuda denetlenir. Hesap açma, düzenleme, pasif yapma, şifre sıfırlama, silme; herkes kendi şifresini değiştirebilir.
- [ ] Yapay zekâ ile içerik taslağı: İçerik ekranında "Taslak oluştur". Besin değerleri önce gerçek veri setlerinden: genel ürünler (fındık, leblebi, çekirdek…) için TürKomp (Ulusal Gıda Kompozisyon Veri Tabanı) ve USDA FoodData Central (ücretsiz API, kamu malı); barkodlu markalı ürünler için Open Food Facts. Gemini sadece ürün adını doğru veri seti kaydıyla eşleştirir (ör. "çifte kavrulmuş fındık" → kavrulmuş fındık), içindekiler/alerjen taslağı yazar ve karışımlarda oranlı hesap önerir. Her şey taslak: kullanıcı kontrol edip Kaydet'e basmadan CL'ye/teraziye gitmez; kaynak ekranda yazar. API anahtarları kasada C:\FiyatGor içinde, istekler sunucu üzerinden.
- [ ] Yemeksepeti ve Trendyol entegrasyonu: siparişleri/ürün-fiyat-stok eşitlemesini kasa sunucusu üzerinden yapmak (Trendyol'un açık satıcı API'si var; Yemeksepeti iş ortağı onayı gerektirir). Ekranlar aynı uygulamaya eklenecek, ayrı masaüstü programı gerekmez.
- [ ] Fatura sistemi entegrasyonu (e-Fatura / e-Arşiv): faturalar şu an Vega'nın web portalından kesiliyor. Araştırma: Vega Yazılım GİB izinli özel entegratör (e-Fatura, e-Arşiv, e-İrsaliye); dış programlar için SOAP web servisi var (üçüncü taraf programlar "API bilgisiyle" bağlanıyor, resmi belge açık değil). Bayi yardımcı olamıyor; merkez de bayiye yönlendirebiliyor. Yol sırası: (1) Vega programında fatura menüsü varsa faturayı Vega veritabanına satış faturası olarak yazıp Vega'dan göndermek (stok girişi gibi keşif: önce kaydet-gönderme-sil ya da 1 TL'lik gerçek satışa 11111111111 nihai tüketici faturası); (2) olmazsa uygulamanın Vega fatura sitesini kullanıcı adına açması (site 6-7 yıldır aynı; önce tarayıcı geliştirici araçlarıyla bir fatura kesme kaydı (HAR) alınıp istekler çıkarılacak; site şifresi kasada dosyada; fatura önce önizleme, onaysız gitmez); (3) Vega merkezinden web servis bilgileri. Anahtarlar kasada, istekler sunucu üzerinden.

### Dükkan sahibi elle yapacak
- [ ] CL'de aynı ürün kodlu ve fiyatı farklı ürünlerin temizliği (126 kod, 108'inde fiyat farklı; PLU 1000 ve 9994-9999 gibi kopyalar).

## Tamamlandı
- [x] Normal kullanıcı hesabı iPhone Safari'de denendi, Ana Ekrana Ekle ile çalışıyor
- [x] ⚖️ Terazi sekmesi: sadece terazi ürünleri; solda CL PLU (1000 altı, aynı koddakiler alt alta), sağda ad ve fiyat; dokununca Fiyat ekranı (dükkanda denenecek)
- [x] Öğretici: normal kullanıcıya ilk girişte (telefon başına bir kez) adım adım tanıtım; sadece yetkili olduğu sekmeler anlatılır; Ayarlar → Hesabım → Öğreticiyi başlat ile herkes tekrar açabilir
- [x] Aramalarda terazi ürünleri (TRZ-) en üstte: tam barkod/PLU/kod eşleşmesi önce, sonra adı aranan kelimeyle başlayan TRZ'ler, diğer TRZ'ler, sonra diğer ürünler
- [x] Cloudflare Access kaldırıldı; giriş uygulamanın kendi e-posta + şifresiyle
- [x] Etiketin kalın/büyük yazılı hali ve Türkiye yazımında Yerli Üretim logosu, dükkanda basıldı
- [x] Stok girişi (📦 Stok sekmesi): adet × çarpan, devir giriş fişi; dükkanda denendi, Vega'da miktar doğru (30 + 24 = 54)
- [x] Mobil uygulama: Cloudflare Tunnel ile https://app.tezgahpanel.com, telefona uygulama olarak yüklendi (docs/cloudflare-kurulum.md). Kalan: C:\FiyatGor\alanadi.txt (bitiş uyarısı), kasa bilgisayarında da uygulama olarak yükleme.
- [x] İçerik gönderimi telefondan paket terazilerine (W30), içerik 1, 3 ve 282 ile birebir doğrulandı
- [x] Okutulan barkod stok kodunda da aranır (Vega gibi)
- [x] Alt menü sekmeleri Ayarlar'dan açılıp kapatılabilir (telefon başına)
- [x] İçerik sekmesinde olmayan kodu yazınca o kodla yeni içerik oluşturma
- [x] Fiyat sorgu ayrı sekme (🔎 Sorgu), sekmeye girince kamera kendiliğinden açılır
- [x] Etiket yazdırma (Sbarco), dükkanda basıldı
- [x] Sabit fiyatlı terazi ürünü ekleme, özel kodlar, fiyat sorgu, birim ekleme, eklerken içerik seçimi: denendi
- [x] İçerik gönderim protokolü (W30) çözüldü
- [x] Telefondan fiyat sorgulama, barkod/terazi etiketi okuma, sepet
- [x] Kasa veritabanından (Vega/UNSALDB) canlı bağlantı
- [x] Telefondan fiyat değiştirme (yetkili kullanıcı, çok birimli ürünlerde tüm birimler)
- [x] Telefondan ürün ekleme (Vega'ya)
- [x] Tailscale ile dükkan dışından erişim
- [x] CL Works terazi protokolü çözüldü (6 yakalama ile doğrulandı)
- [x] Fiyat değişince doğrudan terazilere gönderme (CL "Gönder" gerekmez), test edildi
- [x] Fiyat değişiminde ve gönderimde PLU 1000 ve üstü atlanır
- [x] Aynı ürün kodlu terazi ürünlerini listeleme, fiyat ekranında birlikte değişecekleri gösterme
- [x] Sunucu güncellenince kendini yeniden başlatır
- [x] Ekle ekranı seçim listeleri (izin.sql)
- [x] Terazi ürünü ekleme: Vega + CL + doğrudan teraziye gönderim, denendi
- [x] Mevcut ürünün özel kodlarını Fiyat sekmesinden değiştirme, denendi
- [x] İçerik sekmesi: CL içeriklerini arama, açma, düzenleme, yeni içerik, alerjen listesi, besin değerleri, denendi

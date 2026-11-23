# Yapılacaklar

## Bekleyen
### Dükkanda denenecek (yazıldı)
- [ ] Dönem devri (Stok → Dönem devri): kaynak dönemde SUM(DEPOENVANTER.ENVANTER) > 0 olan ürünler hedef döneme tek devir giriş fişiyle (ALTBELGENO = DEVIR-<kaynak>, ikinci kez engellenir). Şimdilik sadece Önizle denenecek; Devret yılbaşında, Vega yeni dönemi açtıktan ve izin.sql yeniden çalıştırıldıktan sonra.
- [ ] Fiyat sorguda bulunamayan ürün için ＋ Ekle düğmesi.

### Yapılacak
- [ ] Kullanıcı girişi ve roller: Cloudflare Access ile girenler **yönetici** (Cloudflare'in gönderdiği Cf-Access-Authenticated-User-Email başlığından anlaşılır). Ayrıca uygulamanın kendi **e-posta + şifre** girişi; bu şekilde girenler **normal kullanıcı**. Şifreler kasada tuzlanmış özet (hash) olarak saklanır, kullanıcıları yönetici ekler/siler. Normal kullanıcıların Cloudflare'e takılmadan girebilmesi için ayrı bir adres (ör. kullanici.tezgahpanel.com, Access'siz) ya da Access'te ayrı kural gerekecek. Rol atama: yönetici, Ayarlar'daki kullanıcı listesinden her kullanıcıya rol verir (ör. yönetici / personel / sadece bakar); her rolün hangi sekmeleri görüp neleri yapabileceği (fiyat değiştirme, ürün ekleme, stok girişi, etiket, içerik, devir) seçilebilir. Yetkiler sunucuda da denetlenir, sadece ekranda gizlemek yetmez. Varsayılan rollerin içeriği kullanıcıyla netleştirilecek.
- [ ] Öğretici: normal kullanıcılar için ilk açılışta adım adım tanıtım (sekmeler, barkod okutma, sorgu…), Ayarlar'dan tekrar açılabilir.
- [ ] Aramalarda terazi ürünleri (TRZ-) en üstte: ör. "nane" aranınca önce TRZ'li Nane, sonra nane yağı vb. Ürünler, Hesap, Fiyat, Stok ve Ekle aramalarında aynı sıralama; TRZ'ler içinde adı aranan kelimeyle başlayanlar önce.
- [ ] Yapay zekâ ile içerik taslağı: İçerik ekranında "Taslak oluştur". Besin değerleri önce gerçek veri setlerinden: genel ürünler (fındık, leblebi, çekirdek…) için TürKomp (Ulusal Gıda Kompozisyon Veri Tabanı) ve USDA FoodData Central (ücretsiz API, kamu malı); barkodlu markalı ürünler için Open Food Facts. Gemini sadece ürün adını doğru veri seti kaydıyla eşleştirir (ör. "çifte kavrulmuş fındık" → kavrulmuş fındık), içindekiler/alerjen taslağı yazar ve karışımlarda oranlı hesap önerir. Her şey taslak: kullanıcı kontrol edip Kaydet'e basmadan CL'ye/teraziye gitmez; kaynak ekranda yazar. API anahtarları kasada C:\FiyatGor içinde, istekler sunucu üzerinden.
- [ ] Yemeksepeti ve Trendyol entegrasyonu: siparişleri/ürün-fiyat-stok eşitlemesini kasa sunucusu üzerinden yapmak (Trendyol'un açık satıcı API'si var; Yemeksepeti iş ortağı onayı gerektirir). Ekranlar aynı uygulamaya eklenecek, ayrı masaüstü programı gerekmez.

### Dükkan sahibi elle yapacak
- [ ] CL'de aynı ürün kodlu ve fiyatı farklı ürünlerin temizliği (126 kod, 108'inde fiyat farklı; PLU 1000 ve 9994-9999 gibi kopyalar).

## Tamamlandı
- [x] Etiketin kalın/büyük yazılı hali ve Türkiye yazımında Yerli Üretim logosu, dükkanda basıldı
- [x] Stok girişi (📦 Stok sekmesi): adet × çarpan, devir giriş fişi; dükkanda denendi, Vega'da miktar doğru (30 + 24 = 54)
- [x] Mobil uygulama: Cloudflare Tunnel + Access ile https://app.tezgahpanel.com, telefona uygulama olarak yüklendi (docs/cloudflare-kurulum.md). Kalan: C:\FiyatGor\alanadi.txt (bitiş uyarısı), diğer kullanıcıların e-postaları, kasa bilgisayarında da uygulama olarak yükleme.
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
- [x] Telefondan fiyat değiştirme (PIN korumalı, çok birimli ürünlerde tüm birimler)
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

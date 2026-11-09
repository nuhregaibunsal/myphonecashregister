# Yapılacaklar

## Bekleyen
### Dükkanda denenecek (yazıldı)
- [ ] Etiket yeni hali (kalın/büyük yazılar, Türkiye yazımında Yerli Üretim logosu) tekrar basılıp bakılacak.
- [ ] Fiyat sorguda bulunamayan ürün için ＋ Ekle düğmesi.

### Yapılacak
- [ ] Mobil uygulama: şu an site güvenilmeyen (kendi imzalı) sertifikayla açıldığı için telefon uygulama olarak yüklemiyor, sadece adres kısayolu ekliyor. 1. adım: Tailscale'in ücretsiz geçerli sertifikasıyla (kasa-bilgisayari.xxx.ts.net adresi, tailscale cert) siteyi açmak; böylece "Uygulamayı yükle" çıkar, adres çubuğu olmadan tam ekran çalışır. Yetmezse Android uygulaması (APK) olarak paketlemek.
- [ ] Telefondan stok girişi (mal kabul): ürünü okutup gelen miktarı Vega'ya işleme. Vega'nın stok girişini nasıl kaydettiği incelenecek.

### Dükkan sahibi elle yapacak
- [ ] CL'de aynı ürün kodlu ve fiyatı farklı ürünlerin temizliği (126 kod, 108'inde fiyat farklı; PLU 1000 ve 9994-9999 gibi kopyalar).

## Tamamlandı
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

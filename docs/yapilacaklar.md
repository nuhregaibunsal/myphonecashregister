# Yapılacaklar

## Bekleyen
### Dükkanda denenecek (yazıldı)
- [ ] Wireshark: CL'den 24 numaralı içeriği yalnız 192.168.1.153'e gönderirken yakala (filtre host 192.168.1.153), dosyayı gönder. İçerik gönderim protokolü için.
- [ ] Etiket yazdırma (Sbarco, Fiyat sekmesi → Etiket): telefondan 1 kopya bas, Vega'nınkiyle karşılaştır. Yerleşim web/etiket-duzen.js (Vega tasarım birimleri). T.E.T.T = yazdırma günü + 366 gün, kayıt no KOD6, Yerli Üretim logosu KOD10 = TURKIYE.

- [ ] Sabit fiyatlı terazi ürünü ekleme (Ekle → Terazi ürünü → Sabit fiyatlı): kasada birim ADET, barkod 28 + ürün kodu (5 hane) + 00001 + kontrol hanesi (örnek TRZ-430 → 2800430000018), CL'de tip 2. Adet. Yazıldı, dükkanda denenecek.

- [ ] Ürün eklerken özel kodlar: Tür (KOD1, terazide "Terazilikler"), üretim yeri (KOD10), kayıt no (KOD6) formda; Sınıf, Grup, 4-ÖK, 5-ÖK, Marka, Renk "Gelişmiş" altında. Listeler F0101TBLSTOKKODTAN (CATEGORY = KOD no), yeni değer listeye eklenir. Mevcut ürünün özel kodları Fiyat sekmesinde değiştirilebilir. Üretim yeri TURKIYE ise kayıt no varsayılan TR-41-K-033887. izin.sql tekrar çalıştırılmalı.

- [ ] İçerik sekmesi (CL TbIngredient: Code, IngText): ara/aç/yeni (ilk boş = en büyük kod + 1), 3 bölüm (içindekiler, alerjen listesi içerir/eser, besin değerleri kutuları), kayıt no sabit TR-41-K-033887, önizleme, CL'ye kaydet. Yazıldı, denenecek. Paket terazilerine (192.168.1.153, 192.168.1.204) otomatik gönderim Wireshark yakalamasından sonra eklenecek.

### Yapılacak
- [ ] Var olan ürünlere telefondan yeni birim ekleme (örnek: KG ürününe 250 gr / 500 gr paket birimi, ağırlık ve barkodla). Vega'nın birim ekleme şekli (F0101TBLBIRIMLEREX satırı) incelenecek.
- [ ] Fiyat sorgu sayfası: kamera sürekli açık, okutulan ürünün adı ve fiyatı büyük yazılır. "Düzenle" ile fiyat değiştirme paneli açılır; panel elle ya da 5 saniye sonra kendiliğinden kapanır, açıkken yeni barkod okunursa yeni ürün gelir.
- [ ] Telefondan stok girişi (mal kabul): ürünü okutup gelen miktarı Vega'ya işleme. Vega'nın stok girişini nasıl kaydettiği incelenecek.

### Dükkan sahibi elle yapacak
- [ ] CL'de aynı ürün kodlu ve fiyatı farklı ürünlerin temizliği (126 kod, 108'inde fiyat farklı; PLU 1000 ve 9994-9999 gibi kopyalar).

## Tamamlandı
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
- [x] Terazi ürünü ekleme: Vega + CL + doğrudan teraziye gönderim, dükkanda denendi (TEST ürünü kaldı, Vega'da silme yok)
- [x] Ekle ekranı seçim listeleri (izin.sql güncel hali çalıştırıldı)

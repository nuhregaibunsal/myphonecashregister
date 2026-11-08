# Yapılacaklar

## Bekleyen
### Dükkanda denenecek (yazıldı)
- [ ] Etiket yazdırma (Sbarco, Fiyat sekmesi → Etiket): telefondan 1 kopya bas, Vega'nınkiyle karşılaştır. Yerleşim web/etiket-duzen.js (Vega tasarım birimleri). T.E.T.T = yazdırma günü + 366 gün, kayıt no KOD6, Yerli Üretim logosu KOD10 = TURKIYE.
- [ ] Terazi ürünü ekleme (Ekle sekmesi → Terazi ürünü): Vega + CL + doğrudan teraziye gönderim. TEST ürünüyle denenecek, sonra TEST hem Vega'dan hem CL'den silinecek.
  - Kullanılmayan sütunlar mevcut bir TbPLU satırından kopyalanır, kullanılanlar formdan yazılır.
  - PLU no elle yazılır; doluysa hata verir, ilk boş PLU önerilir.
  - İçerik no varsayılan 0, son kullanma varsayılan 366, tip varsayılan 1 (Ağırlık), istenirse 2 (Adet).

### Yapılacak
- [ ] **Sabit fiyatlı terazi ürünleri** (Adet tipinde): Ekle ve fiyat değiştirme ekranlarında destek (F=1A UseFixedPrice, F=05 UnitWeight hazır).
- [ ] Telefondan eklenen ürünlere Vega özel kodlarının girilmesi (Tür = "Terazilikler", Marka = son tüketim tarihi, KOD6 = kayıt no, KOD10 = üretim yeri).
- [ ] İçindekiler sisteminin bağlanması (şu an sadece içerik no seçiliyor).
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
- [x] Ekle ekranı seçim listeleri (izin.sql güncel hali çalıştırıldı)

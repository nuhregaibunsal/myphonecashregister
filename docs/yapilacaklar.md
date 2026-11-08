# Yapılacaklar

## Bekleyen
- [ ] **Sabit fiyatlı terazi ürünleri ayarlanacak.** Telefondaki "Ekle" ekranında ve fiyat değiştirmede, sabit fiyatlı (UseFixedPrice) tartılı ürünler için destek. CL'ye ve teraziye doğru gönderim (F=1A = UseFixedPrice, F=05 = UnitWeight alanları hazır; ekleme/düzenleme arayüzü yapılacak).
- [ ] Yeni terazi ürününü telefondan eklerken CL'ye (TbPLU) de ekleme. Yazıldı, dükkanda denenecek. Kararlar:
  - Kullanılmayan sütunlar mevcut bir TbPLU satırından kopyalanır, kullanılanlar formdan yazılır.
  - PLU no elle yazılır; doluysa hata verir, ilk boş PLU önerilir.
  - İçerik no seçilebilir, varsayılan 0 (içindekiler sistemi ileride entegre edilecek).
  - Son kullanma varsayılan 366, değiştirilebilir.
  - Tip varsayılan 1 (Ağırlık), istenirse 2 (Adet). Sabit fiyatlılar Adet olacak.
  - Eklenen ürün W02 ile doğrudan terazilere gönderilir.
- [x] Fiyat değişiminde ve gönderimde PLU 1000 ve üstü atlanır.
- [ ] CL'de aynı ürün kodlu ve fiyatı farklı ürünler (126 kod, 108'inde fiyat farklı; PLU 1000 ve 9994-9999 gibi kopyalar) elle temizlenecek.
- [ ] Telefondan eklenen terazi ürünlerine Vega'daki özel koddan tür atanması (şu an KOD1-KOD8 boş gidiyor). Hangi özel kod alanı ve hangi değerler kullanılacağı netleştirilecek.
- [ ] Yazıcıdan (Sbaro etiket yazıcısı, USB) etiket basma. Tasarım Vega arayüzünde.

## Tamamlandı
- [x] Telefondan fiyat sorgulama, barkod/terazi etiketi okuma, sepet
- [x] Kasa veritabanından (Vega/UNSALDB) canlı bağlantı
- [x] Telefondan fiyat değiştirme (PIN korumalı, çok birimli ürünlerde tüm birimler)
- [x] Telefondan ürün ekleme (Vega'ya)
- [x] Tailscale ile dükkan dışından erişim
- [x] CL Works terazi protokolü çözüldü (6 yakalama ile doğrulandı)
- [x] Fiyat değişince doğrudan terazilere gönderme (CL "Gönder" gerekmez)
- [x] Aynı ürün kodlu terazi ürünlerini listeleme, fiyat ekranında birlikte değişecekleri gösterme

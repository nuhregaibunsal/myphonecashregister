# Yapılacaklar

## Bekleyen
- [ ] **Sabit fiyatlı terazi ürünleri ayarlanacak.** Telefondaki "Ekle" ekranında ve fiyat değiştirmede, sabit fiyatlı (UseFixedPrice) tartılı ürünler için destek. CL'ye ve teraziye doğru gönderim (F=1A = UseFixedPrice, F=05 = UnitWeight alanları hazır; ekleme/düzenleme arayüzü yapılacak).
- [ ] Yeni terazi ürününü telefondan eklerken CL'ye (TbPLU) de ekleme (şu an sadece Vega'ya ekliyor).
- [ ] Yazıcıdan (Sbaro etiket yazıcısı, USB) etiket basma. Tasarım Vega arayüzünde.

## Tamamlandı
- [x] Telefondan fiyat sorgulama, barkod/terazi etiketi okuma, sepet
- [x] Kasa veritabanından (Vega/UNSALDB) canlı bağlantı
- [x] Telefondan fiyat değiştirme (PIN korumalı, çok birimli ürünlerde tüm birimler)
- [x] Telefondan ürün ekleme (Vega'ya)
- [x] Tailscale ile dükkan dışından erişim
- [x] CL Works terazi protokolü çözüldü (4 yakalama ile doğrulandı)
- [x] Fiyat değişince doğrudan terazilere gönderme (CL "Gönder" gerekmez)

# UNSALDB veritabanı haritası

Bu dosya, telefondaki sorgulama ve SSMS'teki keşif sonuçlarından çıkarıldı. Sunucu: `(local)`, SQL Server 2019 (15.0), veritabanı `UNSALDB`. Kasa programı Vega (arka ofis) ve FasterPOS (kasa önü).

## Tablo adları

- `F0101...` : firma 01, dönem 01 tabloları. Ürün kartları ve birimler burada.
- `F0101D0001...`, `D0004`, `D0006`, `D0007` : depo/şube bazlı hareket tabloları (satış, stok hareketi, cari). Fiyat sorgulama için kullanılmaz.
- `TBL...` (önek yok) : ortak tablolar ve FasterPOS tabloları. Çoğu boş şablon.

## Uygulamanın kullandığı tablolar

| Tablo | Satır | Ne için |
|---|---|---|
| `F0101TBLSTOKLAR` | 2676 | Ürün kartı. `IND` anahtar, `MALINCINSI` ürün adı, `DELETED` / `IPTAL` silinmiş ve iptal işaretleri. `STOKNO` sütunu boş, anahtar değil. |
| `F0101TBLBIRIMLEREX` | 2744 | Satış birimi. Her ürünün bir veya birkaç birimi var. `STOKNO` → `F0101TBLSTOKLAR.IND`. `BARCODE` barkod, `SATISFIYATI1` satış fiyatı (boşsa `SATISFIYATI`), `BIRIMADI` ADET / KG / PAKET. `PLU` hep boş. |
| `TBLFASTERSTOKLAR` | 134 | FasterPOS'un kasa listesi. `BIRIMIND` → `F0101TBLBIRIMLEREX.IND`. Terazi `PLU` numarası buradan alınır. |

Ölçülen değerler:

- Birim satırlarından 2718'i bir ürün kartına bağlı, 2187'sinde barkod alanı dolu.
- `F0101TBLBIRIMLEREX.PLU` hiçbir satırda dolu değil.
- Bazı barkodsuz ürünlerde ürün adı `BARCODE` alanına yazılmış (örn. `MABEK KAŞIK ÇİKOLATA`), `MALINCINSI` boş.
- `IND` 1-3 sistem kayıtları: VADE FARKI, KUR FARKI, DEVIR.

## Dışa aktarma kuralları (`araclar/urunler.sql`)

1. `F0101TBLBIRIMLEREX` her satırı bir ürün satırı olur, `F0101TBLSTOKLAR` ile `IND` üzerinden birleşir.
2. Ad: `MALINCINSI`, boşsa birim `ACIKLAMA`, o da boşsa `BARCODE` alanındaki yazı.
3. Barkod: sadece rakamlardan oluşuyorsa alınır. İsim yazılmış barkod alanları boş barkod sayılır.
4. Fiyat: `SATISFIYATI1`, sıfırsa `SATISFIYATI`.
5. PLU: aynı birime bağlı `TBLFASTERSTOKLAR.PLU`, yoksa boş.
6. Silinmiş, iptal edilmiş, sistem kayıtları ve fiyatı da barkodu da olmayan satırlar alınmaz.
7. Ad içindeki virgül, noktalı virgül ve tırnaklar temizlenir; SSMS'in CSV kaydını bozmasın diye.

## Açık konular

- Terazi PLU'ları büyük ihtimalle CL Works Pro'nun `.mdb` dosyasında. `TBLFASTERSTOKLAR` yetmezse oradan çekilip eşleştirilecek.
- Kısa sayısal barkodlar (örn. `00244`) terazi etiketindeki ürün koduyla eşleşebilir; uygulama bunu otomatik dener.

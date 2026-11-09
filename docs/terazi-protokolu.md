# CAS CL-Works terazi protokolü

CL Works, PLU kaydını terazilere TCP **20304** portundan ASCII tabanlı bir paketle gönderiyor. Bu belge dört Wireshark yakalamasının (AY ÇEKİRDEĞİ, FINDIK İÇİ, ÇİĞ, DİĞER) bayt bayt incelenmesine dayanıyor. Üretilen paket dördünde de orijinalle aynı.

## Akış (Ethernet dolgusu ayıklanmış)
1. PC teraziye TCP bağlantısı açar.
2. PC tek bir W02 paketi gönderir.
3. Terazi 45 bayt cevap verir: `^=01.*=01.$=0.&=<IP hex>.@=<port hex>.?=3.W02:O01` + `\n\n`
   - `&` terazinin IP'si (C0A801C9 = 192.168.1.201), `@` port (4F50 = 20304), `?=3` TbScale.Country.
   - `W02:O01` = W02 komutu kabul edildi. Cevap dört testte birebir aynı, ürünle değişmiyor.
4. Bağlantı kapanır.

Terazi bağlanınca bir şey göndermiyor; yakalamalarda görünen `00 00` ve `00 00 00 00 00 00` Ethernet çerçeve dolgusu.

## Paket
`W02A<PLU, 5 hane HEX>,<Reyon, 2 hane>L<gövde uzunluğu, 4 hane HEX>:<gövde><checksum>`

- Gövde: 23 alan, **her zaman aynı sırada ve aynı alanlar**. Biçim: `F=<id>.<tip>,<uzunluk HEX>:<değer>`
- Tipler: `57` W = 2 bayt, `4C` L = 4 bayt, `42` B = 1/2/4 bayt, `4D` M = 1 bayt (sayılar little-endian), `53` S = metin (Windows-1254).
- Checksum: gövde baytlarının XOR'u (başlık dahil değil). Dört testte doğru.
- W02 hem yeni PLU oluşturuyor hem var olanı güncelliyor (T3 ve T4 yeni satırdı, terazi kabul etti).

## Alanlar
| F | Tip | TbPLU sütunu | Durum | T1 AY | T2 FINDIK | T3 ÇİĞ | T4 DİĞER |
|---|---|---|---|---|---|---|---|
| 01 | W | DeptNo | doğrulandı | 1 | 1 | 2 | 1 |
| 02 | L | PluNo | doğrulandı | 19 | 2 | 386 | 388 |
| 04 | M | PluType | doğrulandı | 1 | 1 | 2 | 3 |
| 05 | B1 | UnitWeight | doğrulandı | 0 | 0 | 1 | 2 |
| 06 | L | UnitPrice × 100 | doğrulandı | 24242 | 120000 | 1242 | 12332 |
| 0B | L | ItemCode | doğrulandı | 9 | 1 | 1234 | 5467 |
| 10 | L | SellByDate | doğrulandı | 373 | 365 | 12 | 365 |
| 19 | W | IngredientNo | doğrulandı | 20 | 1 | 24 | 23 |
| 1A | B1 | UseFixedPrice | doğrulandı | 0 | 0 | 1 | 0 |
| 0A | S | Name1 | doğrulandı | AY CEKİRDEGİ | FINDIK ICI␠ | ÇİĞ | DİĞER |
| 09 | W | ? | hep 0 | | | | |
| 0D | L | ? | hep 0 | | | | |
| 0E | W | ? | hep 0 | | | | |
| 0F | B1 | ? | hep 0 | | | | |
| 11 | B2 | ? | hep 0 | | | | |
| 12 | W | ? | hep 0 | | | | |
| 37 | W | ? | hep 0 | | | | |
| 51 | W | ? | hep 0 | | | | |
| 55 | W | ? | hep 0 | | | | |
| 5B | B4 | ? | hep 0 | | | | |
| 64 | L | ? | hep 0 | | | | |
| 1E | S | ? | hep boş | | | | |
| 1F | S | ? | hep boş | | | | |

PluType değerleri: 1 = Kilo, 2 = Adet, 3 = Parça.

T5 (PLU 387 ŞİÇJ, Kilo) ve T6 (aynı ürün, Adet) körlemesine tahmin edildi; ikisi de 303 baytın tamamında yakalamayla birebir tuttu (checksum 0x2F / 0x2C), terazi W02:O01 ile kabul etti.

FixedWeight (T3'te 12, T4'te 54 girildi) pakette hiç yok; bu komutla gönderilmiyor.

## Bilinmeyenler
13 alan dört testte de 0/boş, çünkü test ürünlerinde karşılık gelen sütunlar (GroupNo, LabelNo, OriginNo, Tare, BarcodeID, SpecialPrice, Name2... adayları) boştu. Göndericide bunlar 0 gidiyor; bu sütunları dolu olan bir ürüne gönderilirse o bilgiler terazide sıfırlanır. Eşlemek için:
1. `canli/cl-istatistik.ps1` ile dükkânda hangi sütunların gerçekten dolu olduğu ölçülür.
2. Dolu olan sütunlara bir test ürününde **birbirinden farklı** değerler verilip tek yakalama yapılır; her değer tek bir alana düşeceği için eşleme kesinleşir.

## İçerik (içindekiler) gönderimi: W30
Yakalama: içerik 1 ve 3, 192.168.1.204'e. Her ikisi de bayt bayt tahminle aynı çıktı (315 ve 319 bayt).

```
W30F01,<kod 4 hex>L<gövde uzunluğu 3 hex>:X=00.D=<metin uzunluğu 3 hex>.<metin><XOR>
```
- Metin CL'deki IngText, satır sonları `\r\n` → `\n`, Windows-1254.
- Gövde = `X=00.D=xxx.` + metin; XOR gövde baytları üzerinden (başlık hariç), W02 ile aynı.
- Kod onaltılık kabul edildi (W02'deki PLU gibi); 10 ve üstü kodla henüz doğrulanmadı.
- Terazi cevabı: `W30:O0001` (içerik 1 ve 3 için aynı, yani kod değil "tamam" anlamında).
- Paket terazileri: 192.168.1.153 (Paket Yeni), 192.168.1.204 (Terazi Paket İçin). Değiştirmek için C:\FiyatGor\paket-terazi.txt.
- Doğrulama: içerik 282 (kısa metin) de birebir tuttu: `W30F01,011AL02D:X=00.D=022.`, XOR 0xD0, 62 bayt. Kod onaltılık, uzunluklar 3 haneye sıfırla tamamlanıyor.

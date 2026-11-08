# CAS CL-Works terazi protokolü (çözüldü)

CL Works terazilere TCP **port 20304** üzerinden ASCII tabanlı bir protokolle PLU gönderiyor. Wireshark yakalamasından çözüldü, kendi ürettiğimiz paket orijinalle bayt bayt aynı.

## Akış
1. PC teraziye bağlanır (TCP).
2. Terazi `00 00` (2 bayt) gönderir.
3. PC PLU kaydını gönderir (aşağıdaki W02 paketi).
4. Terazi `00 00 00 00 00 00` (6 bayt) onay gönderir.
5. Terazi durum/sonuç gönderir: `^=01.*=01.$=0.&=<IP hex>.@=<port hex>.?=3.W02:O01` (`O01` = başarılı).

## Paket biçimi (W02 = PLU yaz)
Başlık: `W02A<PLU:5 hane HEX>,<Reyon:2 hane>L<gövde uzunluğu:4 hane HEX>:`
Gövde: arka arkaya alanlar, her biri `F=<id:2HEX>.<tip:2HEX>,<uzunluk:HEX>:<değer baytları>`
Son bayt: gövdedeki tüm baytların **XOR**'u (checksum).

Tipler: `57`=W (2 bayt, little-endian), `4C`=L (4 bayt LE), `42`=B (n bayt LE), `4D`=M (1 bayt), `53`=S (metin, Windows-1254).

## Bilinen alanlar (AY ÇEKİRDEĞİ örneğinden)
| F | Tip | Anlam | Örnek |
|---|---|---|---|
| 01 | W | Reyon (DeptNo) | 1 |
| 02 | L | PLU no | 19 |
| 06 | L | Satış fiyatı × 100 (kuruş) | 24242 = 242,42 ₺ |
| 0B | L | Ürün kodu (ItemCode) | 9 |
| 10 | L | ? (AY için 373) | 373 |
| 19 | W | İçindekiler no (IngredientNo) | 20 |
| 0A | S | Ürün adı (Name1) | AY CEKİRDEGİ |
| 1E, 1F | S | (boş) | |
| diğerleri | | 0 | |

`10` alanının anlamı henüz kesin değil; genel çözüm için birkaç farklı ürünün gönderimi daha yakalanıp alanların ürüne göre nasıl değiştiği eşlenmeli.

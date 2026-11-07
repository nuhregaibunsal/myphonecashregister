# Fiyat Gör

Kuruyemiş dükkanı için telefondan fiyat sorgulama ve "ne kadar tuttu" hesaplama uygulaması. Kasaya gitmeden barkod okutup müşteriye tutarı söylemek için.

- Kamerayla barkod okuma (EAN-13, EAN-8, UPC, Code128)
- Terazi etiketlerini çözer (varsayılan: `27` + 5 hane PLU + 5 hane gram + kontrol hanesi; Ayarlar'dan değiştirilebilir)
- Etiketsiz kilolu ürünlerde gram sorar (100 gr, 250 gr, 500 gr, 1 kg kısayolları)
- Sepet toplamı, kalem silme ve düzeltme
- İnternetsiz çalışır, ürün listesi telefonda saklanır
- Android ve iPhone'da ana ekrana eklenerek uygulama gibi kullanılır

Uygulama kasaya ya da veritabanına hiçbir şey yazmaz, sadece okur.

## Ürün listesini çıkarma

Uygulama Excel (.xlsx/.xls), CSV/TXT veya JSON kabul eder. Sütunları otomatik tanımaya çalışır, tanıyamazsa elle seçilir.

### FasterPOS / Vega (SQL Server, .mdf)

Kasa bilgisayarında PowerShell açıp `araclar` klasörüne gidin:

```powershell
powershell -ExecutionPolicy Bypass -File .\disari-aktar.ps1
```

1. İlk çalıştırma veritabanlarını listeler.
2. `-Veritabani <ad> -Kesfet` ile barkod/fiyat içeren tabloları bulur ve `kesif.txt` dosyasına yazar.
3. Doğru tablo ya da sorgu belli olunca:

```powershell
powershell -ExecutionPolicy Bypass -File .\disari-aktar.ps1 -Veritabani VERITABANI_ADI -Sorgu "SELECT ... FROM ..."
```

`urunler.csv` dosyası oluşur.

Sunucu bulunamazsa `-Sunucu ".\SQLEXPRESS"` ekleyin. Windows girişi yetmezse `-Kullanici sa -Sifre ...` verin.

### CL Works Pro (terazi, .mdb)

Terazideki PLU numaralarını almak için:

```powershell
C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -File .\disari-aktar.ps1 -Mdb "C:\...\dosya.mdb" -Kesfet
```

Ardından `-Tablo` ya da `-Sorgu` ile dışa aktarın.

## Telefona yükleme

Kamera sadece `https` adresinde çalışır. Repo GitHub Pages ile yayınlanır (`.github/workflows/pages.yml`, `main` dalına gönderildiğinde çalışır):

1. GitHub'da repo Settings, ardından Pages, Source: **GitHub Actions**.
2. Verilen adresi telefonda açın.
3. Android Chrome'da menüden **Ana ekrana ekle** seçin. iPhone Safari'de Paylaş, ardından **Ana Ekrana Ekle** seçin.
4. Ayarlar sekmesinden `urunler.csv` dosyasını seçin (WhatsApp, e-posta ya da Drive ile telefona atılabilir) ve Kaydet'e basın.

Fiyatlar değiştiğinde betiği tekrar çalıştırıp dosyayı yeniden yükleyin.

Ürün listesi sadece telefonda saklanır. Sitede herhangi bir ürün ya da fiyat verisi bulunmaz.

## Klasörler

- `web/` uygulamanın kendisi (statik dosyalar)
- `araclar/disari-aktar.ps1` SQL Server ve MDB'den CSV çıkarma betiği

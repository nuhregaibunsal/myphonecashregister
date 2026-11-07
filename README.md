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

`araclar` klasörünü kasa bilgisayarına kopyalayıp `calistir.bat` dosyasına çift tıklayın.

- Betik SQL servislerini listeler, bulduğu tüm SQL Server'lara bağlanmayı dener ve her denemenin hatasını yazar.
- Windows girişiyle bağlanamazsa SQL kullanıcı adı ve şifresi sorar (boş geçilebilir).
- Hiç bağlanamazsa kasa programının ayar dosyalarında bağlantı bilgisi arar.
- Tek veritabanı varsa barkod/fiyat içeren tabloları doğrudan listeler.
- Ekrana yazılan her şey `rapor.txt` dosyasına kaydedilir ve pencere Enter'a basılana kadar kapanmaz.

Doğru tablo ya da sorgu belli olunca komut satırından:

```bat
calistir.bat -Veritabani VERITABANI_ADI -Sorgu "SELECT ... FROM ..."
```

`urunler.csv` dosyası oluşur. Ek seçenekler: `-Sunucu "PC\INSTANCE"`, `-Kullanici sa -Sifre ...`.

### CL Works Pro (terazi, .mdb)

Terazideki PLU numaralarını almak için:

```bat
calistir-32bit.bat -Mdb "C:\...\dosya.mdb" -Kesfet
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

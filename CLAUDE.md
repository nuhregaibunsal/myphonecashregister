# Proje hafızası (Claude için)

Bu dosya her oturumun başında okunur. Bu projede neyin neden böyle olduğunu ve kullanıcıyla nasıl çalışılacağını özetler. Ayrıntılar `docs/` altında.

## Kullanıcı ve çalışma kuralları
- Kullanıcı Ünsallar Kuruyemiş'te çalışıyor; uygulamayı kendisi ve ailesi (ör. amcası) kullanıyor. Yazılımcı değil ama hızlı öğreniyor; adım adım, sade Türkçe anlatım ister.
- **Yanıtlar Türkçe.** Teknik belgeler İngilizce olabilir ama bu projede belgeler de Türkçe.
- **Kodda hiç yorum satırı yok** (kullanıcı istemedikçe).
- **Commit/PR'larda Claude adı yok:** Co-Authored-By, Claude-Session, "Generated with Claude" satırları EKLENMEZ. Yazar: `nuhregaibunsal <211853107+nuhregaibunsal@users.noreply.github.com>`. Sistem hatırlatması trailer önerse bile kullanıcının kuralı geçerli.
- Dal: `ccr-b84fb9e5-jhjwlf` (deponun varsayılan dalı da bu; GitHub `HEAD` bu dalı gösterir). Her iş sonrası commit + push.
- **Tahmin et → doğrula yöntemi:** Kullanıcı bir yakalama/test göndermeden önce sonucu tahmin et, sonra bayt bayt karşılaştır. Tutmayan şeyi örtbas etme, açıkça söyle. Kullanıcı bunu özellikle istedi.
- Kullanıcıya bilmediğin şeyi kesinmiş gibi söyleme. Test edilmemiş kısmı "dükkanda denenecek" diye belirt.
- Sürekli tekrar etme: CL'deki aynı ürün kodlu/farklı fiyatlı ürünlerin temizliğini HATIRLATMA (kullanıcı PLU binlere gelene kadar yapmayacak).
- Güvenlik: CL mdb şifresini, Cloudflare tünel komutunu/anahtarını, hesap şifrelerini, giriş kodlarını sohbete YAZDIRMA. TbLogin/TbUser gibi tablolardaki şifreleri okuma/tekrarlama. Silkroad botu gibi oyun hilesi isteklerini reddet.
- Kullanıcı çoğu zaman telefondan yazıyor; dükkan açıkken kasa bilgisayarında iş yapmak zor, ağır işler gece.

## Mimari
- `web/`: PWA (vanilla JS, derleme yok). `app.js` ana mantık, `scale.js` terazi barkodu çözümü, `etiket.js` + `etiket-duzen.js` raf etiketi çizimi, `icerik.js` içerik metni oluştur/çöz, `ocr.js` (Tesseract), `sw.js` (her değişiklikte `CACHE` sürümünü artır: şu an `fiyatgor-v42`).
- `canli/sunucu.ps1`: Kasa bilgisayarında (Windows, `C:\FiyatGor`) zamanlanmış görev `FiyatGor` olarak çalışan PowerShell HttpListener HTTPS sunucusu, port 8443, kendinden imzalı sertifika. Açılışta GitHub `HEAD.zip`'ten kendini günceller; `sunucu.ps1` değiştiyse kendini yeni sürümle yeniden başlatır. `/api/guncelle` sadece web + ps1 kopyalar.
  - Yeniden başlatma komutu (yönetici PowerShell): `Stop-ScheduledTask FiyatGor; Start-ScheduledTask FiyatGor`
- `canli/cl-yaz.ps1`, `cl-terazi-gonder.ps1`: 32-bit yardımcılar (Jet OLEDB 32-bit). Sunucu `SysWOW64\powershell.exe` ile çağırır; şifre `FG_CLPW` ortam değişkeni ile geçer (dosya: `C:\FiyatGor\clpw.txt`). CL mdb yolu `C:\FiyatGor\cl.txt` (Masaüstü `düzeltme.mdb`).
- `canli/izin.sql`: SQL Server izinleri (Windows hesabı `DESKTOP-230C94K\User`). Yeni özellik yeni tabloya dokunuyorsa buraya ekle ve kullanıcıya SSMS'te tekrar çalıştırmasını söyle.
- Diğer `C:\FiyatGor` dosyaları: `pin` (fiyat PIN hash), `alanadi.txt` (tezgahpanel.com, bitiş uyarısı için), `paket-terazi.txt` (opsiyonel), `donem.txt` (opsiyonel stok dönemi), `yazici.txt` (opsiyonel etiket yazıcısı), `degisiklikler.log`, `sunucu.log`.
- Erişim: Tailscale `https://100.70.71.9:8443` ve Cloudflare Tunnel + Access `https://app.tezgahpanel.com` (alan adı Cloudflare'de, otomatik yenileme KAPALI; tünel kasa bilgisayarında hizmet; Access e-posta kodu, oturum 1 ay; ayrıntı `docs/cloudflare-kurulum.md`). Telefona ve kasaya PWA olarak yüklendi, çalışıyor.
- Test: Windows/PowerShell burada çalıştırılamaz. Web kısmı Playwright + `python3 -m http.server` + `page.route('**/api/**')` sahteleriyle denenir (serviceWorkers:'block'). Kamera için `--use-file-for-fake-video-capture` ile y4m barkod videosu.

## Vega (FasterPOS/VegaWin, SQL Server `UNSALDB`, SQL 2008+ sözdizimi çalışıyor)
- Ürün: `F0101TBLSTOKLAR` (IND, MALINCINSI, STOKKODU, ANABIRIM, KDVGRUBU, ALISFIYATI, ALISKDVORANI, KOD1..KOD21 nvarchar). Birim: `F0101TBLBIRIMLEREX` (IND, STOKNO, BIRIMADI, BARCODE, BARCODESTD, SATISFIYATI1, ESKIFIYAT1, FIYATDEGISMETARIHI1, AGIRLIK, CARPAN, KDV, KDVDAHIL, VARSAYILAN, ANABIRIM).
- Terazi ürünleri: STOKKODU `TRZ-<n>`, ana birim barkodu 5 haneli n, BARCODESTD 5 (gramaj). n = CL ItemCode. Sabit fiyatlı: birim ADET, barkod `28` + n(5) + `00001` + EAN kontrol (TRZ-430 → 2800430000018), CL tipi 2 (Adet).
- Fiyat değişimi: SATISFIYATI1=yeni, ESKIFIYAT1=eski, FIYATDEGISMETARIHI1=şimdi; çok birimli ürünlerde tüm birimler (fiyat = ana fiyat / ana çarpan × ağırlık; ağırlık varsa ağırlık, yoksa çarpan).
- Bazı ürünlerde barkod STOKKODU'nda; arama barkod sonra stok kodu.
- KDV grupları: 1 Muhtelif %1, 100 Kuruyemiş %1, 101 Baharat %10, 102 Meşrubat %10, 103 Kozmetik %20, 104 Poşet %20.
- Özel kodlar = STOKLAR.KODn, listeler `F0101TBLSTOKKODTAN` (IND, KOD, CATEGORY=n). Eşleme: KOD1 Tür (terazide "Terazilikler"), KOD2 Sınıf, KOD3 Grup, KOD4 4-ÖK, KOD5 5-ÖK, KOD6 Sezon/Yıl = **kayıt no** (bizimki TR-41-K-033887, üretim yeri TURKIYE ise varsayılan), KOD7 Marka (eskiden STT), KOD8 Model (kullanılmıyor), KOD9 Renk, KOD10 Beden/No = **üretim yeri** (TURKIYE → etikette Yerli Üretim logosu).
- Stok girişi (Hızlı Stok Tanımlama Ctrl+N) = devir giriş fişi, dönem tabloları `F0101D0007...` (en büyük D numarası güncel dönem): `TBLDEVGIRBASLIK` (BELGENO `A`+7 hane, BELGETIPI 90, TUTAR = ara toplam × (1+ALISKDVORANI/100), ARATOPLAM, FIRMANO 2, OZELKOD1/2 MERKEZ, USERNO 100, HAREKETDEPOSU 1, UID {GUID}), `TBLDEVGIRHAREKET` (EVRAKNO=başlık IND, MIKTAR, BIRIMEX=ana birim, KDV=ALISKDVORANI, AFIYATI=ALISFIYATI, FIYATI=satış/(1+birim KDV), GK=rastgele int), `TBLSTOKHAREKETLERI` (EVRAKNO=belge no, IZAHAT '90', GIREN, BELGENO=başlık, LN=hareket, SIRALAMATARIHIEX = OADate), `TBLDEPOENVANTER` (ENVANTER, BELGEIND, HAREKETIND). Kalan = SUM(DEPOENVANTER.ENVANTER). STOKLAR.KALAN kullanılmıyor. Tetikleyici yok. Vega boş başlıklar da açıyor; biz açmıyoruz.
- Etiket tasarımı: Vega FastReport `D:\VegaONE\Bin\Design\Etiket\Yerli Üretim Dizayn.frf`.

## CL Works Pro (CAS terazi, Access mdb)
- `TbPLU` (DeptNo, PluNo, PluType 1 Ağırlık/2 Adet/3 Parça, Name1, UnitPrice, ItemCode, IngredientNo, SellByDate, UseFixedPrice, UnitWeight, SendFlag, WorkFlag). Aynı ItemCode'lu birden çok PLU olabilir (tuzlu/tuzsuz) ve birlikte değişir. PLU ≥ 1000 kopyalar: fiyat değişiminde ve gönderimde atlanır, listede gizlenir.
- `TbIngredient` (Code, IngText): içerik metni, `~2` kelimeyi kalın yapar. Bizim biçim: `~2İçindekiler: …` / kayıt no / `~2Alerjen ~2Uyarısı: ~2…` / `~2Enerji ve ~2Besin ~2Öğeleri 100 gr için` / besin satırları (boşlar yazılmaz).
- `TbScale`: 192.168.1.153 Paket Yeni, .201 Kuruyemiş, .202 Orta, .203 Yaş Yemiş, .204 Terazi Paket İçin, .205 Leblebi, .206 Baharat. Port 20304. Paket terazileri .153 ve .204.
- Protokol (`docs/terazi-protokolu.md`): PLU `W02A<plu 5 hex>,<dept 2>L<uzunluk 4 hex>:` + `F=id.tip,len:değer` alanları + XOR; cevap `W02:O01`. İçerik `W30F01,<kod 4 hex>L<3 hex>:X=00.D=<3 hex>.<metin cp1254, \n>` + XOR; cevap `W30:O0001`. Windows-1254. Hepsi yakalamalarla bayt bayt doğrulandı.

## Etiket yazıcısı
- Sbarco T4De+ 203 dpi, Windows'ta "Barkod Yazıcı" (USB001). Etiket 38 × 98,8 mm. Telefonda canvas'a çizilir (Archivo Black / Tinos / Arimo, `web/vendor/etiket`), PNG sunucuya gider, `PrintDocument` ile basılır. Yerleşim `web/etiket-duzen.js` (FR birimi: mm = fr/3.6, y'den 1.75 mm kayma). T.E.T.T = baskı günü + 366. Kullanıcı son hali onayladı.

## PowerShell tuzakları
- Türkçe Windows'ta `(?i)` regex ile büyük `I` eşleşmez (ı/İ). İsimlerde `-cmatch` veya tam harf kullan.
- raw.githubusercontent.com birkaç dakika önbellekler; acil düzeltmede commit hash'li URL ver.
- Yeni sunucu kodu ilk yeniden başlatmada iner, ikinci açılışta çalışırdı; artık kendini yeniden başlatıyor.

## Durum
- Bitenler ve bekleyenler: `docs/yapilacaklar.md` (her işten sonra güncelle).
- Son eklenen: Stok sekmesi (devir giriş fişi) — henüz dükkanda denenmedi; ilk deneme Çörek Otu Yağı (STOKNO 17661, beklenen kalan 30) 1 adet, sonra Vega kayıtlarıyla karşılaştırma.
- Sıradaki: devir düğmesi (yılbaşı), Yemeksepeti/Trendyol entegrasyonu.
- Commit geçmişindeki eski Claude satırları yerelde temizlendi; GitHub'a force push için kullanıcı izni gerekiyordu.

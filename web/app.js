(function () {
  const $ = id => document.getElementById(id);
  const tl = n => (Number(n) || 0).toLocaleString("tr-TR", { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + " ₺";
  const kgFmt = n => (Number(n) || 0).toLocaleString("tr-TR", { maximumFractionDigits: 3 });
  const lower = s => String(s || "").toLocaleLowerCase("tr-TR");

  const store = {
    get(key, def) {
      try { const v = localStorage.getItem(key); return v == null ? def : JSON.parse(v); } catch (e) { return def; }
    },
    set(key, val) {
      try { localStorage.setItem(key, JSON.stringify(val)); return true; } catch (e) { return false; }
    }
  };

  const DB_NAME = "fiyatgor";
  function idb() {
    return new Promise((res, rej) => {
      const r = indexedDB.open(DB_NAME, 1);
      r.onupgradeneeded = () => r.result.createObjectStore("kv");
      r.onsuccess = () => res(r.result);
      r.onerror = () => rej(r.error);
    });
  }
  async function idbGet(key) {
    const db = await idb();
    return new Promise((res, rej) => {
      const r = db.transaction("kv").objectStore("kv").get(key);
      r.onsuccess = () => res(r.result);
      r.onerror = () => rej(r.error);
    });
  }
  async function idbSet(key, val) {
    const db = await idb();
    return new Promise((res, rej) => {
      const tx = db.transaction("kv", "readwrite");
      tx.objectStore("kv").put(val, key);
      tx.oncomplete = () => res();
      tx.onerror = () => rej(tx.error);
    });
  }

  let products = [];
  let byBarcode = new Map();
  let byStokKodu = new Map();
  let meta = { updated: null, source: "" };
  let settings = Object.assign({}, Scale.DEFAULTS, store.get("scaleSettings", {}));
  if (settings.unknownScale === "price") settings.unknownScale = "ocr";
  const round2 = n => Math.round((Number(n) || 0) * 100) / 100;
  let busy = false;
  let basket = store.get("basket", []);

  function index() {
    byBarcode = new Map();
    byStokKodu = new Map();
    products.forEach(p => {
      String(p.barkod || "").split(/[;,|\s]+/).map(Scale.normCode).filter(Boolean).forEach(b => byBarcode.set(b, p));
      const k = String(p.kod || "").trim();
      if (/^\d{6,14}$/.test(k) && !byStokKodu.has(k)) byStokKodu.set(k, p);
    });
  }

  async function loadProducts() {
    try {
      const data = await idbGet("products");
      if (data) { products = data.products || []; meta = data.meta || meta; }
    } catch (e) { }
    index();
    renderInfo();
  }

  async function saveProducts() {
    await idbSet("products", { products, meta });
    try { if (navigator.storage && navigator.storage.persist) await navigator.storage.persist(); } catch (e) { }
    index();
    renderInfo();
  }

  let live = false, liveTimer = null;

  let baglantiHata = null, liveHazir = false, tekrarTimer = null;
  const canliOrtam = () => /^https?:$/.test(location.protocol) && !/github\.io$/i.test(location.hostname);

  function hataSinifla(h) {
    const kod = h && h.kod ? " · kod " + h.kod : "";
    if (h.tip === "oturum") return { baslik: "Oturumun süresi dolmuş", aciklama: "Sayfayı yenileyip e-posta koduyla yeniden giriş yap.", dugme: "Yeniden giriş", alt: "" };
    if (h.tip === "zaman") return { baslik: "Kasa bilgisayarı yanıt vermiyor", aciklama: "Bilgisayar meşgul ya da çok yavaş. Birazdan kendiliğinden tekrar denenecek.", alt: "zaman aşımı" };
    if (h.tip === "ag") return navigator.onLine === false
      ? { baslik: "İnternet bağlantısı yok", aciklama: "Telefonun Wi-Fi ya da mobil verisini kontrol et.", alt: "çevrimdışı" }
      : { baslik: "Kasa bilgisayarına ulaşılamıyor", aciklama: "Bilgisayar kapalı, internetten kopmuş ya da sunucu çalışmıyor olabilir.", alt: "ağ hatası" };
    if (h.tip === "sql") return { baslik: "Kasa veritabanına bağlanılamadı", aciklama: "Vega'nın veritabanı (SQL Server) kapalı olabilir." + (h.mesaj ? " Ayrıntı: " + h.mesaj : ""), alt: "kod " + h.kod };
    const k = Number(h.kod) || 0;
    if (k === 401 || k === 403) return { baslik: "Oturumun süresi dolmuş", aciklama: "Sayfayı yenileyip e-posta koduyla yeniden giriş yap.", dugme: "Yeniden giriş", alt: "kod " + k };
    if (k === 504 || k === 524) return { baslik: "Kasa bilgisayarı geç yanıt veriyor", aciklama: "Sunucu çalışıyor ama yanıt vermesi uzun sürdü. Birazdan tekrar denenecek.", alt: "kod " + k };
    if (k >= 500) return { baslik: "Kasa bilgisayarına ulaşılamıyor", aciklama: "Sunucu kapalı ya da yeniden başlıyor olabilir. Bilgisayarın açık olduğundan emin ol.", alt: "kod " + k };
    return { baslik: "Bağlantı hatası", aciklama: "Kasa bilgisayarından ürün listesi alınamadı.", alt: k ? "kod " + k : "" };
  }

  function baglantiGoster() {
    const el = $("baglanti");
    if (!baglantiHata || !canliOrtam()) { el.hidden = true; return; }
    const m = hataSinifla(baglantiHata);
    $("bgBaslik").textContent = m.baslik;
    $("bgAciklama").textContent = m.aciklama;
    const son = meta.updated && products.length ? "Fiyatlar telefondaki son listeden gösteriliyor (" + new Date(meta.updated).toLocaleString("tr-TR", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" }) + ")" : "Telefonda kayıtlı ürün listesi yok";
    $("bgAlt").textContent = son + (m.alt ? " · " + m.alt : "");
    $("bgDugme").textContent = m.dugme || "Tekrar dene";
    $("bgDugme").onclick = m.dugme ? () => location.reload() : () => { $("bgDugme").disabled = true; startLive().finally(() => { $("bgDugme").disabled = false; }); };
    el.hidden = false;
  }

  async function syncLive() {
    if (!/^https?:$/.test(location.protocol)) return false;
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 10000);
    try {
      let res;
      try { res = await apiFetch("api/urunler", { cache: "no-store", signal: ctrl.signal }); }
      catch (err) { throw { tip: err && err.name === "AbortError" ? "zaman" : "ag" }; }
      const json = /json/.test(res.headers.get("content-type") || "");
      if (!res.ok) {
        const j = json ? await res.json().catch(() => null) : null;
        if (res.status === 401 && j && j.giris) throw { tip: "giris" };
        throw j && j.error ? { tip: "sql", kod: res.status, mesaj: j.error } : { tip: "http", kod: res.status };
      }
      if (!json) throw { tip: "oturum", kod: res.status };
      const data = await res.json();
      if (!Array.isArray(data.products)) throw { tip: "http", kod: res.status };
      products = data.products.map(p => ({
        barkod: Scale.normCode(p.barkod),
        ad: String(p.ad || "").trim(),
        fiyat: round2(p.fiyat),
        birim: String(p.birim || "").trim().toUpperCase(),
        plu: Scale.normCode(p.plu),
        birimind: Number(p.birimind) || 0,
        kod: String(p.kod || "").trim()
      })).filter(p => p.ad);
      meta = { updated: data.updated || Date.now(), source: "Kasa bilgisayarı, canlı" };
      live = true;
      baglantiHata = null;
      baglantiGoster();
      await saveProducts();
      renderInfo();
      if ($("tab-terazi").classList.contains("active")) renderTerazi(true);
      return true;
    } catch (e) {
      if (e && e.tip === "giris") {
        live = false;
        baglantiHata = null;
        baglantiGoster();
        if ($("giris").hidden) girisGoster();
        return false;
      }
      baglantiHata = e && e.tip ? e : { tip: "ag" };
      live = false;
      renderInfo();
      baglantiGoster();
      return false;
    } finally {
      clearTimeout(t);
    }
  }

  let me = null, girisKurulum = false;
  const can = k => !!(me && me.giris && (me.rol === "yonetici" || (me.yetkiler || []).includes(k)));
  const fiyatSekmesi = () => can("fiyat") || can("etiket") || can("ekle");

  async function apiFetch(url, opt) {
    const res = await fetch(url, Object.assign({ credentials: "same-origin" }, opt || {}));
    if (res.status === 401 && !/^api\/(giris|kurulum|ben|cikis)/.test(String(url))) {
      res.clone().json().then(j => { if (j && j.giris) girisGoster(); }).catch(() => { });
    }
    return res;
  }

  async function loadRights() {
    try {
      const res = await fetch("api/ben", { cache: "no-store", credentials: "same-origin" });
      if (!/json/.test(res.headers.get("content-type") || "")) return "hata";
      const j = await res.json();
      if (!j || !j.ok) return "hata";
      girisKurulum = !!j.kurulum;
      me = j.giris ? j : null;
      return j.giris ? "ok" : "giris";
    } catch (e) { return "hata"; }
  }

  function gMsg(text, kind) {
    $("gMsg").textContent = text || "";
    $("gMsg").className = "msg " + (kind || "");
  }

  function girisGoster() {
    me = null;
    live = false;
    baglantiHata = null;
    $("baglanti").hidden = true;
    const k = girisKurulum;
    $("girisAlt").textContent = k ? "İlk yönetici hesabını oluştur" : "Devam etmek için hesabınla giriş yap.";
    $("gAdL").hidden = !k;
    $("gSifre2L").hidden = !k;
    $("gPinL").hidden = !k;
    $("gBtn").textContent = k ? "Hesabı oluştur" : "Giriş yap";
    $("gSifre").autocomplete = k ? "new-password" : "current-password";
    gMsg("");
    $("giris").hidden = false;
    setTimeout(() => { try { (k ? $("gAd") : $("gEposta")).focus(); } catch (e) { } }, 50);
  }

  async function girisGonder(e) {
    e.preventDefault();
    const eposta = $("gEposta").value.trim();
    const sifre = $("gSifre").value;
    if (!eposta || !sifre) { gMsg("E-posta ve şifreyi yaz.", "err"); return; }
    let url = "api/giris", body = { eposta, sifre };
    if (girisKurulum) {
      const ad = $("gAd").value.trim();
      const pin = $("gPin").value.trim();
      if (!ad) { gMsg("Adını yaz.", "err"); return; }
      if (sifre.length < 8) { gMsg("Şifre en az 8 karakter olmalı.", "err"); return; }
      if (sifre !== $("gSifre2").value) { gMsg("İki şifre aynı değil.", "err"); return; }
      if (!pin) { gMsg("Mevcut PIN'i yaz.", "err"); return; }
      url = "api/kurulum";
      body = { eposta, ad, sifre, pin };
    }
    $("gBtn").disabled = true;
    gMsg("Bekleyin…");
    try {
      const res = await apiFetch(url, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
      const j = await res.json().catch(() => ({}));
      if (res.ok && j.ok && j.giris) {
        ["gSifre", "gSifre2", "gPin"].forEach(id => { $(id).value = ""; });
        me = j;
        girisKurulum = false;
        $("giris").hidden = true;
        gMsg("");
        if (!liveHazir) startLive(); else { updatePriceTab(); syncLive(); }
      } else {
        gMsg(j.error || ("Giriş yapılamadı (" + res.status + ")"), "err");
      }
    } catch (err) {
      gMsg("Kasa bilgisayarına ulaşılamadı.", "err");
    }
    $("gBtn").disabled = false;
  }

  async function cikisYap() {
    try { await apiFetch("api/cikis", { method: "POST" }); } catch (e) { }
    location.reload();
  }

  function sfMsg(text, kind) {
    $("sfMsg").textContent = text || "";
    $("sfMsg").className = "msg " + (kind || "");
  }

  async function sifreDegistir(e) {
    e.preventDefault();
    const eski = $("sfEski").value, yeni = $("sfYeni").value;
    if (!eski) { sfMsg("Mevcut şifreni yaz.", "err"); return; }
    if (yeni.length < 8) { sfMsg("Yeni şifre en az 8 karakter olmalı.", "err"); return; }
    if (yeni !== $("sfYeni2").value) { sfMsg("İki yeni şifre aynı değil.", "err"); return; }
    sfMsg("Kaydediliyor…");
    try {
      const res = await apiFetch("api/sifrem", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ eski, yeni }) });
      const j = await res.json().catch(() => ({}));
      if (res.ok && j.ok) {
        $("sifreForm").reset();
        $("sifreForm").hidden = true;
        sfMsg("Şifre değişti.", "ok");
      } else sfMsg(j.error || ("Değiştirilemedi (" + res.status + ")"), "err");
    } catch (err) {
      sfMsg("Kasa bilgisayarına ulaşılamadı.", "err");
    }
  }

  const IZINLER = [["fiyat", "Fiyat değiştirme"], ["ekle", "Ürün ekleme ve düzenleme"], ["stok", "Stok girişi"], ["etiket", "Etiket basma"], ["icerik", "İçerik"], ["devir", "Dönem devri"]];
  const ROL_AD = { yonetici: "Yönetici", kullanici: "Kullanıcı" };
  let kulListe = [], kdEposta = "";

  function yetkiKutulari(box, secili, rol) {
    box.innerHTML = "";
    IZINLER.forEach(([k, ad]) => {
      const l = document.createElement("label");
      l.className = "check";
      l.innerHTML = '<input type="checkbox"> <span></span>';
      l.querySelector("span").textContent = ad;
      const c = l.querySelector("input");
      c.value = k;
      c.checked = rol === "yonetici" || (secili || []).includes(k);
      c.disabled = rol === "yonetici";
      box.appendChild(l);
    });
  }

  function yetkiKilidi(box, rol) {
    box.querySelectorAll("input").forEach(c => { c.disabled = rol === "yonetici"; if (rol === "yonetici") c.checked = true; });
  }

  const yetkiOku = box => [...box.querySelectorAll("input:checked")].map(c => c.value);

  function kulMsg(text, kind) {
    $("kulMsg").textContent = text || "";
    $("kulMsg").className = "msg " + (kind || "");
  }

  async function kullanicilariYukle() {
    try {
      const res = await apiFetch("api/kullanicilar", { cache: "no-store" });
      const j = await res.json().catch(() => ({}));
      if (!res.ok || !j.ok) { kulMsg(j.error || ("Kullanıcılar okunamadı (" + res.status + ")"), "err"); return; }
      kulListe = j.kullanicilar || [];
      kullaniciCiz();
    } catch (e) { kulMsg("Kullanıcılar okunamadı.", "err"); }
  }

  function kullaniciCiz() {
    const ul = $("kulListe");
    ul.innerHTML = "";
    kulListe.forEach(u => {
      const li = document.createElement("li");
      li.innerHTML = '<div class="info"><b></b><span class="muted small kul-ep"></span><div class="kul-etiketler"></div></div><div class="kul-islem"></div>';
      li.querySelector("b").textContent = u.ad;
      li.querySelector(".kul-ep").textContent = u.eposta;
      const tags = li.querySelector(".kul-etiketler");
      const tag = (t, c) => { const sp = document.createElement("span"); sp.className = "kul-etiket " + (c || ""); sp.textContent = t; tags.appendChild(sp); };
      tag(ROL_AD[u.rol] || u.rol, "rol");
      if (!u.aktif) tag("Pasif", "pasif");
      if (u.rol === "yonetici") tag("Tüm yetkiler");
      else IZINLER.filter(([k]) => (u.yetkiler || []).includes(k)).forEach(([, ad]) => tag(ad));
      const isl = li.querySelector(".kul-islem");
      const dugme = (ad, fn, cls) => { const b = document.createElement("button"); b.type = "button"; b.className = "btn" + (cls ? " " + cls : ""); b.textContent = ad; b.onclick = fn; isl.appendChild(b); };
      dugme("Düzenle", () => kulDuzenleAc(u));
      dugme("Şifre sıfırla", () => kulSifreSifirla(u));
      if (me && u.eposta !== me.eposta) dugme("Sil", () => kulSil(u), "danger");
      ul.appendChild(li);
    });
  }

  async function kulIstek(body) {
    const res = await apiFetch("api/kullanicilar", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
    const j = await res.json().catch(() => ({}));
    return { ok: res.ok && j.ok, hata: j.error || ("İşlem yapılamadı (" + res.status + ")") };
  }

  async function kulEkle(e) {
    e.preventDefault();
    const ad = $("kfAd").value.trim(), eposta = $("kfEposta").value.trim(), sifre = $("kfSifre").value;
    const msg = (t, k) => { $("kfMsg").textContent = t || ""; $("kfMsg").className = "msg " + (k || ""); };
    if (!ad) { msg("Adı yaz.", "err"); return; }
    if (!eposta.includes("@")) { msg("E-postayı doğru yaz.", "err"); return; }
    if (sifre.length < 8) { msg("Şifre en az 8 karakter olmalı.", "err"); return; }
    msg("Ekleniyor…");
    try {
      const r = await kulIstek({ islem: "ekle", eposta, ad, sifre, rol: $("kfRol").value, yetkiler: yetkiOku($("kfYetkiler")) });
      if (!r.ok) { msg(r.hata, "err"); return; }
      $("kulForm").reset();
      yetkiKutulari($("kfYetkiler"), [], "kullanici");
      msg(ad + " eklendi.", "ok");
      kullanicilariYukle();
    } catch (err) { msg("Kasa bilgisayarına ulaşılamadı.", "err"); }
  }

  function kulDuzenleAc(u) {
    kdEposta = u.eposta;
    $("kdBaslik").textContent = u.eposta;
    $("kdAd").value = u.ad;
    $("kdRol").value = u.rol;
    $("kdAktif").checked = !!u.aktif;
    yetkiKutulari($("kdYetkiler"), u.yetkiler, u.rol);
    $("kdMsg").textContent = "";
    $("kulDuzenle").showModal();
  }

  async function kulDuzenleKaydet(e) {
    e.preventDefault();
    $("kdMsg").textContent = "Kaydediliyor…";
    $("kdMsg").className = "msg";
    try {
      const r = await kulIstek({ islem: "guncelle", eposta: kdEposta, ad: $("kdAd").value.trim(), rol: $("kdRol").value, yetkiler: yetkiOku($("kdYetkiler")), aktif: $("kdAktif").checked });
      if (!r.ok) { $("kdMsg").textContent = r.hata; $("kdMsg").className = "msg err"; return; }
      $("kulDuzenle").close();
      kulMsg("Kullanıcı güncellendi.", "ok");
      kullanicilariYukle();
    } catch (err) { $("kdMsg").textContent = "Kasa bilgisayarına ulaşılamadı."; $("kdMsg").className = "msg err"; }
  }

  async function kulSifreSifirla(u) {
    const sifre = prompt(u.ad + " için yeni şifre (en az 8 karakter):");
    if (sifre === null) return;
    if (sifre.length < 8) { kulMsg("Şifre en az 8 karakter olmalı.", "err"); return; }
    try {
      const r = await kulIstek({ islem: "sifre", eposta: u.eposta, sifre });
      kulMsg(r.ok ? u.ad + " için şifre sıfırlandı, açık oturumları kapandı." : r.hata, r.ok ? "ok" : "err");
    } catch (err) { kulMsg("Kasa bilgisayarına ulaşılamadı.", "err"); }
  }

  async function kulSil(u) {
    if (!confirm(u.ad + " (" + u.eposta + ") hesabı silinsin mi?")) return;
    try {
      const r = await kulIstek({ islem: "sil", eposta: u.eposta });
      kulMsg(r.ok ? u.ad + " silindi." : r.hata, r.ok ? "ok" : "err");
      if (r.ok) kullanicilariYukle();
    } catch (err) { kulMsg("Kasa bilgisayarına ulaşılamadı.", "err"); }
  }

  function hesapCiz() {
    const g = !!(me && me.giris);
    $("hesapCard").hidden = !g;
    $("kullaniciCard").hidden = !(g && me.rol === "yonetici");
    if (!g) return;
    $("hesapAd").textContent = me.ad;
    $("hesapEposta").textContent = me.eposta;
    if (me.rol === "yonetici") kullanicilariYukle();
  }

  let priceSel = null;
  const priceLog = [];

  const MENU = [["hesap", "🧮 Hesap", false], ["sorgu", "🔎 Sorgu", false], ["urunler", "📋 Ürünler", false], ["terazi", "⚖️ Terazi", false], ["fiyat", "₺ Fiyat", ["fiyat", "etiket", "ekle"]], ["ekle", "＋ Ekle", ["ekle"]], ["stok", "📦 Stok", ["stok"]], ["icerik", "🥜 İçerik", ["icerik"]]];

  const sekmeIzinli = yetki => !yetki || yetki.some(can);

  function menuUygula() {
    const gizli = store.get("gizliSekmeler", []);
    MENU.forEach(([k, , yetki]) => {
      const b = document.querySelector('.tabs button[data-tab="' + k + '"]');
      if (b) b.hidden = !sekmeIzinli(yetki) || gizli.includes(k);
    });
    const aktif = document.querySelector(".tabs button.active");
    if (aktif && aktif.hidden) switchTab("ayarlar");
  }

  function menuAyarKur() {
    const box = $("menuAyar");
    box.innerHTML = "";
    const gizli = store.get("gizliSekmeler", []);
    MENU.forEach(([k, ad, yetki]) => {
      if (!sekmeIzinli(yetki)) return;
      const l = document.createElement("label");
      l.className = "check";
      l.innerHTML = '<input type="checkbox"> <span></span>';
      l.querySelector("span").textContent = ad;
      const c = l.querySelector("input");
      c.checked = !gizli.includes(k);
      c.onchange = () => {
        const g = store.get("gizliSekmeler", []).filter(x => x !== k);
        if (!c.checked) g.push(k);
        store.set("gizliSekmeler", g);
        menuUygula();
      };
      box.appendChild(l);
    });
  }

  let ogrAktif = null;
  let ogrBasladi = false;

  function ogrAdimlar() {
    const nav = k => '.tabs button[data-tab="' + k + '"]';
    const ad = me && me.ad ? me.ad : "";
    let fiyatMetin = "";
    if (can("fiyat")) fiyatMetin += "Ürün fiyatını değiştirebilirsin. Değişen fiyat kasaya ve terazilere gider. ";
    else fiyatMetin += "Ürünlerin fiyatına buradan bakarsın. ";
    if (can("etiket")) fiyatMetin += "Raf etiketi de basabilirsin.";
    const tum = [
      { baslik: ad ? "Hoş geldin " + ad : "Hoş geldin", metin: "Bu uygulamayla barkod okutup ürünün fiyatını görürsün. Aldığın ürünleri sepete ekleyip toplamı hesaplarsın. Şimdi kısaca gezelim." },
      { hedef: "#startScan", baslik: "Barkod Okut", metin: "Buna basınca kamera açılır. Okuttuğun ürün sepete eklenir." },
      { hedef: "#manualInput", baslik: "Elle yaz", metin: "Barkodu elle yazabilirsin. Ürünün adını yazıp da arayabilirsin. Terazi ürünleri listenin en üstünde çıkar." },
      { hedef: ".totalbar", baslik: "Toplam tutar", metin: "Sepetin toplamı burada yazar. Temizle düğmesi sepeti boşaltır." },
      { hedef: nav("sorgu"), baslik: "Fiyat Sorgu", metin: "Kamera açık kalır. Okuttuğun ürünün fiyatı büyük yazılır. Müşteriye göstermek için çok iyidir." },
      { hedef: nav("urunler"), baslik: "Ürünler", metin: "Bütün ürünlerin listesi burada. Arayıp ürüne dokunursan sepete eklenir." },
      { hedef: nav("terazi"), baslik: "Terazi", metin: "Terazi ürünleri burada. Solda terazideki PLU numarası, yanında adı ve fiyatı yazar." + (fiyatSekmesi() ? " Ürüne dokunursan fiyatını değiştirebilirsin." : "") },
      { hedef: nav("fiyat"), baslik: "Fiyat", metin: fiyatMetin },
      { hedef: nav("ekle"), baslik: "Ekle", metin: "Listede olmayan yeni bir ürünü buradan eklersin." },
      { hedef: nav("stok"), baslik: "Stok", metin: "Dükkana gelen malın adedini buradan yazarsın. Stok kendiliğinden artar." },
      { hedef: nav("icerik"), baslik: "İçerik", metin: "Terazi etiketlerinde çıkan içindekiler ve alerjen yazılarını buradan düzenlersin." },
      { hedef: nav("ayarlar"), baslik: "Ayarlar", metin: "Şifreni buradan değiştirirsin. Çıkış da burada. Alt menüde hangi sekmelerin görüneceğini seçebilirsin. Bu öğreticiyi de buradan tekrar açarsın." },
      { baslik: "Hazırsın", metin: "Bir şey yanlış giderse yöneticiye sor. İyi çalışmalar!" }
    ];
    return tum.filter(s => {
      if (!s.hedef) return true;
      const el = document.querySelector(s.hedef);
      if (!el || el.hidden) return false;
      const r = el.getBoundingClientRect();
      return r.width > 0 && r.height > 0;
    });
  }

  function ogrBitir() {
    const o = ogrAktif;
    if (!o) return;
    ogrAktif = null;
    window.removeEventListener("resize", o.yerles);
    window.removeEventListener("orientationchange", o.yerles);
    window.removeEventListener("scroll", o.yerles, true);
    document.removeEventListener("keydown", o.tus, true);
    o.kat.remove();
    window.scrollTo(0, o.scrollY);
    if (me && me.eposta) store.set("ogretici:" + me.eposta, true);
    if (o.onceki && o.onceki.focus) { try { o.onceki.focus(); } catch (e) { } }
  }

  function ogrBaslat() {
    if (ogrAktif || !me || !me.giris) return;
    const giris = $("giris");
    if (giris && !giris.hidden) return;
    switchTab("hesap");
    const adimlar = ogrAdimlar();
    if (!adimlar.length) return;

    const kat = document.createElement("div");
    kat.className = "ogr";
    kat.innerHTML = '<div class="ogr-dim"></div><div class="ogr-spot"></div>' +
      '<div class="ogr-kart" role="dialog" aria-modal="true" aria-labelledby="ogrBaslik">' +
      '<div class="ogr-ust"><b id="ogrBaslik"></b><span class="muted small ogr-say"></span></div>' +
      '<p class="ogr-metin" aria-live="polite"></p>' +
      '<div class="ogr-alt"><button class="btn sm ogr-atla" type="button">Atla</button><span class="ogr-bos"></span>' +
      '<button class="btn sm ogr-geri" type="button">Geri</button><button class="btn sm primary ogr-ileri" type="button">İleri</button></div></div>';
    document.body.appendChild(kat);

    const dim = kat.querySelector(".ogr-dim");
    const spot = kat.querySelector(".ogr-spot");
    const kart = kat.querySelector(".ogr-kart");
    const bas = kat.querySelector("#ogrBaslik");
    const say = kat.querySelector(".ogr-say");
    const metin = kat.querySelector(".ogr-metin");
    const atla = kat.querySelector(".ogr-atla");
    const geri = kat.querySelector(".ogr-geri");
    const ileri = kat.querySelector(".ogr-ileri");
    let i = 0;

    function yerles() {
      const s = adimlar[i];
      const vw = document.documentElement.clientWidth;
      const vh = window.innerHeight;
      const m = 12;
      const gen = Math.min(340, vw - 2 * m);
      kart.style.width = gen + "px";
      const kh = kart.offsetHeight;
      const el = s.hedef ? document.querySelector(s.hedef) : null;
      const r = el ? el.getBoundingClientRect() : null;
      if (!r || !r.width || !r.height) {
        dim.hidden = false;
        spot.hidden = true;
        kart.style.left = Math.max(m, (vw - gen) / 2) + "px";
        kart.style.top = Math.max(m, (vh - kh) / 2) + "px";
        return;
      }
      dim.hidden = true;
      spot.hidden = false;
      const p = 6;
      const x = Math.max(0, r.left - p), y = Math.max(0, r.top - p);
      const w = Math.min(vw, r.right + p) - x, h = Math.min(vh, r.bottom + p) - y;
      spot.style.left = x + "px";
      spot.style.top = y + "px";
      spot.style.width = w + "px";
      spot.style.height = h + "px";
      const alt = vh - (y + h) - m, ust = y - m;
      let top;
      if (alt >= kh + 8) top = y + h + 8;
      else if (ust >= kh + 8) top = y - kh - 8;
      else top = alt >= ust ? vh - kh - m : m;
      top = Math.min(Math.max(m, top), Math.max(m, vh - kh - m));
      let left = r.left + r.width / 2 - gen / 2;
      left = Math.min(Math.max(m, left), vw - gen - m);
      kart.style.left = left + "px";
      kart.style.top = top + "px";
    }

    function goster() {
      const s = adimlar[i];
      bas.textContent = s.baslik;
      metin.textContent = s.metin;
      say.textContent = (i + 1) + " / " + adimlar.length;
      geri.hidden = i === 0;
      ileri.textContent = i === adimlar.length - 1 ? "Bitir" : "İleri";
      const el = s.hedef ? document.querySelector(s.hedef) : null;
      if (el) el.scrollIntoView({ block: "center" });
      yerles();
      requestAnimationFrame(yerles);
      setTimeout(yerles, 250);
      ileri.focus();
    }

    function tus(e) {
      if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); ogrBitir(); return; }
      if (e.key === "Tab") {
        const d = [atla, geri, ileri].filter(b => !b.hidden);
        const k = d.indexOf(document.activeElement);
        e.preventDefault();
        d[(k + (e.shiftKey ? d.length - 1 : 1)) % d.length].focus();
      }
    }

    atla.onclick = () => ogrBitir();
    geri.onclick = () => { if (i > 0) { i--; goster(); } };
    ileri.onclick = () => { if (i >= adimlar.length - 1) ogrBitir(); else { i++; goster(); } };

    ogrAktif = { kat, yerles, tus, scrollY: window.scrollY, onceki: document.activeElement };
    window.addEventListener("resize", yerles);
    window.addEventListener("orientationchange", yerles);
    window.addEventListener("scroll", yerles, true);
    document.addEventListener("keydown", tus, true);
    goster();
  }

  function ogrOtomatik() {
    if (ogrBasladi || !me || !me.giris || me.rol !== "kullanici") return;
    if (store.get("ogretici:" + me.eposta, false)) return;
    ogrBasladi = true;
    setTimeout(() => {
      if (ogrAktif || !me || !me.giris) return;
      const giris = $("giris");
      if (giris && !giris.hidden) { ogrBasladi = false; return; }
      ogrBaslat();
    }, 600);
  }

  function updatePriceTab() {
    menuUygula();
    menuAyarKur();
    window.addEventListener("online", () => { if (!live) startLive(); });
    $("guncelleCard").hidden = !live || !(me && me.rol === "yonetici");
    $("devirBox").hidden = !can("devir");
    hesapCiz();
    if (can("ekle")) loadLists();
    ogrOtomatik();
  }

  async function appGuncelle() {
    $("guncelleBtn").disabled = true;
    $("guncelleMsg").textContent = "Güncelleniyor, bekleyin…";
    $("guncelleMsg").className = "msg";
    try {
      const res = await apiFetch("api/guncelle", { method: "POST" });
      const j = await res.json().catch(() => ({}));
      if (res.ok && j.ok) {
        $("guncelleMsg").textContent = "Güncellendi, uygulama yenileniyor…";
        $("guncelleMsg").className = "msg ok";
        try { if (window.caches) { const ks = await caches.keys(); await Promise.all(ks.map(k => caches.delete(k))); } } catch (e) { }
        setTimeout(() => location.reload(), 800);
        return;
      }
      $("guncelleMsg").textContent = j.error || j.mesaj || "Güncellenemedi.";
      $("guncelleMsg").className = "msg err";
    } catch (e) {
      $("guncelleMsg").textContent = "Kasa bilgisayarına ulaşılamadı.";
      $("guncelleMsg").className = "msg err";
    }
    $("guncelleBtn").disabled = false;
  }

  function fMsg(text, kind) {
    $("fMsg").textContent = text || "";
    $("fMsg").className = "msg " + (kind || "");
  }

  let unitData = null;

  const unitFactor = u => (u.agirlik > 0 ? u.agirlik : (u.carpan > 0 ? u.carpan : 1));
  const unitLabel = u => [u.birim, u.agirlik > 0 ? kgFmt(u.agirlik) + " kg" : "", u.barkod].filter(Boolean).join(" · ");

  function recalcUnits() {
    if (!unitData || unitData.birimler.length < 2) return;
    const main = unitData.birimler[0];
    const m = parseFloat(String($("fNew").value).replace(/\./g, "").replace(",", "."));
    unitData.birimler.slice(1).forEach(u => {
      const inp = $("fu-" + u.ind);
      if (!inp || inp.dataset.touched) return;
      inp.value = m > 0 ? String(round2(m / unitFactor(main) * unitFactor(u))).replace(".", ",") : "";
    });
  }

  async function selectForPrice(p) {
    priceSel = p;
    unitData = null;
    $("fCard").hidden = false;
    $("fName").textContent = p.ad;
    $("fInfo").textContent = "Yükleniyor…";
    $("fOld").textContent = "";
    $("fNew").value = "";
    $("fSave").disabled = true;
    $("fSave").hidden = !can("fiyat");
    $("fYeniGrid").hidden = !can("fiyat");
    $("fSuggest").innerHTML = "";
    $("fSearch").value = "";
    $("fUnitsBox").hidden = true;
    $("fUnits").innerHTML = "";
    $("fTerazi").hidden = true;
    $("fEtiketBox").hidden = true;
    $("fOzelBox").hidden = true;
    $("fBirimBox").hidden = true;
    $("fEtiketSon").hidden = true;
    fMsg("");
    try {
      const res = await apiFetch("api/birimler?ind=" + encodeURIComponent(p.birimind), { cache: "no-store" });
      const j = await res.json();
      if (!res.ok || !j.ok || !j.birimler || !j.birimler.length) throw new Error(j.error || "bulunamadı");
      if (priceSel !== p) return;
      unitData = j;
      const main = j.birimler[0];
      $("fName").textContent = j.ad;
      $("fInfo").textContent = [j.kod, main.barkod].filter(Boolean).join(" · ");
      $("fOld").textContent = tl(main.fiyat) + " / " + lower(main.birim || "birim");
      $("fNewLabel").textContent = "Yeni " + (main.birim || "") + " fiyatı";
      if (j.birimler.length > 1) {
        const ul = $("fUnits");
        j.birimler.forEach((u, i) => {
          const li = document.createElement("li");
          li.innerHTML = '<div class="info"><b></b><span class="muted small"></span></div><input inputmode="decimal" autocomplete="off">';
          li.querySelector("b").textContent = i === 0 ? unitLabel(u) + " (ana birim)" : unitLabel(u);
          li.querySelector("span").textContent = "şu an " + tl(u.fiyat);
          const inp = li.querySelector("input");
          if (i === 0) { inp.disabled = true; inp.placeholder = "üstteki"; }
          else {
            inp.id = "fu-" + u.ind;
            inp.oninput = () => { inp.dataset.touched = "1"; };
          }
          ul.appendChild(li);
        });
        $("fUnitsBox").hidden = !can("fiyat");
      }
      $("fSave").disabled = false;
      fillEtiketUnits();
      birimFormKur();
      if (can("ekle")) loadOzel(j.stok, p);
      const tk = trzKod(j.kod);
      if (tk) showTerazi(p, tk);
      setTimeout(() => $("fNew").focus(), 50);
    } catch (e) {
      $("fInfo").textContent = "";
      fMsg(/JSON|DOCTYPE|Failed to fetch|NetworkError/i.test(e.message) ? "Kasa bilgisayarına ulaşılamadı. Sunucu kapalı ya da yeniden başlıyor olabilir; biraz sonra tekrar dene." : "Ürünün birimleri okunamadı: " + e.message, "err");
    }
  }

  function bMsg(text, kind) { $("bMsg").textContent = text || ""; $("bMsg").className = "msg " + (kind || ""); }

  function birimFormKur() {
    const sel = $("bBirim");
    sel.innerHTML = "";
    ((lists && lists.birim) || ["ADET", "KG", "PAKET"]).forEach(b => {
      const o = document.createElement("option");
      o.value = b; o.textContent = b;
      sel.appendChild(o);
    });
    if ([...sel.options].some(o => o.value === "PAKET")) sel.value = "PAKET";
    $("bAgirlik").value = ""; $("bBarkod").value = ""; $("bFiyat").value = "";
    delete $("bFiyat").dataset.touched;
    bMsg("");
    $("fBirimBox").hidden = !unitData || !can("ekle");
  }

  function birimFiyatHesapla() {
    if (!unitData || $("bFiyat").dataset.touched) return;
    const main = unitData.birimler[0];
    const ag = parseFloat(String($("bAgirlik").value).replace(",", "."));
    $("bFiyat").value = ag > 0 ? String(round2(main.fiyat / unitFactor(main) * ag)).replace(".", ",") : "";
  }

  async function birimEkle() {
    if (!unitData || !priceSel) return;
    const num = v => parseFloat(String(v).replace(/\./g, "").replace(",", "."));
    const birim = $("bBirim").value;
    const agirlik = parseFloat(String($("bAgirlik").value).replace(",", ".")) || 0;
    const barkod = Scale.normCode($("bBarkod").value);
    const fiyat = num($("bFiyat").value);
    if (!birim) { bMsg("Birim adını seç.", "err"); return; }
    if (!barkod) { bMsg("Barkodu yaz.", "err"); return; }
    if (byBarcode.get(barkod)) { bMsg("Bu barkod zaten kayıtlı: " + byBarcode.get(barkod).ad, "err"); return; }
    if (!(fiyat > 0)) { bMsg("Satış fiyatını yaz.", "err"); return; }
    $("bEkle").disabled = true;
    bMsg("Ekleniyor…");
    try {
      const res = await apiFetch("api/birim", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ stok: unitData.stok, birim, agirlik, barkod, fiyat: round2(fiyat) }) });
      const j = await res.json().catch(() => ({}));
      if (res.ok && j.ok) {
        const p = priceSel;
        await syncLive();
        await selectForPrice(p);
        fMsg(birim + (agirlik > 0 ? " " + kgFmt(agirlik) + " kg" : "") + " birimi eklendi (" + barkod + ", " + tl(round2(fiyat)) + ").", "ok");
      } else {
        bMsg(j.error || ("Eklenemedi (" + res.status + ")"), "err");
      }
    } catch (e) {
      bMsg("Kasa bilgisayarına ulaşılamadı.", "err");
    }
    $("bEkle").disabled = false;
  }

  let eCanvas = null, eVeri = null;

  function eMsg(text, kind) {
    $("eMsg").textContent = text || "";
    $("eMsg").className = "msg " + (kind || "");
  }

  function fillEtiketUnits() {
    const sel = $("eBirim");
    sel.innerHTML = "";
    (unitData ? unitData.birimler : []).forEach(u => {
      const o = document.createElement("option");
      o.value = u.ind;
      o.textContent = unitLabel(u);
      sel.appendChild(o);
    });
    eCanvas = null;
    $("eResim").hidden = true;
    eMsg("");
    $("fEtiketBox").hidden = !sel.options.length || !can("etiket");
  }

  async function etiketHazirla() {
    if (!window.Etiket) throw new Error("etiket çizici yüklenmedi");
    const res = await apiFetch("api/etiket?ind=" + encodeURIComponent($("eBirim").value), { cache: "no-store" });
    const j = await res.json().catch(() => ({}));
    if (!res.ok || !j.ok) throw new Error(j.error || ("HTTP " + res.status));
    eVeri = j;
    eCanvas = await Etiket.ciz(j);
    $("eResim").src = (await Etiket.ciz(j, null, { okuma: true })).toDataURL("image/png");
    $("eResim").hidden = false;
  }

  async function etiketOnizle() {
    eMsg("Hazırlanıyor…");
    try { await etiketHazirla(); eMsg(""); } catch (e) { eMsg("Etiket hazırlanamadı: " + e.message, "err"); }
  }

  async function etiketYazdir() {
    const k = parseInt($("eKopya").value, 10);
    if (!(k >= 1 && k <= 50)) { eMsg("Kopya sayısı 1-50 arası olmalı.", "err"); return; }
    $("eYazdir").disabled = true;
    eMsg("Yazdırılıyor…");
    try {
      await etiketHazirla();
      const blob = await new Promise(r => eCanvas.toBlob(r, "image/png"));
      const res = await apiFetch("api/etiket?kopya=" + k + "&ad=" + encodeURIComponent(eVeri.ad || ""), { method: "POST", headers: { "Content-Type": "image/png" }, body: blob });
      const j = await res.json().catch(() => ({}));
      if (res.ok && j.ok) eMsg(k + " etiket yazıcıya gönderildi (" + j.yazici + ").", "ok");
      else eMsg(j.error || ("Yazdırılamadı (" + res.status + ")"), "err");
    } catch (e) {
      eMsg("Yazdırılamadı: " + e.message, "err");
    }
    $("eYazdir").disabled = false;
  }

  function clearPriceSel() {
    priceSel = null;
    unitData = null;
    $("fCard").hidden = true;
  }

  function renderPriceLog() {
    $("fLogCard").hidden = !priceLog.length;
    const ul = $("fLog");
    ul.innerHTML = "";
    priceLog.forEach(x => {
      const li = document.createElement("li");
      li.innerHTML = '<div class="info"><b></b><span class="muted small"></span></div><strong></strong>';
      li.querySelector("b").textContent = x.ad;
      li.querySelector("span").textContent = x.at.toLocaleTimeString("tr-TR", { hour: "2-digit", minute: "2-digit" }) + " · eski " + tl(x.eski) + (x.birimSayisi > 1 ? " · " + x.birimSayisi + " birim" : "");
      li.querySelector("strong").textContent = tl(x.yeni);
      ul.appendChild(li);
    });
  }

  async function savePrice() {
    if (!priceSel || !unitData) return;
    const num = v => parseFloat(String(v).replace(/\./g, "").replace(",", "."));
    const main = unitData.birimler[0];
    const bos = v => !String(v || "").trim();
    const yeni = bos($("fNew").value) ? main.fiyat : num($("fNew").value);
    if (!(yeni > 0)) { fMsg("Yeni fiyatı doğru yaz.", "err"); return; }
    const changes = [{ ind: main.ind, eski: main.fiyat, yeni: round2(yeni) }];
    for (const u of unitData.birimler.slice(1)) {
      const inp = $("fu-" + u.ind);
      const v = !inp || bos(inp.value) ? u.fiyat : num(inp.value);
      if (!(v > 0)) { fMsg(unitLabel(u) + " için fiyatı doğru yaz.", "err"); return; }
      changes.push({ ind: u.ind, eski: u.fiyat, yeni: round2(v) });
    }
    const real = changes.filter(c => Math.abs(c.yeni - c.eski) >= 0.005);
    const birimVar = !$("fBirimBox").hidden && !bos($("bBarkod").value);
    if (!real.length) {
      if (birimVar) { await birimEkle(); return; }
      fMsg("Fiyat değişmedi, kaydedilecek bir şey yok.", "err");
      return;
    }
    if (birimVar) { fMsg("Önce fiyatı kaydet, sonra birimi ekle (ya da fiyat kutusunu boş bırak).", "err"); return; }
    $("fSave").disabled = true;
    fMsg("Kaydediliyor…");
    try {
      const res = await apiFetch("api/fiyat", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ stok: unitData.stok, ad: unitData.ad, degisiklikler: real })
      });
      const j = await res.json().catch(() => ({}));
      if (res.ok && j.ok) {
        clData = null;
        real.forEach(c => { const pr = products.find(x => x.birimind === c.ind); if (pr) pr.fiyat = c.yeni; });
        priceLog.unshift({ ad: unitData.ad, eski: main.fiyat, yeni: round2(yeni), birimSayisi: real.length, at: new Date() });
        renderPriceLog();
        const ad = unitData.ad;
        const saved = priceSel;
        clearPriceSel();
        $("fEtiketSon").hidden = false;
        $("fEtiketSon").onclick = async () => {
          $("fEtiketSon").hidden = true;
          await selectForPrice(saved);
          if (!$("fEtiketBox").hidden) { $("fEtiketBox").scrollIntoView({ behavior: "smooth" }); etiketOnizle(); }
        };
        let msg = ad + ": " + tl(main.fiyat) + " → " + tl(round2(yeni)) + (real.length > 1 ? " (" + real.length + " birim)" : "") + " kasaya kaydedildi";
        if (j.teraziMesaj) msg += ". " + j.teraziMesaj;
        fMsg(msg, "ok");
        await saveProducts();
        syncLive();
        return;
      }
      if (res.status === 409) syncLive();
      fMsg(j.error || ("Kaydedilemedi (" + res.status + ")"), "err");
    } catch (e) {
      fMsg("Kasa bilgisayarına ulaşılamadı.", "err");
    }
    $("fSave").disabled = false;
  }

  let clData = null, clAt = 0;

  async function loadCL(force) {
    if (!force && clData && Date.now() - clAt < 60000) return clData;
    const res = await apiFetch("api/terazi", { cache: "no-store" });
    const j = await res.json().catch(() => ({}));
    if (!res.ok || !j.ok) throw new Error(j.error || ("HTTP " + res.status));
    clData = j.urunler || [];
    clAt = Date.now();
    return clData;
  }

  const trzKod = k => { const m = String(k || "").match(/TRZ[^0-9]*0*([0-9]+)/i); return m ? parseInt(m[1], 10) : 0; };
  const clLine = x => "PLU " + x.plu + " · " + x.ad + " · " + tl(x.fiyat);

  async function showTerazi(p, kod) {
    const el = $("fTerazi");
    el.hidden = false;
    el.className = "msg";
    el.textContent = "Terazi ürünleri okunuyor…";
    try {
      const list = (await loadCL()).filter(x => x.kod === kod);
      if (priceSel !== p) return;
      if (!list.length) {
        el.className = "msg err";
        el.textContent = "Terazide ürün kodu " + kod + " olan ürün yok, terazi fiyatı değişmez.";
      } else {
        el.className = list.length > 1 ? "msg err" : "msg";
        el.textContent = "Terazide birlikte değişecek (ürün kodu " + kod + "): " + list.map(clLine).join(" | ");
      }
    } catch (e) {
      if (priceSel !== p) return;
      el.className = "msg err";
      el.textContent = "Terazi ürünleri okunamadı: " + e.message;
    }
  }

  let tKodOpen = false;

  function hideSameCodes() {
    tKodOpen = false;
    $("tKodList").innerHTML = "";
    $("tKodMsg").textContent = "";
    $("tKodBtn").textContent = "Aynı kodlu terazi ürünlerini göster";
  }

  async function toggleSameCodes() {
    if (tKodOpen) { hideSameCodes(); return; }
    await showSameCodes(true);
  }

  async function showSameCodes(force) {
    const ul = $("tKodList");
    const msg = $("tKodMsg");
    ul.innerHTML = "";
    msg.className = "msg";
    msg.textContent = "Okunuyor…";
    $("tKodBtn").disabled = true;
    try {
      const gizle = $("tKodGizle").checked;
      const data = (await loadCL(force)).filter(x => !gizle || x.plu < 1000);
      const g = new Map();
      data.forEach(x => { if (!g.has(x.kod)) g.set(x.kod, []); g.get(x.kod).push(x); });
      const kasa = new Set(products.map(p => trzKod(p.kod)).filter(Boolean));
      const groups = [...g.entries()]
        .filter(([k, v]) => v.length > 1 || k <= 0)
        .map(([k, v]) => ({ k, v, farkli: new Set(v.map(x => Number(x.fiyat).toFixed(2))).size > 1 }))
        .sort((a, b) => (b.farkli - a.farkli) || (a.k - b.k));
      groups.forEach(gr => {
        const li = document.createElement("li");
        li.innerHTML = '<div class="info"><b></b><span class="muted small"></span></div>';
        const notlar = [gr.v.length + " ürün"];
        if (gr.k <= 0) notlar.push("ürün kodu boş");
        if (gr.farkli) notlar.push("fiyatlar farklı");
        if (gr.k > 0 && products.length && !kasa.has(gr.k)) notlar.push("kasada TRZ-" + gr.k + " yok");
        li.querySelector("b").textContent = (gr.k > 0 ? "Ürün kodu " + gr.k : "Kodsuz") + " — " + notlar.join(", ");
        const sp = li.querySelector("span");
        gr.v.sort((a, b) => a.plu - b.plu).forEach(x => { const d = document.createElement("div"); d.textContent = clLine(x); sp.appendChild(d); });
        if (gr.farkli || gr.k <= 0) li.querySelector("b").className = "msg err";
        ul.appendChild(li);
      });
      const nf = groups.filter(x => x.farkli).length;
      msg.textContent = groups.length ? (groups.length + " kod birden fazla üründe kullanılıyor" + (nf ? ", " + nf + " tanesinde fiyatlar farklı." : ".")) : "Her ürün kodu tek bir terazi ürününde, aynı kodlu ürün yok.";
      msg.className = nf ? "msg err" : "msg ok";
      tKodOpen = true;
      $("tKodBtn").textContent = "Listeyi gizle";
    } catch (e) {
      msg.className = "msg err";
      msg.textContent = "Terazi ürünleri okunamadı: " + e.message;
    }
    $("tKodBtn").disabled = false;
  }

  let icerikler = null, icerikKod = 0, icerikYeni = false;

  function iMsg(text, kind) { $("iMsg").textContent = text || ""; $("iMsg").className = "msg " + (kind || ""); }
  function iKayitMsg(text, kind) { $("iKayitMsg").textContent = text || ""; $("iKayitMsg").className = "msg " + (kind || ""); }

  async function loadIcerikler() {
    iMsg("İçerikler okunuyor…");
    try {
      const res = await apiFetch("api/icerik", { cache: "no-store" });
      const j = await res.json().catch(() => ({}));
      if (!res.ok || !j.ok) throw new Error(j.error || ("HTTP " + res.status));
      icerikler = j.icerikler || [];
      iMsg(icerikler.length + " içerik var. Kod ya da kelimeyle ara, ya da yeni içerik oluştur.");
    } catch (e) {
      icerikler = null;
      iMsg("İçerikler okunamadı: " + e.message, "err");
    }
  }

  const icerikOzet = m => String(m || "").split(/\r?\n/)[0].replace(/~2/g, "").slice(0, 90);

  function icerikAra(q) {
    const ul = $("iSuggest");
    ul.innerHTML = "";
    if (!icerikler) return;
    q = String(q || "").trim();
    if (!q) return;
    const n = q.toLocaleLowerCase("tr-TR");
    const hits = /^\d+$/.test(q) ? icerikler.filter(x => String(x.kod) === q) : icerikler.filter(x => x.metin.toLocaleLowerCase("tr-TR").replace(/~2/g, "").includes(n)).slice(0, 15);
    if (!hits.length) {
      if (/^\d+$/.test(q) && Number(q) > 0 && Number(q) <= 9999) {
        iMsg(q + " numaralı içerik yok.");
        const li = document.createElement("li");
        li.textContent = "＋ " + q + " koduyla yeni içerik oluştur";
        li.onclick = () => { ul.innerHTML = ""; iMsg(""); icerikAc({ kod: Number(q), metin: "" }, true); };
        ul.appendChild(li);
        return;
      }
      iMsg("Bulunamadı.", "err");
      return;
    }
    iMsg("");
    if (hits.length === 1 && /^\d+$/.test(q)) { icerikAc(hits[0], false); return; }
    hits.forEach(x => {
      const li = document.createElement("li");
      li.textContent = x.kod + " · " + icerikOzet(x.metin);
      li.onclick = () => { ul.innerHTML = ""; icerikAc(x, false); };
      ul.appendChild(li);
    });
  }

  function icerikFormKur() {
    const al = $("iAlerjen");
    if (!al.childElementCount) {
      Icerik.ALERJEN.forEach(([k, ad]) => {
        const l = document.createElement("label");
        l.innerHTML = '<span></span><select><option value="">—</option><option value="icerir">İçerir</option><option value="eser">Eser miktarda</option></select>';
        l.querySelector("span").textContent = ad;
        const sel = l.querySelector("select");
        sel.id = "iA-" + k;
        sel.onchange = icerikOnizle;
        al.appendChild(l);
      });
      const bs = $("iBesin");
      [["kj", "Enerji (kJ)"], ["kcal", "Enerji (kcal)"]].concat(Icerik.BESIN).forEach(([k, ad]) => {
        const l = document.createElement("label");
        l.innerHTML = '<span></span><input inputmode="decimal" autocomplete="off">';
        l.querySelector("span").textContent = ad;
        const inp = l.querySelector("input");
        inp.id = "iB-" + k;
        inp.oninput = icerikOnizle;
        bs.appendChild(l);
      });
    }
  }

  function icerikDegerleri() {
    const v = { icindekiler: $("iIcindekiler").value, kayit: $("iKayit").value, alerjenEk: $("iAlerjenEk").value, alerjen: {}, besin: {} };
    Icerik.ALERJEN.forEach(([k]) => { const x = $("iA-" + k).value; if (x) v.alerjen[k] = x; });
    ["kj", "kcal"].concat(Icerik.BESIN.map(b => b[0])).forEach(k => { v.besin[k] = $("iB-" + k).value.trim(); });
    return v;
  }

  function icerikOnizle() {
    $("iOnizle").innerHTML = Icerik.html(Icerik.olustur(icerikDegerleri()));
  }

  function icerikAc(x, yeni) {
    icerikFormKur();
    icerikKod = x.kod;
    icerikYeni = yeni;
    const v = Icerik.coz(x.metin || "");
    $("iBaslik").textContent = (yeni ? "Yeni içerik · kod " : "İçerik kodu ") + x.kod;
    $("iIcindekiler").value = v.icindekiler;
    $("iKayit").value = v.kayit || Icerik.KAYIT;
    $("iAlerjenEk").value = v.alerjenEk;
    Icerik.ALERJEN.forEach(([k]) => { $("iA-" + k).value = v.alerjen[k] || ""; });
    ["kj", "kcal"].concat(Icerik.BESIN.map(b => b[0])).forEach(k => { $("iB-" + k).value = v.besin[k] || ""; });
    $("iUyari").hidden = !v.taninmayan.length;
    $("iUyari").textContent = v.taninmayan.length ? "Şu satırlar tanınmadı, kaydedersen silinir: " + v.taninmayan.map(t => t.replace(/~2/g, "")).join(" / ") : "";
    iKayitMsg("");
    $("iCard").hidden = false;
    icerikOnizle();
    setTimeout(() => $("iCard").scrollIntoView({ behavior: "smooth" }), 50);
  }

  function icerikYeniAc() {
    if (!icerikler) { iMsg("İçerikler henüz okunmadı.", "err"); return; }
    const kod = icerikler.reduce((m, x) => Math.max(m, x.kod), 0) + 1;
    icerikAc({ kod, metin: "" }, true);
  }

  async function icerikKaydet() {
    const v = icerikDegerleri();
    if (!v.icindekiler.trim()) { iKayitMsg("İçindekileri yaz.", "err"); return; }
    const metin = Icerik.olustur(v);
    $("iKaydet").disabled = true;
    iKayitMsg("Kaydediliyor…");
    try {
      const res = await apiFetch("api/icerik", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ kod: icerikKod, metin, gonder: $("iGonder").checked }) });
      const j = await res.json().catch(() => ({}));
      if (res.ok && j.ok) {
        const eski = icerikler && icerikler.find(x => x.kod === icerikKod);
        if (eski) eski.metin = metin; else if (icerikler) icerikler.push({ kod: icerikKod, metin });
        icerikYeni = false;
        $("iBaslik").textContent = "İçerik kodu " + icerikKod;
        $("iUyari").hidden = true;
        const tm = j.teraziMesaj || "";
        iKayitMsg("CL'ye kaydedildi (kod " + icerikKod + "). " + (tm || "Terazilere gönderilmedi; göndermek için CL Works'te Gönder'e bas."), /ulasilamadi|Ulasilamadi/.test(tm) ? "err" : "ok");
      } else {
        iKayitMsg(j.error || ("Kaydedilemedi (" + res.status + ")"), "err");
      }
    } catch (e) {
      iKayitMsg("Kasa bilgisayarına ulaşılamadı.", "err");
    }
    $("iKaydet").disabled = false;
  }

  async function icerikListesiDoldur() {
    if (!icerikler) await loadIcerikler();
    const dl = $("dlIcerik");
    if (!icerikler || dl.childElementCount === icerikler.length + 1) return;
    dl.innerHTML = "";
    const z = document.createElement("option");
    z.value = "0"; z.label = "İçerik yok";
    dl.appendChild(z);
    icerikler.slice().sort((a, b) => b.kod - a.kod).forEach(x => {
      const o = document.createElement("option");
      o.value = String(x.kod);
      o.label = icerikOzet(x.metin);
      o.textContent = icerikOzet(x.metin);
      dl.appendChild(o);
    });
    icerikSecimGoster();
  }

  function icerikSecimGoster() {
    const v = $("aClIcerik").value.trim();
    const x = icerikler && /^\d+$/.test(v) && Number(v) > 0 ? icerikler.find(i => String(i.kod) === v) : null;
    $("aClIcerikInfo").textContent = Number(v) > 0 ? (x ? "İçerik " + v + ": " + icerikOzet(x.metin) : (icerikler ? "Bu kodda içerik yok." : "")) : "";
  }

  let stokSecili = null;
  const stokLog = [];
  const sayiOku = v => { const t = String(v || "").trim().replace(/\s/g, ""); if (!t) return NaN; return parseFloat(/,/.test(t) ? t.replace(/\./g, "").replace(",", ".") : t); };
  const miktarYaz = n => (Math.round(n * 1000) / 1000).toLocaleString("tr-TR", { maximumFractionDigits: 3 });

  function sMsg(text, kind) { $("sMsg").textContent = text || ""; $("sMsg").className = "msg " + (kind || ""); }
  function sdMsg(text, kind) { $("sdMsg").textContent = text || ""; $("sdMsg").className = "msg " + (kind || ""); }

  function stokHesap() {
    const a = sayiOku($("sdAdet").value), c = sayiOku($("sdCarpan").value) || 1;
    const el = $("sdToplam");
    if (!(a > 0) || !(c > 0) || !stokSecili) { el.textContent = "Adet yaz; çarpan kutudaki adet içindir (24'lü koli için 24)."; return 0; }
    const t = Math.round(a * c * 1000) / 1000;
    el.innerHTML = "";
    el.append(miktarYaz(a) + " × " + miktarYaz(c) + " = ");
    const b = document.createElement("b"); b.textContent = miktarYaz(t) + " " + (stokSecili.birim || "");
    el.append(b, " eklenecek · yeni kalan " + miktarYaz((Number(stokSecili.kalan) || 0) + t));
    return t;
  }

  async function stokAc(p) {
    if (!p || !p.birimind) { sMsg("Bu ürün kasada kayıtlı değil.", "err"); return; }
    sMsg("Ürün bilgisi alınıyor…");
    try {
      const res = await apiFetch("api/stok?birim=" + encodeURIComponent(p.birimind), { cache: "no-store" });
      const j = await res.json().catch(() => ({}));
      if (!res.ok || !j.ok) throw new Error(j.error || ("HTTP " + res.status));
      stokSecili = j;
      sMsg("");
      $("sdAd").textContent = j.ad;
      $("sdBilgi").textContent = [j.kod, "Şu an: " + miktarYaz(Number(j.kalan) || 0) + " " + (j.birim || "")].filter(Boolean).join(" · ");
      $("sdAdet").value = "";
      $("sdCarpan").value = "1";
      sdMsg("");
      $("sdEkle").disabled = false;
      stokHesap();
      $("stokDialog").showModal();
      setTimeout(() => $("sdAdet").focus(), 50);
    } catch (e) {
      sMsg("Ürün bilgisi alınamadı: " + e.message, "err");
    }
  }

  async function stokEkle() {
    if (!stokSecili) return;
    const t = stokHesap();
    if (!(t > 0)) { sdMsg("Adet ve çarpanı yaz.", "err"); return; }
    if (t > 100000) { sdMsg("Miktar çok büyük, adet ve çarpanı kontrol et.", "err"); return; }
    $("sdEkle").disabled = true;
    sdMsg("Ekleniyor…");
    try {
      const res = await apiFetch("api/stok", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ stok: stokSecili.stok, miktar: t }) });
      const j = await res.json().catch(() => ({}));
      if (res.ok && j.ok) {
        $("stokDialog").close();
        stokLog.unshift({ ad: stokSecili.ad, miktar: t, birim: stokSecili.birim, kalan: j.kalan, belge: j.belge, at: new Date() });
        stokLogCiz();
        sMsg(stokSecili.ad + ": +" + miktarYaz(t) + " " + (stokSecili.birim || "") + " eklendi (fiş " + j.belge + "). Kalan " + miktarYaz(j.kalan) + ".", "ok");
        beep(true);
        return;
      }
      sdMsg(j.error || ("Eklenemedi (" + res.status + ")"), "err");
    } catch (e) {
      sdMsg("Kasa bilgisayarına ulaşılamadı.", "err");
    }
    $("sdEkle").disabled = false;
  }

  function stokLogCiz() {
    $("sLogCard").hidden = !stokLog.length;
    const ul = $("sLog");
    ul.innerHTML = "";
    stokLog.forEach(x => {
      const li = document.createElement("li");
      li.innerHTML = '<div class="info"><b></b><span class="muted small"></span></div><strong></strong>';
      li.querySelector("b").textContent = x.ad;
      li.querySelector("span").textContent = x.at.toLocaleTimeString("tr-TR", { hour: "2-digit", minute: "2-digit" }) + " · fiş " + x.belge + " · kalan " + miktarYaz(x.kalan);
      li.querySelector("strong").textContent = "+" + miktarYaz(x.miktar);
      ul.appendChild(li);
    });
  }

  function stokScan(code) {
    const r = lookup(code);
    if (r && r.product && !r.scale) { beep(true); stokAc(r.product); return; }
    if (r && r.product && r.scale) { beep(true); stokAc(r.product); return; }
    beep(false);
    sMsg("Bulunamadı: " + code + ". Terazi ürünüyse aşağıdaki listeden seç.", "err");
  }

  function stokAra(q) {
    const ul = $("sSuggest");
    ul.innerHTML = "";
    q = String(q || "").trim();
    if (!q) return;
    const r = /^\d{6,14}$/.test(q) ? lookup(q) : null;
    if (r && r.product) { stokAc(r.product); return; }
    const k = findByKod(q);
    if (k) { stokAc(k); return; }
    const hits = search(q, 8).filter(p => p.birimind);
    if (!hits.length) { sMsg("Bulunamadı.", "err"); return; }
    sMsg("");
    hits.forEach(p => {
      const li = document.createElement("li");
      li.textContent = p.ad + (p.kod ? " · " + p.kod : "");
      li.onclick = () => { ul.innerHTML = ""; $("sAra").value = ""; stokAc(p); };
      ul.appendChild(li);
    });
  }

  function stokTeraziListe() {
    const q = lower($("sTrzAra").value).trim();
    const seen = new Set();
    const list = products.filter(p => /^TRZ-/i.test(p.kod || "") && p.birimind && !seen.has(p.kod) && seen.add(p.kod))
      .filter(p => !q || lower(p.ad + " " + p.kod).includes(q))
      .sort((a, b) => (trzKod(a.kod) - trzKod(b.kod)));
    const ul = $("sTrzList");
    ul.innerHTML = "";
    list.slice(0, 300).forEach(p => {
      const li = document.createElement("li");
      li.innerHTML = '<div class="info"><b></b><span class="muted small"></span></div>';
      li.querySelector("b").textContent = p.ad;
      li.querySelector("span").textContent = p.kod;
      li.onclick = () => stokAc(p);
      ul.appendChild(li);
    });
  }

  let devirVeri = null, donemListesi = null;
  function dvMsg(text, kind) { $("dvMsg").textContent = text || ""; $("dvMsg").className = "msg " + (kind || ""); }
  const donemEtiket = d => d.ad.slice(5) + (d.ilk ? " · " + d.ilk + " – " + d.son : " · boş") + " · " + d.satir + " kayıt";

  async function devirDonemler() {
    if (donemListesi) return;
    dvMsg("Dönemler okunuyor…");
    try {
      const res = await apiFetch("api/devir", { cache: "no-store" });
      const j = await res.json().catch(() => ({}));
      if (!res.ok || !j.ok) throw new Error(j.error || ("HTTP " + res.status));
      donemListesi = j.donemler || [];
      ["dvKaynak", "dvHedef"].forEach(id => {
        const sel = $(id);
        sel.innerHTML = "";
        donemListesi.forEach(d => { const o = document.createElement("option"); o.value = d.ad; o.textContent = donemEtiket(d); sel.appendChild(o); });
      });
      const gi = donemListesi.findIndex(d => d.ad === j.guncel);
      $("dvHedef").value = j.guncel;
      if (gi > 0) $("dvKaynak").value = donemListesi[gi - 1].ad;
      dvMsg("");
    } catch (e) {
      donemListesi = null;
      dvMsg("Dönemler okunamadı: " + e.message, "err");
    }
  }

  async function devirOnizle() {
    const k = $("dvKaynak").value, h = $("dvHedef").value;
    $("dvSonuc").hidden = true;
    devirVeri = null;
    if (!k || !h || k === h) { dvMsg("Kaynak ve hedef farklı dönemler olmalı.", "err"); return; }
    if (k > h) { dvMsg("Kaynak dönem hedef dönemden önce olmalı.", "err"); return; }
    dvMsg("Hesaplanıyor…");
    try {
      const res = await apiFetch("api/devir?kaynak=" + encodeURIComponent(k) + "&hedef=" + encodeURIComponent(h), { cache: "no-store" });
      const j = await res.json().catch(() => ({}));
      if (!res.ok || !j.ok) throw new Error(j.error || ("HTTP " + res.status));
      devirVeri = j;
      dvMsg("");
      $("dvOzet").textContent = j.urun + " ürünün kalanı (" + miktarYaz(j.toplam) + " birim) " + h.slice(5) + " dönemine tek fişle aktarılacak.";
      const ul = $("dvListe");
      ul.innerHTML = "";
      j.satirlar.forEach(x => {
        const li = document.createElement("li");
        li.innerHTML = '<div class="info"><b></b><span class="muted small"></span></div><strong></strong>';
        li.querySelector("b").textContent = x.ad;
        li.querySelector("span").textContent = x.kod || "";
        li.querySelector("strong").textContent = miktarYaz(x.kalan) + " " + (x.birim || "");
        ul.appendChild(li);
      });
      if (j.urun > j.satirlar.length) { const li = document.createElement("li"); li.textContent = "… ve " + (j.urun - j.satirlar.length) + " ürün daha"; ul.appendChild(li); }
      $("dvDevret").disabled = j.onceki > 0 || j.urun === 0;
      if (j.onceki > 0) dvMsg("Bu dönemden devir daha önce yapılmış. İkinci kez yapılmaz.", "err");
      else if (j.urun === 0) dvMsg("Kaynak dönemde kalanı olan ürün yok.", "err");
      $("dvSonuc").hidden = false;
    } catch (e) {
      dvMsg("Önizleme yapılamadı: " + e.message, "err");
    }
  }

  async function devirYap() {
    if (!devirVeri) return;
    if (!confirm(devirVeri.urun + " ürünün kalanı " + devirVeri.kaynak.slice(5) + " döneminden " + devirVeri.hedef.slice(5) + " dönemine aktarılacak. Bu işlem bir kez yapılır. Devam edilsin mi?")) return;
    $("dvDevret").disabled = true;
    dvMsg("Devrediliyor, bu biraz sürebilir…");
    try {
      const res = await apiFetch("api/devir", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ kaynak: devirVeri.kaynak, hedef: devirVeri.hedef }) });
      const j = await res.json().catch(() => ({}));
      if (res.ok && j.ok) {
        dvMsg("Devir tamam: fiş " + j.belge + ", " + j.adet + " ürün, toplam " + miktarYaz(j.toplam) + " birim.", "ok");
        $("dvSonuc").hidden = true;
        donemListesi = null;
        return;
      }
      dvMsg(j.error || ("Devir yapılamadı (" + res.status + ")"), "err");
    } catch (e) {
      dvMsg("Kasa bilgisayarına ulaşılamadı. Devrin yapılıp yapılmadığını Önizle ile kontrol et.", "err");
    }
    $("dvDevret").disabled = false;
  }

  const kodNorm = v => String(v || "").toLocaleUpperCase("tr-TR").replace(/[^0-9A-ZÇĞİÖŞÜ]/g, "").replace(/^([A-ZÇĞİÖŞÜ]*)0+(?=\d)/, "$1");

  function findByKod(q) {
    const k = kodNorm(q);
    if (!k) return null;
    const hits = products.filter(p => p.birimind && kodNorm(p.kod) === k);
    return hits.length ? hits[0] : null;
  }

  function priceFind(q) {
    q = String(q || "").trim();
    if (!q) return;
    fMsg("");
    const byKod = findByKod(q);
    if (byKod) { selectForPrice(byKod); return; }
    if (/^\d+$/.test(q)) {
      const r = lookup(q);
      if (r && r.product) { selectForPrice(r.product); return; }
      const n = parseInt(q, 10);
      const trz = q.length <= 6 ? (findByKod("TRZ" + n) || byBarcode.get(String(n).padStart(5, "0"))) : null;
      if (trz) { selectForPrice(trz); return; }
      fMsg(r && r.scale ? "Bu terazi numarası (" + r.scale.plu + ") listede yok." : "Bulunamadı: " + q, "err");
      return;
    }
    const res = search(q, 2).filter(p => p.birimind);
    if (res.length === 1) selectForPrice(res[0]);
    else if (!res.length) fMsg("Bulunamadı: " + q, "err");
    else fMsg("Birden fazla ürün var, aşağıdaki listeden seç.", "err");
  }

  function renderPriceSuggest() {
    const q = $("fSearch").value.trim();
    const ul = $("fSuggest");
    ul.innerHTML = "";
    if (q.length < 2 || /^\d{6,}$/.test(q)) return;
    search(q, 30).filter(p => p.birimind).slice(0, 8).forEach(p => ul.appendChild(productLi(p, selectForPrice)));
  }

  let lists = null, kodTouched = false;
  const addLog = [];

  async function loadLists() {
    try {
      const res = await apiFetch("api/listeler", { cache: "no-store" });
      const j = await res.json().catch(() => ({}));
      if (!res.ok || !j || !j.ok) { aMsg("Seçim listeleri okunamadı: " + (j.error || ("HTTP " + res.status)), "err"); return; }
      lists = j;
      const fill = (sel, items, val, label) => {
        sel.innerHTML = "";
        (items || []).forEach(it => {
          const o = document.createElement("option");
          o.value = val(it);
          o.textContent = label(it);
          sel.appendChild(o);
        });
      };
      fill($("aBirim"), j.birim, x => x, x => x);
      fill($("aFiyatAdi"), j.fiyatAdi, x => x, x => x);
      fill($("aKdv"), j.kdv, x => x.ind, x => x.ad + " %" + Number(x.oran).toLocaleString("tr-TR"));
      OZEL.forEach(n => fill($("dlOk" + n), (j.ozel || {})[n] || [], x => x, x => x));
      if (!$("aBarkod").value.trim() && !$("aAd").value.trim()) resetAddForm();
      else {
        if ([...$("aBirim").options].some(o => o.value === "ADET") && !$("aTerazi").checked) $("aBirim").value = "ADET";
        if ([...$("aFiyatAdi").options].some(o => o.value === "FIYAT")) $("aFiyatAdi").value = "FIYAT";
      }
      if (j.hatalar && j.hatalar.length) aMsg("Bazı listeler okunamadı: " + j.hatalar.join(" | "), "err");
    } catch (e) {
      aMsg("Seçim listeleri okunamadı: " + e.message, "err");
    }
  }

  const OZEL = [1, 2, 3, 4, 5, 6, 7, 9, 10];
  const BIZIM_KAYIT = "TR-41-K-033887";
  const trMi = v => String(v || "").trim().toLocaleUpperCase("tr-TR").replace(/[İÜŞÇĞÖ]/g, c => ({ "İ": "I", "Ü": "U", "Ş": "S", "Ç": "C", "Ğ": "G", "Ö": "O" })[c]) === "TURKIYE";
  const kayitOto = {};

  function uretimYeriDegisti(p) {
    const tr = trMi($(p + "Ok10").value);
    if (tr && !$(p + "Ok6").value.trim()) { $(p + "Ok6").value = BIZIM_KAYIT; kayitOto[p] = true; }
    else if (!tr && kayitOto[p] && $(p + "Ok6").value === BIZIM_KAYIT) { $(p + "Ok6").value = ""; kayitOto[p] = false; }
  }

  function kayitBagla(p) {
    $(p + "Ok10").addEventListener("input", () => uretimYeriDegisti(p));
    $(p + "Ok10").addEventListener("change", () => uretimYeriDegisti(p));
    $(p + "Ok6").addEventListener("input", () => { kayitOto[p] = false; });
  }

  let ozelEski = null, ozelStok = 0;

  function okMsg(text, kind) {
    $("fOkMsg").textContent = text || "";
    $("fOkMsg").className = "msg " + (kind || "");
  }

  async function loadOzel(stok, p) {
    ozelEski = null; ozelStok = 0;
    okMsg("");
    try {
      const res = await apiFetch("api/ozel?stok=" + encodeURIComponent(stok), { cache: "no-store" });
      const j = await res.json().catch(() => ({}));
      if (priceSel !== p) return;
      if (!res.ok || !j.ok) { $("fOzelBox").hidden = false; okMsg("Özel kodlar okunamadı: " + (j.error || ("HTTP " + res.status)), "err"); return; }
      ozelEski = j.ozel || {};
      ozelStok = stok;
      OZEL.forEach(n => { $("fOk" + n).value = ozelEski[n] || ""; });
      kayitOto.f = false;
      $("fOzelBox").hidden = false;
    } catch (e) {
      if (priceSel === p) { $("fOzelBox").hidden = false; okMsg("Özel kodlar okunamadı.", "err"); }
    }
  }

  async function saveOzel() {
    if (!ozelEski || !ozelStok) return;
    const degisen = {};
    OZEL.forEach(n => { const v = $("fOk" + n).value.trim(); if (v !== (ozelEski[n] || "")) degisen[n] = v; });
    if (!Object.keys(degisen).length) { okMsg("Değişiklik yok.", "err"); return; }
    $("fOkKaydet").disabled = true;
    okMsg("Kaydediliyor…");
    try {
      const res = await apiFetch("api/ozel", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ stok: ozelStok, ozel: degisen }) });
      const j = await res.json().catch(() => ({}));
      if (res.ok && j.ok) {
        Object.assign(ozelEski, degisen);
        okMsg("Özel kodlar kaydedildi (" + Object.keys(degisen).length + " alan).", "ok");
        Object.entries(degisen).forEach(([n, v]) => {
          const dl = $("dlOk" + n);
          if (!v || !dl || [...dl.options].some(o => o.value.toLocaleUpperCase("tr-TR") === v.toLocaleUpperCase("tr-TR"))) return;
          const o = document.createElement("option");
          o.value = v; o.textContent = v;
          dl.insertBefore(o, dl.firstChild);
        });
      } else {
        okMsg(j.error || ("Kaydedilemedi (" + res.status + ")"), "err");
      }
    } catch (e) {
      okMsg("Kasa bilgisayarına ulaşılamadı.", "err");
    }
    $("fOkKaydet").disabled = false;
  }

  function aMsg(text, kind) {
    $("aMsg").textContent = text || "";
    $("aMsg").className = "msg " + (kind || "");
  }

  function numIn(id) {
    const v = String($(id).value).trim();
    if (!v) return 0;
    return parseFloat(v.replace(/\./g, "").replace(",", ".")) || 0;
  }

  function stdText() {
    const b = $("aBarkod").value.trim();
    if ($("aTerazi").checked) return "Barkod standardı: terazi (Vega'daki terazi ürünleri gibi)";
    if (/^\d{13}$/.test(b)) return "Barkod standardı: Ean 13";
    return b ? "Barkod standardı: [Hiçbiri]" : "";
  }

  function checkBarcode() {
    const b = Scale.normCode($("aBarkod").value);
    $("aStd").textContent = stdText();
    if (!kodTouched) $("aKod").value = $("aTerazi").checked && /^\d+$/.test(b) ? "TRZ-" + parseInt(b, 10) : b;
    updateClInfo();
    const hit = b && byBarcode.get(b);
    if (hit) aMsg("Bu barkod zaten kayıtlı: " + hit.ad + " (" + tl(hit.fiyat) + ")", "err");
    else if ($("aMsg").className.includes("err")) aMsg("");
  }

  let clAdTouched = false;

  async function checkClPlu(force) {
    const msg = $("aClPluMsg"), btn = $("aClOneri");
    const raw = $("aClPlu").value.trim();
    const v = parseInt(raw, 10);
    try {
      const list = await loadCL(force);
      updateClInfo();
      const used = new Map(list.filter(x => x.bolum === 1).map(x => [x.plu, x.ad]));
      let o = 1;
      while (o < 1000 && used.has(o)) o++;
      btn.hidden = o >= 1000;
      btn.textContent = "İlk boş PLU: " + o + " (kullan)";
      btn.dataset.plu = o;
      if (!raw) { msg.textContent = ""; msg.className = "msg"; return; }
      if (!/^\d+$/.test(raw) || !(v >= 1 && v < 1000)) { msg.textContent = "PLU 1 ile 999 arasında olmalı."; msg.className = "msg err"; return; }
      if (used.has(v)) { msg.textContent = "PLU " + v + " dolu: " + used.get(v); msg.className = "msg err"; }
      else { msg.textContent = "PLU " + v + " boş ✓"; msg.className = "msg ok"; }
    } catch (e) {
      msg.textContent = "Terazi listesi okunamadı: " + e.message;
      msg.className = "msg err";
      btn.hidden = true;
    }
  }

  const clAdi = v => String(v || "").replace(/\s*TRZ\s*NO\s*:?\s*\d*\s*$/i, "").trim().toLocaleUpperCase("tr-TR");

  function sabitBarkod(n) {
    if (!(n > 0 && n <= 99999)) return "";
    const s = "28" + String(n).padStart(5, "0") + "00001";
    const cs = (10 - (s.split("").reduce((a, v, i) => a + Number(v) * (i % 2 ? 3 : 1), 0) % 10)) % 10;
    return s + cs;
  }

  function updateClInfo() {
    const k = trzKod($("aKod").value);
    let t = k
      ? "Terazi ürün kodu: " + k + " (stok kodundan). Terazi fiyatı: 1. satış fiyatı."
      : "Stok kodu TRZ-sayı olmalı (örnek TRZ-650), terazi ürün kodu ondan alınır.";
    const ayni = k && clData ? clData.filter(x => x.kod === k && x.plu < 1000) : [];
    if (ayni.length) t += " Dikkat: CL'de bu ürün kodu zaten var: " + ayni.map(x => "PLU " + x.plu + " " + x.ad).join(", ") + ". Fiyat değişince birlikte değişirler.";
    $("aClInfo").textContent = t;
    if ($("aSabit").checked) {
      const b = sabitBarkod(k);
      $("aSabitInfo").hidden = false;
      $("aSabitInfo").textContent = b
        ? "Kasa barkodu teraziden çıkacak sabit etiketle aynı: " + b + " (28 + ürün kodu " + String(k).padStart(5, "0") + " + 1 adet). Terazi tipi Adet, kasada birim ADET."
        : "Sabit fiyatlı ürün için stok kodu TRZ-1 ile TRZ-99999 arası olmalı.";
    } else $("aSabitInfo").hidden = true;
  }

  function applySabit() {
    const on = $("aSabit").checked;
    let n = trzKod($("aKod").value) || parseInt(lists && lists.sonrakiPlu, 10) || 0;
    if (on) {
      if (n) { $("aKod").value = "TRZ-" + n; kodTouched = true; }
      $("aBarkod").value = sabitBarkod(n);
      if ([...$("aBirim").options].some(o => o.value === "ADET")) $("aBirim").value = "ADET";
      $("aClTip").value = "2";
    } else {
      if (n) $("aBarkod").value = String(n).padStart(5, "0");
      kodTouched = false;
      if ([...$("aBirim").options].some(o => o.value === "KG")) $("aBirim").value = "KG";
      $("aClTip").value = "1";
    }
    checkBarcode();
  }

  function resetClFields() {
    $("aClAd").value = "";
    $("aClPlu").value = "";
    $("aClTip").value = "1";
    $("aClIcerik").value = "0";
    $("aClIcerikInfo").textContent = "";
    $("aClSkt").value = "366";
    $("aClPluMsg").textContent = "";
    $("aClOneri").hidden = true;
    $("aSabit").checked = false;
    $("aSabitInfo").hidden = true;
    clAdTouched = false;
  }

  function applyTerazi() {
    const t = $("aTerazi").checked;
    $("aClBox").hidden = !t;
    if (!t && $("aSabit").checked) { $("aSabit").checked = false; $("aSabitInfo").hidden = true; }
    if (t && !$("aOk1").value.trim()) $("aOk1").value = "Terazilikler";
    if (!t && $("aOk1").value.trim() === "Terazilikler") $("aOk1").value = "";
    if (t) {
      if (!clAdTouched) $("aClAd").value = clAdi($("aAd").value);
      if (!$("aClIcerik").value.trim()) $("aClIcerik").value = "0";
      if (!$("aClSkt").value.trim()) $("aClSkt").value = "366";
      checkClPlu(true);
      if ([...$("aBirim").options].some(o => o.value === "KG")) $("aBirim").value = "KG";
      if (lists && lists.sonrakiPlu) $("aBarkod").value = lists.sonrakiPlu;
      kodTouched = false;
    } else {
      if ([...$("aBirim").options].some(o => o.value === "ADET")) $("aBirim").value = "ADET";
      if (lists && $("aBarkod").value === lists.sonrakiPlu) $("aBarkod").value = "";
    }
    checkBarcode();
  }

  function resetAddForm() {
    ["aBarkod", "aKod", "aAd", "aF1", "aF2", "aF3", "aAlis", "aAlisKdv", "aUretici"].forEach(id => { $(id).value = ""; });
    $("aTerazi").checked = false;
    OZEL.forEach(n => { $("aOk" + n).value = ""; });
    kayitOto.a = false;
    $("aClBox").hidden = true;
    resetClFields();
    $("aKdvDahil").checked = false;
    if ([...$("aBirim").options].some(o => o.value === "ADET")) $("aBirim").value = "ADET";
    if ([...$("aFiyatAdi").options].some(o => o.value === "FIYAT")) $("aFiyatAdi").value = "FIYAT";
    if ($("aKdv").options.length) $("aKdv").selectedIndex = 0;
    kodTouched = false;
    $("aStd").textContent = "";
    $("aSave").disabled = false;
  }

  function renderAddLog() {
    $("aLogCard").hidden = !addLog.length;
    const ul = $("aLog");
    ul.innerHTML = "";
    addLog.forEach(x => {
      const li = document.createElement("li");
      li.innerHTML = '<div class="info"><b></b><span class="muted small"></span></div><strong></strong>';
      li.querySelector("b").textContent = x.ad;
      li.querySelector("span").textContent = x.at.toLocaleTimeString("tr-TR", { hour: "2-digit", minute: "2-digit" }) + " · " + [x.barkod, x.birim].filter(Boolean).join(" · ");
      li.querySelector("strong").textContent = tl(x.fiyat);
      ul.appendChild(li);
    });
  }

  async function saveProduct(e) {
    if (e) e.preventDefault();
    const data = {
      terazi: $("aTerazi").checked,
      barkod: Scale.normCode($("aBarkod").value),
      stokKodu: $("aKod").value.trim(),
      ad: $("aAd").value.trim().toLocaleUpperCase("tr-TR"),
      fiyat1: numIn("aF1"),
      fiyat2: numIn("aF2"),
      fiyat3: numIn("aF3"),
      birim: $("aBirim").value,
      fiyatAdi: $("aFiyatAdi").value,
      kdvGrubu: Number($("aKdv").value),
      kdvDahil: $("aKdvDahil").checked,
      alisFiyati: numIn("aAlis"),
      alisKdv: Math.round(numIn("aAlisKdv")),
      uretici: $("aUretici").value.trim(),
      ozel: Object.fromEntries(OZEL.map(n => [String(n), $("aOk" + n).value.trim()]).filter(x => x[1]))
    };
    if (!data.ad) { aMsg("Stok adını yaz.", "err"); return; }
    if (!data.stokKodu) { aMsg("Stok kodunu yaz.", "err"); return; }
    if (!(data.fiyat1 > 0)) { aMsg("1. satış fiyatını yaz.", "err"); return; }
    if (data.barkod && byBarcode.get(data.barkod)) { aMsg("Bu barkod zaten kayıtlı: " + byBarcode.get(data.barkod).ad, "err"); return; }
    if (data.terazi) {
      const int = id => { const v = $(id).value.trim(); return /^\d+$/.test(v) ? parseInt(v, 10) : -1; };
      data.cl = {
        ad: $("aClAd").value.trim().toLocaleUpperCase("tr-TR"),
        plu: int("aClPlu"),
        tip: Number($("aClTip").value),
        icerik: int("aClIcerik"),
        skt: int("aClSkt")
      };
      if (!trzKod(data.stokKodu)) { aMsg("Terazi ürünü için stok kodu TRZ-sayı olmalı (örnek TRZ-650).", "err"); return; }
      if ($("aSabit").checked) {
        const sb = sabitBarkod(trzKod(data.stokKodu));
        if (!sb) { aMsg("Sabit fiyatlı ürün için stok kodu TRZ-1 ile TRZ-99999 arası olmalı.", "err"); return; }
        if (data.barkod !== sb) { aMsg("Sabit fiyatlı üründe barkod " + sb + " olmalı (stok kodundan hesaplanır).", "err"); return; }
        if (data.cl.tip !== 2) { aMsg("Sabit fiyatlı üründe terazi tipi 2. Adet olmalı.", "err"); return; }
      }
      if (!data.cl.ad) { aMsg("Terazideki adı yaz.", "err"); return; }
      if (!(data.cl.plu >= 1 && data.cl.plu < 1000)) { aMsg("Terazi PLU no yaz (1-999).", "err"); return; }
      if (data.cl.icerik < 0) { aMsg("İçerik no sayı olmalı (yoksa 0).", "err"); return; }
      if (data.cl.skt < 0) { aMsg("Son kullanma gün sayısı olmalı.", "err"); return; }
      if ($("aClPluMsg").className.includes("err")) { aMsg($("aClPluMsg").textContent, "err"); return; }
    }
    $("aSave").disabled = true;
    aMsg("Kaydediliyor…");
    try {
      const res = await apiFetch("api/urun", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(data) });
      const j = await res.json().catch(() => ({}));
      if (res.ok && j.ok) {
        addLog.unshift({ ad: data.ad, barkod: data.barkod, birim: data.birim, fiyat: data.fiyat1, at: new Date() });
        renderAddLog();
        resetAddForm();
        clData = null;
        const ok = !j.clMesaj || /^CL'ye/.test(j.clMesaj);
        aMsg(data.ad + " kasaya eklendi. " + (j.clMesaj || (data.terazi ? "CL Works'e de eklemeyi unutmayın." : "")), ok ? "ok" : "err");
        await syncLive();
        loadLists();
        return;
      }
      if (j.oneri) { clData = null; checkClPlu(true); }
      aMsg(j.error || ("Eklenemedi (" + res.status + ")"), "err");
    } catch (err) {
      aMsg("Kasa bilgisayarına ulaşılamadı.", "err");
    }
    $("aSave").disabled = false;
  }

  function handleAddScan(code) {
    beep(true);
    stopScan();
    $("aBarkod").value = code;
    kodTouched = false;
    checkBarcode();
    $("aAd").focus();
  }

  let sorguTimer = null, sorguUrun = null, sorguKod = "";

  function sorguKapat() {
    clearTimeout(sorguTimer);
    $("sorguKart").hidden = true;
    sorguUrun = null;
  }

  function sorguGoster(code) {
    clearTimeout(sorguTimer);
    const r = lookup(code);
    const k = $("sorguKart");
    k.hidden = false;
    k.classList.toggle("yok", !(r && r.product));
    if (!r || !r.product) {
      beep(false);
      sorguUrun = null;
      $("sorguAd").textContent = r && r.scale ? "Terazi etiketi, ürün bulunamadı" : "Ürün bulunamadı";
      $("sorguFiyat").textContent = "—";
      $("sorguAlt").textContent = code;
      $("sorguDuzenle").hidden = true;
      sorguKod = code;
      $("sorguEkle").hidden = !can("ekle") || !!(r && r.scale);
    } else {
      beep(true);
      const p = r.product;
      sorguUrun = p;
      $("sorguEkle").hidden = true;
      $("sorguAd").textContent = p.ad;
      $("sorguFiyat").textContent = tl(p.fiyat);
      let alt = p.birim ? lower(p.birim) + " fiyatı" : "";
      if (r.scale) {
        let kg, amount;
        if (r.scale.valType === "price") { amount = r.scale.amount; kg = p.fiyat ? amount / p.fiyat : 0; }
        else { kg = r.scale.kg; amount = kg * p.fiyat; }
        alt = "Bu etiket: " + kgFmt(kg) + " kg = " + tl(amount);
      }
      $("sorguAlt").textContent = alt;
      $("sorguDuzenle").hidden = !(fiyatSekmesi() && p.birimind);
    }
    const bar = $("sorguSure");
    bar.style.animation = "none";
    void bar.offsetWidth;
    bar.style.animation = "";
    sorguTimer = setTimeout(sorguKapat, 5000);
  }

  function sorguEkle() {
    const code = Scale.normCode(sorguKod);
    if (!code) return;
    sorguKapat();
    stopScan();
    switchTab("ekle");
    resetAddForm();
    $("aBarkod").value = code;
    kodTouched = false;
    checkBarcode();
    aMsg("");
    setTimeout(() => $("aAd").focus(), 100);
  }

  function sorguDuzenle() {
    const p = sorguUrun;
    if (!p) return;
    sorguKapat();
    stopScan();
    switchTab("fiyat");
    selectForPrice(p);
  }

  function handlePriceScan(code) {
    const r = lookup(code);
    if (r && r.product) {
      beep(true);
      stopScan();
      selectForPrice(r.product);
      return;
    }
    beep(false);
    fMsg(r && r.scale ? "Bu bir terazi etiketi. Ürünü isimle arayın." : "Bulunamadı: " + code, "err");
  }

  async function alanAdiKontrol() {
    try {
      const res = await apiFetch("api/alanadi", { cache: "no-store" });
      const j = await res.json();
      if (!j || !j.ok || !j.alan || !(j.kalanGun >= 0) || j.kalanGun > 30) return;
      const bugun = new Date().toISOString().slice(0, 10);
      if (store.get("alanUyariGun", "") === bugun) return;
      $("alanUyariYazi").textContent = j.alan + " alan adının süresi " + j.bitis + " tarihinde bitiyor (" + j.kalanGun + " gün kaldı). Kullanmaya devam edecekseniz Cloudflare'den yenileyin.";
      $("alanUyari").hidden = false;
      $("alanUyariKapat").onclick = () => { $("alanUyari").hidden = true; store.set("alanUyariGun", bugun); };
    } catch (e) { }
  }

  async function startLive() {
    clearTimeout(tekrarTimer);
    if (canliOrtam() && !(me && me.giris)) {
      const r = await loadRights();
      if (r === "giris") { girisGoster(); return false; }
    }
    if (await syncLive()) {
      if (!liveHazir) {
        if (canliOrtam() && !(me && me.giris)) {
          await loadRights();
          if (!(me && me.giris)) { tekrarTimer = setTimeout(startLive, 20000); return false; }
        }
        liveHazir = true;
        updatePriceTab();
        alanAdiKontrol();
        renderInfo();
        liveTimer = setInterval(syncLive, 60000);
        document.addEventListener("visibilitychange", () => { if (!document.hidden) syncLive(); });
      }
      return true;
    }
    if (!liveHazir && canliOrtam()) tekrarTimer = setTimeout(startLive, 20000);
    return false;
  }

  function renderInfo() {
    $("dbInfo").textContent = (live ? "● Canlı · " : (baglantiHata && canliOrtam() ? "● Bağlantı yok · " : "")) + (products.length ? products.length + " ürün" : "Liste yok");
    $("dbInfo").classList.toggle("kopuk", !live && !!baglantiHata && canliOrtam());
    const d = meta.updated ? new Date(meta.updated).toLocaleString("tr-TR") : "-";
    $("dataStats").textContent = products.length + " ürün kayıtlı. Son güncelleme: " + d + (meta.source ? " (" + meta.source + ")" : "");
  }

  const isKg = p => /^(kg|kilo|kilogram|gr|gram)$/i.test(String(p.birim || "").trim());

  function lookup(code) {
    code = Scale.normCode(code);
    if (!code) return null;
    const direct = byBarcode.get(code) || (code.length === 12 ? byBarcode.get("0" + code) : null) || (code.length === 13 && code[0] === "0" ? byBarcode.get(code.slice(1)) : null)
      || byStokKodu.get(code) || (code.length === 12 ? byStokKodu.get("0" + code) : null) || (code.length === 13 && code[0] === "0" ? byStokKodu.get(code.slice(1)) : null);
    if (direct) return { product: direct };
    const parsed = Scale.parseScale(code, settings);
    if (parsed) {
      const p = Scale.findByPlu(products, parsed, settings);
      if (p) return { product: p, scale: parsed };
      return { notFound: true, scale: parsed };
    }
    return { notFound: true };
  }

  function addFromCode(code, snap) {
    if (!products.length) { flash("Önce Ayarlar'dan ürün listesini yükle.", "warn"); return; }
    const r = lookup(code);
    if (r && r.notFound && r.scale && settings.unknownScale !== "none") {
      handleWeighed(r.scale, code, snap);
      return;
    }
    if (!r || r.notFound) {
      const extra = r && r.scale ? " (Terazi PLU " + r.scale.plu + ")" : "";
      flash("Bulunamadı: " + code + extra, "err");
      beep(false);
      return;
    }
    const p = r.product;
    beep(true);
    if (r.scale) {
      let kg, amount;
      if (r.scale.valType === "price") { amount = r.scale.amount; kg = p.fiyat ? amount / p.fiyat : 0; }
      else { kg = r.scale.kg; amount = kg * p.fiyat; }
      pushItem({ ad: p.ad, fiyat: p.fiyat, birim: "KG", miktar: kg, tutar: amount, kod: code, sabit: r.scale.valType === "price" });
      return;
    }
    addUnit(p, code);
  }

  function addUnit(p, code) {
    const existing = basket.find(i => i.kod === code && i.birim !== "KG" && !i.sabit && i.fiyat === p.fiyat);
    if (existing) { existing.miktar += 1; existing.tutar = existing.miktar * existing.fiyat; saveBasket(); flashItem(existing); return; }
    const birim = isKg(p) ? "ADET" : (p.birim || "ADET");
    pushItem({ ad: p.ad, fiyat: p.fiyat, birim, miktar: 1, tutar: p.fiyat, kod: code, birimind: p.birimind || 0 });
  }

  function addProduct(p) {
    const code = Scale.normCode(String(p.barkod || "").split(/[;,|\s]+/)[0]) || (p.plu ? "PLU" + p.plu : "AD" + p.ad);
    addUnit(p, code);
  }

  function pushItem(item) {
    item.id = Date.now() + Math.random();
    basket.unshift(item);
    saveBasket();
    flashItem(item);
  }

  function weighedName() { return settings.unknownName || "Ağırlıklı işlem"; }

  function handleWeighed(scale, code, snap) {
    if (scale.valType === "price") {
      beep(true);
      pushItem({ ad: weighedName(), fiyat: scale.amount, birim: "ADET", miktar: 1, tutar: scale.amount, kod: code, sabit: true });
      return;
    }
    const kg = scale.kg;
    if (settings.unknownScale === "ocr" && snap && window.LabelOCR) {
      busy = true;
      beep(true);
      flash("Etiket okunuyor… " + kgFmt(kg) + " kg", "warn");
      LabelOCR.readLabel(snap.canvas, kg, 9000, snap.corners).then(res => {
        if (res.match) pushWeighed(kg, res.match.unit, res.match.total, code, true);
        else { beep(false); askUnitPrice(kg, code, res.nums, null); }
      }).catch(() => askUnitPrice(kg, code, [], null)).finally(() => { busy = false; });
      return;
    }
    beep(true);
    askUnitPrice(kg, code, [], null);
  }

  function rememberUnit(u) {
    const list = store.get("recentUnits", []).filter(x => x !== u);
    list.unshift(u);
    store.set("recentUnits", list.slice(0, 4));
  }

  function pushWeighed(kg, unit, total, code, fromOcr) {
    rememberUnit(unit);
    pushItem({ ad: weighedName(), fiyat: unit, birim: "KG", miktar: kg, tutar: total != null ? total : round2(unit * kg), kod: code, agirlikli: true, okundu: !!fromOcr });
  }

  function askUnitPrice(kg, code, nums, item) {
    busy = true;
    const dlg = $("priceDialog");
    $("pTitle").textContent = weighedName() + " · " + kgFmt(kg) + " kg";
    const unitIn = $("pUnit"), totalIn = $("pTotal");
    unitIn.value = item ? String(item.fiyat).replace(".", ",") : "";
    totalIn.value = item ? String(item.tutar).replace(".", ",") : "";
    const num = v => parseFloat(String(v).replace(/\./g, "").replace(",", ".")) || 0;
    unitIn.oninput = () => { const u = num(unitIn.value); totalIn.value = u > 0 ? String(round2(u * kg)).replace(".", ",") : ""; };
    totalIn.oninput = () => { const t = num(totalIn.value); unitIn.value = t > 0 ? String(round2(t / kg)).replace(".", ",") : ""; };
    const quick = $("pQuick");
    quick.innerHTML = "";
    const addBtn = (label, fn) => { const b = document.createElement("button"); b.type = "button"; b.className = "btn sm"; b.textContent = label; b.onclick = fn; quick.appendChild(b); };
    store.get("recentUnits", []).forEach(u => addBtn(tl(u) + "/kg", () => { unitIn.value = String(u).replace(".", ","); unitIn.oninput(); }));
    const seen = new Set();
    (nums || []).filter(n => n.decimals === 2 && n.value > 0 && !seen.has(n.value) && seen.add(n.value)).slice(0, 3)
      .forEach(n => addBtn("Tutar " + tl(n.value), () => { totalIn.value = String(n.value).replace(".", ","); totalIn.oninput(); }));
    dlg.onclose = () => {
      busy = false;
      if (dlg.returnValue !== "ok") { if (!item) $("lastScan").hidden = true; return; }
      let u = num(unitIn.value), t = num(totalIn.value);
      if (!(u > 0) && t > 0) u = round2(t / kg);
      if (!(t > 0) && u > 0) t = round2(u * kg);
      if (!(u > 0)) return;
      if (item) { item.fiyat = u; item.tutar = t; item.okundu = false; rememberUnit(u); saveBasket(); flashItem(item); }
      else pushWeighed(kg, u, t, code, false);
    };
    dlg.returnValue = "";
    dlg.showModal();
    setTimeout(() => unitIn.focus(), 50);
  }

  function flashItem(item) {
    const qty = item.birim === "KG" ? kgFmt(item.miktar) + " kg" : item.miktar + " " + lower(item.birim || "adet");
    $("lastScan").hidden = false;
    $("lastScan").className = "last ok";
    $("lastScan").innerHTML = "<b></b><span></span><strong></strong>";
    $("lastScan").children[0].textContent = item.ad;
    $("lastScan").children[1].textContent = qty + " × " + tl(item.fiyat) + (item.birim === "KG" ? "/kg" : "") + (item.okundu ? " · etiketten okundu, kontrol et" : "");
    $("lastScan").children[2].textContent = tl(item.tutar);
  }

  function flash(text, kind) {
    if ($("tab-fiyat").classList.contains("active")) { fMsg(text, kind === "ok" ? "ok" : "err"); return; }
    if ($("tab-ekle").classList.contains("active")) { aMsg(text, kind === "ok" ? "ok" : "err"); return; }
    $("lastScan").hidden = false;
    $("lastScan").className = "last " + (kind || "");
    $("lastScan").textContent = text;
  }

  function saveBasket() { store.set("basket", basket); renderBasket(); }

  function renderBasket() {
    const ul = $("basket");
    ul.innerHTML = "";
    let total = 0;
    basket.forEach(item => {
      total += Number(item.tutar) || 0;
      const li = document.createElement("li");
      const qty = item.birim === "KG" ? kgFmt(item.miktar) + " kg" : item.miktar + " " + lower(item.birim || "adet");
      li.innerHTML = '<div class="info"><b></b><span class="muted small"></span></div><strong></strong><div class="acts"></div>';
      li.querySelector("b").textContent = item.ad;
      li.querySelector("span").textContent = qty + " × " + tl(item.fiyat) + (item.okundu ? " · etiketten" : "");
      li.querySelector("strong").textContent = tl(item.tutar);
      const acts = li.querySelector(".acts");
      if (!item.sabit) {
        const edit = document.createElement("button");
        edit.className = "btn sm"; edit.type = "button"; edit.textContent = "✎";
        edit.onclick = () => item.agirlikli ? askUnitPrice(item.miktar, item.kod, [], item) : askQty(item, q => { item.miktar = q; item.tutar = q * item.fiyat; saveBasket(); });
        acts.appendChild(edit);
      }
      const del = document.createElement("button");
      del.className = "btn sm danger"; del.type = "button"; del.textContent = "✕";
      del.onclick = () => { basket = basket.filter(i => i !== item); saveBasket(); };
      acts.appendChild(del);
      ul.appendChild(li);
    });
    $("total").textContent = tl(total);
    $("itemCount").textContent = basket.length + " kalem";
  }

  function askQty(p, cb) {
    const kg = isKg(p) || p.birim === "KG";
    $("qtyTitle").textContent = p.ad;
    $("qtyHint").textContent = kg ? "Gram yaz (fiyat " + tl(p.fiyat) + "/kg)" : "Adet yaz";
    $("qtyInput").value = p.miktar ? (kg ? Math.round(p.miktar * 1000) : p.miktar) : "";
    const quick = $("qtyQuick");
    quick.innerHTML = "";
    (kg ? [100, 250, 500, 1000] : [1, 2, 3, 5]).forEach(v => {
      const b = document.createElement("button");
      b.type = "button"; b.className = "btn sm"; b.textContent = kg ? (v >= 1000 ? v / 1000 + " kg" : v + " gr") : v;
      b.onclick = () => { $("qtyInput").value = v; };
      quick.appendChild(b);
    });
    const dlg = $("qtyDialog");
    dlg.onclose = () => {
      if (dlg.returnValue !== "ok") return;
      const n = parseFloat(String($("qtyInput").value).replace(",", "."));
      if (!(n > 0)) return;
      cb(kg ? n / 1000 : n);
    };
    dlg.returnValue = "";
    dlg.showModal();
    setTimeout(() => $("qtyInput").focus(), 50);
  }

  let audioCtx;
  function beep(ok) {
    try { if (navigator.vibrate) navigator.vibrate(ok ? 60 : [80, 60, 80]); } catch (e) { }
    try {
      audioCtx = audioCtx || new (window.AudioContext || window.webkitAudioContext)();
      const o = audioCtx.createOscillator(), g = audioCtx.createGain();
      o.frequency.value = ok ? 1500 : 300;
      g.gain.value = 0.08;
      o.connect(g); g.connect(audioCtx.destination);
      o.start(); o.stop(audioCtx.currentTime + (ok ? 0.08 : 0.25));
    } catch (e) { }
  }

  let stream = null, scanning = false, zxingReader = null, lastCode = "", lastTime = 0;
  let camTrack = null, torchOn = false, zoomOn = false, backCams = [], camIndex = -1, detectTimer = null, focusTimer = null;

  function snapshot(corners) {
    const v = $("video");
    if (!v.videoWidth) return null;
    const c = document.createElement("canvas");
    c.width = v.videoWidth;
    c.height = v.videoHeight;
    c.getContext("2d").drawImage(v, 0, 0, c.width, c.height);
    return { canvas: c, corners };
  }

  function cornersFromLine(pts) {
    if (!pts || pts.length < 2) return null;
    const a = pts[0], b = pts[pts.length - 1];
    const dx = b.x - a.x, dy = b.y - a.y, len = Math.hypot(dx, dy);
    if (len < 10) return null;
    const nx = -dy / len, ny = dx / len, h = len * 0.16;
    return [
      { x: a.x - nx * h, y: a.y - ny * h }, { x: b.x - nx * h, y: b.y - ny * h },
      { x: b.x + nx * h, y: b.y + ny * h }, { x: a.x + nx * h, y: a.y + ny * h }
    ];
  }

  let lastSeen = 0, scanMode = "hesap";

  function onDetected(code, corners) {
    const now = Date.now();
    if (code === lastCode && now - lastSeen < 1500) { lastSeen = now; return; }
    if (busy || $("priceDialog").open || $("qtyDialog").open || $("stokDialog").open) { if (code === lastCode) lastSeen = now; return; }
    if (now - lastTime < 600) return;
    lastCode = code; lastTime = now; lastSeen = now;
    if (scanMode === "sorgu") { sorguGoster(code); return; }
    if (scanMode === "stok") { stokScan(code); return; }
    if (scanMode === "fiyat") { handlePriceScan(code); return; }
    if (scanMode === "ekle") { handleAddScan(code); return; }
    const snap = Scale.parseScale(code, settings) ? snapshot(corners) : null;
    addFromCode(code, snap);
  }

  function videoConstraints(deviceId) {
    const v = { width: { ideal: 1920 }, height: { ideal: 1080 }, frameRate: { ideal: 30 } };
    if (deviceId) v.deviceId = { exact: deviceId };
    else v.facingMode = { ideal: "environment" };
    return { video: v, audio: false };
  }

  async function listBackCams() {
    try {
      const all = (await navigator.mediaDevices.enumerateDevices()).filter(d => d.kind === "videoinput");
      const back = all.filter(d => /back|rear|arka|environment/i.test(d.label));
      return back.length ? back : all;
    } catch (e) { return []; }
  }

  function pickMainCam(list) {
    const saved = store.get("camId", "");
    let i = list.findIndex(d => d.deviceId === saved);
    if (i >= 0) return i;
    i = list.findIndex(d => /camera2? 0\b|camera 0\b/i.test(d.label));
    if (i >= 0) return i;
    i = list.findIndex(d => !/wide|ultra|tele|geniş|depth|macro/i.test(d.label));
    return i >= 0 ? i : 0;
  }

  async function startScan() {
    if (scanning) return;
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      flash("Kamera bu tarayıcıda açılamıyor. Uygulamayı https adresinden aç.", "err");
      return;
    }
    $("scanner").hidden = false;
    $("scanner").classList.toggle("kisa", scanMode === "sorgu");
    scanning = true;
    lastCode = "";
    try {
      let s = await navigator.mediaDevices.getUserMedia(videoConstraints(null));
      backCams = await listBackCams();
      const current = s.getVideoTracks()[0].getSettings().deviceId;
      const want = backCams.length ? pickMainCam(backCams) : -1;
      if (want >= 0 && backCams[want].deviceId && backCams[want].deviceId !== current) {
        s.getTracks().forEach(t => t.stop());
        try { s = await navigator.mediaDevices.getUserMedia(videoConstraints(backCams[want].deviceId)); camIndex = want; }
        catch (e) { s = await navigator.mediaDevices.getUserMedia(videoConstraints(null)); camIndex = backCams.findIndex(d => d.deviceId === current); }
      } else camIndex = backCams.findIndex(d => d.deviceId === current);
      if (!scanning) { s.getTracks().forEach(t => t.stop()); return; }
      await runDecoder(s);
    } catch (e) {
      stopScan();
      flash("Kamera açılamadı: " + (e && e.message ? e.message : e), "err");
    }
  }

  async function runDecoder(s) {
    stream = s;
    const video = $("video");
    video.srcObject = s;
    await video.play().catch(() => { });
    tuneCamera(s);
    if (settings.unknownScale === "ocr" && window.LabelOCR) setTimeout(() => LabelOCR.warm().catch(() => { }), 1500);
    if ("BarcodeDetector" in window) {
      try {
        const formats = await BarcodeDetector.getSupportedFormats();
        const want = ["ean_13", "ean_8", "upc_a", "upc_e", "code_128", "code_39", "itf"].filter(f => formats.includes(f));
        if (want.length) {
          const detector = new BarcodeDetector({ formats: want });
          const loop = async () => {
            if (!scanning || stream !== s) return;
            try {
              const codes = await detector.detect(video);
              if (codes.length) onDetected(codes[0].rawValue, codes[0].cornerPoints && codes[0].cornerPoints.length === 4 ? codes[0].cornerPoints.map(p => ({ x: p.x, y: p.y })) : null);
            } catch (e) { }
            detectTimer = setTimeout(loop, 100);
          };
          loop();
          return;
        }
      } catch (e) { }
    }
    const hints = new Map();
    hints.set(ZXing.DecodeHintType.POSSIBLE_FORMATS, [ZXing.BarcodeFormat.EAN_13, ZXing.BarcodeFormat.EAN_8, ZXing.BarcodeFormat.UPC_A, ZXing.BarcodeFormat.UPC_E, ZXing.BarcodeFormat.CODE_128, ZXing.BarcodeFormat.CODE_39, ZXing.BarcodeFormat.ITF]);
    hints.set(ZXing.DecodeHintType.TRY_HARDER, true);
    const reader = new ZXing.MultiFormatReader();
    reader.setHints(hints);
    const c = document.createElement("canvas");
    const g = c.getContext("2d", { willReadFrequently: true });
    const loop = () => {
      if (!scanning || stream !== s) return;
      if (video.videoWidth) {
        const k = Math.min(1, 1280 / Math.max(video.videoWidth, video.videoHeight));
        c.width = Math.round(video.videoWidth * k);
        c.height = Math.round(video.videoHeight * k);
        g.drawImage(video, 0, 0, c.width, c.height);
        try {
          const res = reader.decodeWithState(new ZXing.BinaryBitmap(new ZXing.HybridBinarizer(new ZXing.HTMLCanvasElementLuminanceSource(c))));
          const pts = (res.getResultPoints() || []).map(p => ({ x: p.getX() / k, y: p.getY() / k }));
          onDetected(res.getText(), cornersFromLine(pts));
        } catch (e) { }
      }
      detectTimer = setTimeout(loop, 140);
    };
    loop();
  }

  function tuneCamera(s) {
    camTrack = s && s.getVideoTracks ? s.getVideoTracks()[0] : null;
    const caps = camTrack && camTrack.getCapabilities ? camTrack.getCapabilities() : {};
    if (caps.focusMode && caps.focusMode.includes("continuous")) camTrack.applyConstraints({ advanced: [{ focusMode: "continuous" }] }).catch(() => { });
    $("torch").hidden = !caps.torch;
    $("zoom").hidden = !(caps.zoom && caps.zoom.max >= 1.8);
    $("switchCam").hidden = backCams.length < 2;
    zoomOn = false; torchOn = false;
    const st = camTrack && camTrack.getSettings ? camTrack.getSettings() : {};
    const name = camIndex >= 0 && backCams[camIndex] ? "Kamera " + (camIndex + 1) + "/" + backCams.length : "";
    $("camInfo").textContent = [st.width && st.height ? st.width + "×" + st.height : "", name].filter(Boolean).join(" · ");
  }

  function toggleTorch() {
    if (!camTrack) return;
    torchOn = !torchOn;
    camTrack.applyConstraints({ advanced: [{ torch: torchOn }] }).catch(() => { torchOn = false; });
  }

  function toggleZoom() {
    if (!camTrack) return;
    const caps = camTrack.getCapabilities ? camTrack.getCapabilities() : {};
    if (!caps.zoom) return;
    zoomOn = !zoomOn;
    camTrack.applyConstraints({ advanced: [{ zoom: zoomOn ? Math.min(2, caps.zoom.max) : Math.max(1, caps.zoom.min) }] }).catch(() => { });
    $("zoom").textContent = zoomOn ? "🔍 Normal" : "🔍 Yakın";
  }

  function tapFocus(e) {
    if (!camTrack || !camTrack.getCapabilities) return;
    const caps = camTrack.getCapabilities();
    if (!caps.focusMode) return;
    const r = $("video").getBoundingClientRect();
    const adv = {};
    if (caps.focusMode.includes("single-shot")) adv.focusMode = "single-shot";
    else if (caps.focusMode.includes("manual") === false && caps.focusMode.includes("continuous")) adv.focusMode = "continuous";
    if ("pointsOfInterest" in caps || (camTrack.getSettings && "pointsOfInterest" in camTrack.getSettings())) {
      adv.pointsOfInterest = [{ x: (e.clientX - r.left) / r.width, y: (e.clientY - r.top) / r.height }];
    }
    camTrack.applyConstraints({ advanced: [adv] }).catch(() => { });
    clearTimeout(focusTimer);
    focusTimer = setTimeout(() => {
      if (camTrack && caps.focusMode.includes("continuous")) camTrack.applyConstraints({ advanced: [{ focusMode: "continuous" }] }).catch(() => { });
    }, 1500);
    const dot = $("focusDot");
    dot.style.left = (e.clientX - r.left) + "px";
    dot.style.top = (e.clientY - r.top) + "px";
    dot.hidden = false;
    setTimeout(() => { dot.hidden = true; }, 700);
  }

  async function switchCamera() {
    if (backCams.length < 2) return;
    const next = (camIndex + 1) % backCams.length;
    stopDecoder();
    try {
      const s = await navigator.mediaDevices.getUserMedia(videoConstraints(backCams[next].deviceId));
      camIndex = next;
      store.set("camId", backCams[next].deviceId);
      await runDecoder(s);
    } catch (e) {
      flash("Bu kamera açılamadı, sıradakini dene.", "warn");
      camIndex = next;
    }
  }

  function stopDecoder() {
    clearTimeout(detectTimer);
    if (zxingReader) { try { zxingReader.reset(); } catch (e) { } zxingReader = null; }
    if (stream) { stream.getTracks().forEach(t => t.stop()); stream = null; }
    camTrack = null;
  }

  function stopScan() {
    if (scanMode === "sorgu") sorguKapat();
    scanning = false;
    stopDecoder();
    torchOn = false; zoomOn = false;
    $("scanner").hidden = true;
    $("video").srcObject = null;
  }

  function search(q, limit) {
    q = lower(q).trim();
    if (!q) return products.slice(0, limit);
    const words = q.split(/\s+/);
    const first = words[0];
    const rank = p => {
      const kod = lower(p.kod || "");
      if (q === String(p.barkod) || (p.plu && q === String(p.plu)) || q === kod) return 0;
      const ad = lower(p.ad);
      const trz = kod.startsWith("trz-");
      const starts = ad.startsWith(q);
      if (trz && starts) return 1;
      const wordStart = ad.split(/[\s.,;:()\-\/]+/).some(w => w.startsWith(first));
      if (trz && wordStart) return 2;
      if (trz) return 3;
      if (starts) return 4;
      if (wordStart) return 5;
      return 6;
    };
    const found = [];
    products.forEach((p, i) => {
      const hay = lower(p.ad) + " " + p.barkod + " " + p.plu + " " + lower(p.kod || "");
      if (words.every(w => hay.includes(w))) found.push({ p, i, r: rank(p) });
    });
    found.sort((a, b) => a.r - b.r || a.i - b.i);
    return found.slice(0, limit).map(x => x.p);
  }

  const noop = () => { };

  function productLi(p, onClick) {
    const li = document.createElement("li");
    li.innerHTML = '<div class="info"><b></b><span class="muted small"></span></div><strong></strong>';
    li.querySelector("b").textContent = p.ad;
    li.querySelector("span").textContent = [p.kod && p.kod !== p.barkod ? p.kod : "", p.barkod, p.plu ? "PLU " + p.plu : ""].filter(Boolean).join(" · ");
    li.querySelector("strong").textContent = tl(p.fiyat);
    li.onclick = () => onClick(p);
    return li;
  }

  function renderSuggest() {
    const q = $("manualInput").value.trim();
    const ul = $("suggest");
    ul.innerHTML = "";
    if (q.length < 2 || /^\d{6,}$/.test(q)) return;
    search(q, 8).forEach(p => ul.appendChild(productLi(p, x => { addProduct(x); $("manualInput").value = ""; ul.innerHTML = ""; })));
  }

  function renderList() {
    const ul = $("productList");
    ul.innerHTML = "";
    const res = search($("searchInput").value, 200);
    if (!products.length) { ul.innerHTML = '<li class="muted">Henüz ürün yok. Ayarlar\'dan liste yükle.</li>'; return; }
    res.forEach(p => ul.appendChild(productLi(p, x => { addProduct(x); switchTab("hesap"); })));
  }

  let tzHata = "", tzYukleniyor = false;

  function tzSatirlar() {
    const gor = new Set();
    const urunler = [];
    products.forEach(p => {
      if (!/^TRZ-/i.test(p.kod || "") || !p.birimind || gor.has(p.kod)) return;
      gor.add(p.kod);
      urunler.push(p);
    });
    const cl = clData || [];
    return urunler.map(p => {
      const n = trzKod(p.kod);
      const plular = cl.filter(x => x.kod === n && x.plu < 1000).map(x => x.plu).sort((a, b) => a - b);
      return { p, plular };
    }).sort((a, b) => {
      const x = a.plular.length ? a.plular[0] : Infinity;
      const y = b.plular.length ? b.plular[0] : Infinity;
      if (x !== y) return x < y ? -1 : 1;
      return a.p.ad.localeCompare(b.p.ad, "tr-TR");
    });
  }

  function tzCiz() {
    const ul = $("tzList");
    ul.innerHTML = "";
    const q = lower($("tzAra").value.trim());
    const tum = tzSatirlar();
    const sonuc = tum.filter(s => !q || lower(s.p.ad).includes(q) || (/^\d+$/.test(q) && s.plular.some(n => String(n).startsWith(q))));
    $("tzSayi").textContent = tzYukleniyor ? "Okunuyor…" : sonuc.length + " ürün";
    const tikla = fiyatSekmesi();
    sonuc.slice(0, 400).forEach(s => {
      const li = document.createElement("li");
      li.className = "tz-satir";
      li.innerHTML = '<div class="tz-plu"></div><div class="info"><b></b></div><strong></strong>';
      const plu = li.querySelector(".tz-plu");
      if (s.plular.length) s.plular.forEach(n => { const d = document.createElement("div"); d.textContent = n; plu.appendChild(d); });
      else plu.textContent = "—";
      li.querySelector("b").textContent = s.p.ad;
      li.querySelector("strong").textContent = tl(s.p.fiyat);
      if (tikla) li.onclick = () => { switchTab("fiyat"); selectForPrice(s.p); };
      else li.style.cursor = "default";
      ul.appendChild(li);
    });
    if (!tum.length) ul.innerHTML = '<li class="muted">Terazi ürünü bulunamadı.</li>';
  }

  async function renderTerazi(onbellek) {
    tzCiz();
    if (tzYukleniyor) return;
    tzYukleniyor = true;
    $("tzSayi").textContent = "Okunuyor…";
    try {
      await loadCL(!onbellek);
      tzHata = "";
    } catch (e) {
      tzHata = (e && e.message) || "bilinmeyen hata";
    }
    tzYukleniyor = false;
    const m = $("tzMsg");
    m.textContent = tzHata ? "Terazi PLU'ları okunamadı: " + tzHata : "";
    m.className = tzHata ? "msg err" : "msg";
    tzCiz();
  }

  function switchTab(name) {
    document.querySelectorAll(".tab").forEach(t => t.classList.toggle("active", t.id === "tab-" + name));
    document.querySelectorAll(".tabs button").forEach(b => b.classList.toggle("active", b.dataset.tab === name));
    stopScan();
    if (name === "urunler") renderList();
    if (name === "terazi") renderTerazi(true);
    if (name === "stok") stokTeraziListe();
    if (name === "sorgu") { scanMode = "sorgu"; startScan(); window.scrollTo(0, 0); }
    if (name === "icerik" && can("icerik") && !icerikler) loadIcerikler();
    if (name === "ekle" && can("ekle") && (!$("aBirim").options.length || !$("aKdv").options.length)) loadLists();
  }

  const FIELDS = [
    { key: "barkod", label: "Barkod", hints: ["barkod", "barcode", "ean", "barkodno", "barkodu"] },
    { key: "ad", label: "Ürün adı", hints: ["malincinsi", "urunadi", "stokadi", "ad", "adi", "isim", "name", "aciklama", "tanim", "urun", "stokismi", "pluadi"] },
    { key: "fiyat", label: "Satış fiyatı", hints: ["satisfiyati1", "satisfiyati", "satisfiyat", "fiyat", "fiyati", "price", "birimfiyat", "unitprice", "perakende", "satis"] },
    { key: "birim", label: "Birim", hints: ["birim", "birimi", "unit", "olcubirimi", "birimadi"] },
    { key: "plu", label: "Terazi PLU no", hints: ["plu", "pluno", "plukodu", "terazino", "terazikodu", "itemcode"] },
    { key: "kod", label: "Stok kodu", hints: ["kod", "stokkodu", "stokkod", "urunkodu"] }
  ];
  const slug = s => lower(s).replace(/[ıi̇]/g, "i").replace(/ş/g, "s").replace(/ğ/g, "g").replace(/ü/g, "u").replace(/ö/g, "o").replace(/ç/g, "c").replace(/[^a-z0-9]/g, "");

  let importRows = [], importHeaders = [], importName = "";

  function decodeText(buf) {
    const utf = new TextDecoder("utf-8", { fatal: false }).decode(buf);
    if (!utf.includes("�")) return utf.replace(/^﻿/, "");
    try { return new TextDecoder("windows-1254").decode(buf); } catch (e) { return utf; }
  }

  function parseCsv(text) {
    const first = text.split(/\r?\n/)[0] || "";
    const delim = [";", "\t", ",", "|"].map(d => [d, first.split(d).length]).sort((a, b) => b[1] - a[1])[0][0];
    const rows = [];
    let row = [], cell = "", q = false;
    for (let i = 0; i < text.length; i++) {
      const c = text[i];
      if (q) {
        if (c === '"' && text[i + 1] === '"') { cell += '"'; i++; }
        else if (c === '"') q = false;
        else cell += c;
      } else if (c === '"') q = true;
      else if (c === delim) { row.push(cell); cell = ""; }
      else if (c === "\n" || c === "\r") {
        if (c === "\r" && text[i + 1] === "\n") i++;
        row.push(cell); cell = "";
        if (row.some(x => x.trim() !== "")) rows.push(row);
        row = [];
      } else cell += c;
    }
    row.push(cell);
    if (row.some(x => x.trim() !== "")) rows.push(row);
    return rows;
  }

  async function handleFile(file) {
    $("importMsg").textContent = "Okunuyor...";
    importName = file.name;
    const buf = await file.arrayBuffer();
    let table = [];
    const ext = file.name.split(".").pop().toLowerCase();
    try {
      if (ext === "json") {
        const data = JSON.parse(decodeText(buf));
        const arr = Array.isArray(data) ? data : (data.products || []);
        const headers = Array.from(new Set(arr.flatMap(o => Object.keys(o))));
        table = [headers].concat(arr.map(o => headers.map(h => o[h])));
      } else if (ext === "xlsx" || ext === "xls") {
        const wb = XLSX.read(buf, { type: "array" });
        const ws = wb.Sheets[wb.SheetNames[0]];
        table = XLSX.utils.sheet_to_json(ws, { header: 1, raw: true, defval: "" });
      } else {
        table = parseCsv(decodeText(buf));
      }
    } catch (e) {
      $("importMsg").textContent = "Dosya okunamadı: " + e.message;
      return;
    }
    table = table.filter(r => r && r.some(c => String(c).trim() !== ""));
    if (table.length < 2) { $("importMsg").textContent = "Dosyada veri bulunamadı."; return; }
    importHeaders = table[0].map((h, i) => String(h || "Sütun " + (i + 1)).trim());
    importRows = table.slice(1);
    buildMapping();
    $("importMsg").textContent = importRows.length + " satır okundu. Sütunları kontrol et ve Kaydet'e bas.";
  }

  function guess(field) {
    const slugs = importHeaders.map(slug);
    for (const h of field.hints) { const i = slugs.indexOf(h); if (i >= 0) return i; }
    for (const h of field.hints) { const i = slugs.findIndex(s => s.includes(h)); if (i >= 0) return i; }
    return -1;
  }

  function buildMapping() {
    const box = $("mapFields");
    box.innerHTML = "";
    const used = new Set();
    FIELDS.forEach(f => {
      const label = document.createElement("label");
      label.textContent = f.label;
      const sel = document.createElement("select");
      sel.id = "map-" + f.key;
      sel.innerHTML = '<option value="-1">— yok —</option>' + importHeaders.map((h, i) => '<option value="' + i + '"></option>').join("");
      importHeaders.forEach((h, i) => { sel.options[i + 1].textContent = h; });
      let g = guess(f);
      if (used.has(g)) g = -1;
      if (g >= 0) used.add(g);
      sel.value = String(g);
      sel.onchange = renderPreview;
      label.appendChild(sel);
      box.appendChild(label);
    });
    $("mapping").hidden = false;
    renderPreview();
  }

  function toNumber(v) {
    if (typeof v === "number") return v;
    let s = String(v || "").replace(/[^\d,.\-]/g, "");
    if (s.includes(",") && s.includes(".")) s = s.lastIndexOf(",") > s.lastIndexOf(".") ? s.replace(/\./g, "").replace(",", ".") : s.replace(/,/g, "");
    else if (s.includes(",")) s = s.replace(",", ".");
    return parseFloat(s) || 0;
  }

  function mapped() {
    const idx = {};
    FIELDS.forEach(f => { idx[f.key] = parseInt($("map-" + f.key).value, 10); });
    const cell = (r, k) => idx[k] >= 0 ? r[idx[k]] : "";
    return importRows.map(r => ({
      barkod: Scale.normCode(cell(r, "barkod")),
      ad: String(cell(r, "ad") || "").trim(),
      fiyat: Math.round(toNumber(cell(r, "fiyat")) * 100) / 100,
      birim: String(cell(r, "birim") || "").trim().toUpperCase(),
      plu: Scale.normCode(cell(r, "plu")),
      kod: String(cell(r, "kod") || "").trim()
    })).filter(p => p.ad);
  }

  function renderPreview() {
    const list = mapped().slice(0, 5);
    $("preview").innerHTML = "";
    const ul = document.createElement("ul");
    ul.className = "list";
    list.forEach(p => ul.appendChild(productLi(p, noop)));
    $("preview").appendChild(ul);
  }

  async function saveImport() {
    const list = mapped();
    if (!list.length) { $("importMsg").textContent = "Eşleşen ürün yok. Ürün adı sütununu seç."; return; }
    if ($("mergeMode").checked) {
      const key = p => p.barkod || (p.plu ? "PLU" + p.plu : "AD" + lower(p.ad));
      const m = new Map(products.map(p => [key(p), p]));
      list.forEach(p => m.set(key(p), Object.assign({}, m.get(key(p)) || {}, p)));
      products = Array.from(m.values());
    } else products = list;
    products.sort((a, b) => a.ad.localeCompare(b.ad, "tr"));
    meta = { updated: Date.now(), source: importName };
    try {
      await saveProducts();
      $("importMsg").textContent = list.length + " ürün kaydedildi. Toplam " + products.length + " ürün.";
      $("mapping").hidden = true;
      $("fileInput").value = "";
    } catch (e) {
      $("importMsg").textContent = "Kaydedilemedi: " + e.message;
    }
  }

  const SFIELDS = { sPrefixes: "prefixes", sLength: "length", sPluStart: "pluStart", sPluLen: "pluLen", sValStart: "valStart", sValLen: "valLen", sValType: "valType", sPluMatch: "pluMatch", sUnknown: "unknownScale", sUnknownName: "unknownName" };

  function fillSettings() { Object.entries(SFIELDS).forEach(([id, k]) => { $(id).value = settings[k]; }); }

  function readSettings() {
    const s = {};
    Object.entries(SFIELDS).forEach(([id, k]) => { s[k] = $(id).value; });
    ["length", "pluStart", "pluLen", "valStart", "valLen"].forEach(k => { s[k] = parseInt(s[k], 10) || 0; });
    return s;
  }

  function testScale() {
    const code = $("sTest").value.trim();
    if (!code) { $("sTestOut").textContent = ""; return; }
    const s = readSettings();
    const parsed = Scale.parseScale(code, s);
    if (!parsed) { $("sTestOut").textContent = "Bu ayarlarla terazi barkodu olarak çözülemedi."; return; }
    const p = Scale.findByPlu(products, parsed, s);
    let t = "PLU: " + parsed.plu + " · " + (parsed.valType === "price" ? "Tutar: " + tl(parsed.amount) : "Ağırlık: " + kgFmt(parsed.kg) + " kg");
    if (!Scale.eanValid(code)) t += " · Kontrol hanesi hatalı";
    if (p) t += " → " + p.ad + " (" + tl(parsed.valType === "price" ? parsed.amount : parsed.kg * p.fiyat) + ")";
    else if (s.unknownScale === "ocr") t += " → listede yok: '" + (s.unknownName || "Ağırlıklı işlem") + "', kg fiyatı etiketten okunur, okunamazsa sorulur";
    else if (s.unknownScale === "ask") t += " → listede yok: '" + (s.unknownName || "Ağırlıklı işlem") + "', kg fiyatı sorulur";
    else t += " → ürün listede bulunamadı";
    $("sTestOut").textContent = t;
  }

  function bind() {
    document.querySelectorAll(".tabs button").forEach(b => b.onclick = () => switchTab(b.dataset.tab));
    menuUygula();
    menuAyarKur();
    $("startScan").onclick = () => { scanMode = "hesap"; startScan(); };
    $("startSorgu").onclick = () => { scanMode = "sorgu"; startScan(); window.scrollTo(0, 0); };
    $("sorguKapat").onclick = sorguKapat;
    $("sorguDuzenle").onclick = sorguDuzenle;
    $("sorguEkle").onclick = sorguEkle;
    $("fScan").onclick = () => { scanMode = "fiyat"; fMsg(""); startScan(); };
    $("fForm").onsubmit = e => { e.preventDefault(); priceFind($("fSearch").value); };
    $("fSearch").oninput = renderPriceSuggest;
    $("fSave").onclick = savePrice;
    $("tKodBtn").onclick = toggleSameCodes;
    $("sScan").onclick = () => { scanMode = "stok"; sMsg(""); startScan(); window.scrollTo(0, 0); };
    $("sForm").onsubmit = e => { e.preventDefault(); stokAra($("sAra").value); };
    $("sTrzAra").oninput = stokTeraziListe;
    $("devirBox").addEventListener("toggle", () => { if ($("devirBox").open) devirDonemler(); });
    $("dvOnizle").onclick = devirOnizle;
    $("dvDevret").onclick = devirYap;
    ["dvKaynak", "dvHedef"].forEach(id => { $(id).onchange = () => { $("dvSonuc").hidden = true; devirVeri = null; dvMsg(""); }; });
    $("sdAdet").oninput = stokHesap;
    $("sdCarpan").oninput = stokHesap;
    $("sdEkle").onclick = stokEkle;
    $("girisForm").onsubmit = girisGonder;
    $("cikisBtn").onclick = cikisYap;
    $("ogreticiBtn").onclick = ogrBaslat;
    $("sifreAc").onclick = () => { $("sifreForm").hidden = !$("sifreForm").hidden; sfMsg(""); };
    $("sfVazgec").onclick = () => { $("sifreForm").reset(); $("sifreForm").hidden = true; sfMsg(""); };
    $("sifreForm").onsubmit = sifreDegistir;
    $("kulForm").onsubmit = kulEkle;
    $("kdForm").onsubmit = kulDuzenleKaydet;
    $("kdVazgec").onclick = () => $("kulDuzenle").close();
    $("kfRol").onchange = () => yetkiKilidi($("kfYetkiler"), $("kfRol").value);
    $("kdRol").onchange = () => yetkiKilidi($("kdYetkiler"), $("kdRol").value);
    yetkiKutulari($("kfYetkiler"), [], "kullanici");
    $("sdVazgec").onclick = () => $("stokDialog").close();
    ["sdAdet", "sdCarpan"].forEach(id => $(id).addEventListener("keydown", e => { if (e.key === "Enter") { e.preventDefault(); stokEkle(); } }));
    $("iForm").onsubmit = e => { e.preventDefault(); icerikAra($("iAra").value); };
    $("iAra").oninput = () => { if (!/^\d+$/.test($("iAra").value.trim())) icerikAra($("iAra").value); };
    $("iYeni").onclick = icerikYeniAc;
    $("iVazgec").onclick = () => { $("iCard").hidden = true; };
    $("iKaydet").onclick = icerikKaydet;
    ["iIcindekiler", "iKayit", "iAlerjenEk"].forEach(id => { $(id).oninput = icerikOnizle; });
    $("eOnizle").onclick = etiketOnizle;
    $("eYazdir").onclick = etiketYazdir;
    $("eBirim").onchange = () => { eCanvas = null; $("eResim").hidden = true; eMsg(""); };
    $("tKodGizle").onchange = () => { if (tKodOpen) showSameCodes(false); };
    $("fNew").oninput = recalcUnits;
    $("fCancel").onclick = () => { clearPriceSel(); fMsg(""); };
    $("aScan").onclick = () => { scanMode = "ekle"; aMsg(""); startScan(); window.scrollTo(0, 0); };
    $("aForm").onsubmit = saveProduct;
    $("aClear").onclick = () => { resetAddForm(); aMsg(""); };
    $("aTerazi").onchange = applyTerazi;
    $("aBarkod").oninput = checkBarcode;
    $("aKod").oninput = () => {
      kodTouched = true;
      if ($("aSabit").checked) $("aBarkod").value = sabitBarkod(trzKod($("aKod").value));
      updateClInfo();
    };
    $("aSabit").onchange = applySabit;
    kayitBagla("a");
    kayitBagla("f");
    $("fOkKaydet").onclick = saveOzel;
    $("bAgirlik").oninput = birimFiyatHesapla;
    $("bFiyat").oninput = () => { $("bFiyat").dataset.touched = "1"; };
    $("bEkle").onclick = birimEkle;
    $("aClIcerik").addEventListener("focus", icerikListesiDoldur);
    $("aClIcerik").addEventListener("input", icerikSecimGoster);
    $("aAd").addEventListener("input", () => { if (!clAdTouched) $("aClAd").value = clAdi($("aAd").value); });
    $("aClAd").oninput = () => { clAdTouched = true; };
    $("aClPlu").oninput = () => checkClPlu(false);
    $("aClOneri").onclick = () => { $("aClPlu").value = $("aClOneri").dataset.plu; checkClPlu(false); };
    $("guncelleBtn").onclick = appGuncelle;
    $("stopScan").onclick = stopScan;
    $("torch").onclick = toggleTorch;
    $("zoom").onclick = toggleZoom;
    $("switchCam").onclick = switchCamera;
    $("video").addEventListener("click", tapFocus);
    $("manualForm").onsubmit = e => {
      e.preventDefault();
      const v = $("manualInput").value.trim();
      if (!v) return;
      if (/^\d+$/.test(v)) { addFromCode(v); $("manualInput").value = ""; $("suggest").innerHTML = ""; return; }
      const r = search(v, 2);
      if (r.length === 1) { addProduct(r[0]); $("manualInput").value = ""; $("suggest").innerHTML = ""; }
    };
    $("manualInput").oninput = renderSuggest;
    $("clearBasket").onclick = () => { if (!basket.length || confirm("Hesap temizlensin mi?")) { basket = []; saveBasket(); $("lastScan").hidden = true; } };
    $("searchInput").oninput = renderList;
    $("tzAra").oninput = tzCiz;
    $("tzYenile").onclick = () => renderTerazi(false);
    $("fileInput").onchange = e => { if (e.target.files[0]) handleFile(e.target.files[0]); };
    $("saveImport").onclick = saveImport;
    Object.keys(SFIELDS).forEach(id => $(id).addEventListener("input", testScale));
    $("sTest").oninput = testScale;
    $("saveSettings").onclick = () => { settings = readSettings(); store.set("scaleSettings", settings); $("sTestOut").textContent = "Kaydedildi."; };
    $("exportJson").onclick = () => {
      const blob = new Blob([JSON.stringify(products, null, 1)], { type: "application/json" });
      const a = document.createElement("a");
      a.href = URL.createObjectURL(blob); a.download = "urunler.json"; a.click();
      setTimeout(() => URL.revokeObjectURL(a.href), 2000);
    };
    $("wipe").onclick = async () => { if (confirm("Tüm ürün listesi silinsin mi?")) { products = []; meta = { updated: null, source: "" }; await saveProducts(); } };
    document.addEventListener("visibilitychange", () => { if (document.hidden) stopScan(); });
  }

  bind();
  fillSettings();
  renderBasket();
  loadProducts().then(startLive);
  if ("serviceWorker" in navigator) navigator.serviceWorker.register("sw.js").catch(() => { });
})();

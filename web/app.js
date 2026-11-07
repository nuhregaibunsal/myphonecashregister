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
  let meta = { updated: null, source: "" };
  let settings = Object.assign({}, Scale.DEFAULTS, store.get("scaleSettings", {}));
  let basket = store.get("basket", []);

  function index() {
    byBarcode = new Map();
    products.forEach(p => {
      String(p.barkod || "").split(/[;,|\s]+/).map(Scale.normCode).filter(Boolean).forEach(b => byBarcode.set(b, p));
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
    index();
    renderInfo();
  }

  function renderInfo() {
    $("dbInfo").textContent = products.length ? products.length + " ürün" : "Liste yok";
    const d = meta.updated ? new Date(meta.updated).toLocaleString("tr-TR") : "-";
    $("dataStats").textContent = products.length + " ürün kayıtlı. Son güncelleme: " + d + (meta.source ? " (" + meta.source + ")" : "");
  }

  const isKg = p => /^(kg|kilo|kilogram|gr|gram)$/i.test(String(p.birim || "").trim());

  function lookup(code) {
    code = Scale.normCode(code);
    if (!code) return null;
    const direct = byBarcode.get(code) || (code.length === 12 ? byBarcode.get("0" + code) : null) || (code.length === 13 && code[0] === "0" ? byBarcode.get(code.slice(1)) : null);
    if (direct) return { product: direct };
    const parsed = Scale.parseScale(code, settings);
    if (parsed) {
      const p = Scale.findByPlu(products, parsed, settings);
      if (p) return { product: p, scale: parsed };
      return { notFound: true, scale: parsed };
    }
    return { notFound: true };
  }

  function addFromCode(code, viaCamera) {
    if (!products.length) { flash("Önce Ayarlar'dan ürün listesini yükle.", "warn"); return; }
    const r = lookup(code);
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
    if (isKg(p)) {
      askQty(p, kg => pushItem({ ad: p.ad, fiyat: p.fiyat, birim: "KG", miktar: kg, tutar: kg * p.fiyat, kod: code }));
      return;
    }
    const existing = basket.find(i => i.kod === code && i.birim !== "KG");
    if (existing) { existing.miktar += 1; existing.tutar = existing.miktar * existing.fiyat; saveBasket(); flashItem(existing); return; }
    pushItem({ ad: p.ad, fiyat: p.fiyat, birim: p.birim || "ADET", miktar: 1, tutar: p.fiyat, kod: code });
  }

  function addProduct(p) {
    const code = Scale.normCode(String(p.barkod || "").split(/[;,|\s]+/)[0]) || (p.plu ? "PLU" + p.plu : "AD" + p.ad);
    if (isKg(p)) askQty(p, kg => pushItem({ ad: p.ad, fiyat: p.fiyat, birim: "KG", miktar: kg, tutar: kg * p.fiyat, kod: code }));
    else pushItem({ ad: p.ad, fiyat: p.fiyat, birim: p.birim || "ADET", miktar: 1, tutar: p.fiyat, kod: code });
  }

  function pushItem(item) {
    item.id = Date.now() + Math.random();
    basket.unshift(item);
    saveBasket();
    flashItem(item);
  }

  function flashItem(item) {
    const qty = item.birim === "KG" ? kgFmt(item.miktar) + " kg" : item.miktar + " " + lower(item.birim || "adet");
    $("lastScan").hidden = false;
    $("lastScan").className = "last ok";
    $("lastScan").innerHTML = "<b></b><span></span><strong></strong>";
    $("lastScan").children[0].textContent = item.ad;
    $("lastScan").children[1].textContent = qty + " × " + tl(item.fiyat) + (item.birim === "KG" ? "/kg" : "");
    $("lastScan").children[2].textContent = tl(item.tutar);
  }

  function flash(text, kind) {
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
      li.querySelector("span").textContent = qty + " × " + tl(item.fiyat);
      li.querySelector("strong").textContent = tl(item.tutar);
      const acts = li.querySelector(".acts");
      if (!item.sabit) {
        const edit = document.createElement("button");
        edit.className = "btn sm"; edit.type = "button"; edit.textContent = "✎";
        edit.onclick = () => askQty(item, q => { item.miktar = q; item.tutar = q * item.fiyat; saveBasket(); });
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

  function onDetected(code) {
    const now = Date.now();
    if (code === lastCode && now - lastTime < 2500) return;
    if (now - lastTime < 900) return;
    lastCode = code; lastTime = now;
    addFromCode(code, true);
  }

  async function startScan() {
    if (scanning) return;
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      flash("Kamera bu tarayıcıda açılamıyor. Uygulamayı https adresinden aç.", "err");
      return;
    }
    $("scanner").hidden = false;
    scanning = true;
    const video = $("video");
    const constraints = { video: { facingMode: { ideal: "environment" }, width: { ideal: 1280 }, height: { ideal: 720 } }, audio: false };
    try {
      if ("BarcodeDetector" in window) {
        const formats = await BarcodeDetector.getSupportedFormats();
        const want = ["ean_13", "ean_8", "upc_a", "upc_e", "code_128", "code_39", "itf"].filter(f => formats.includes(f));
        if (want.length) {
          const detector = new BarcodeDetector({ formats: want });
          stream = await navigator.mediaDevices.getUserMedia(constraints);
          video.srcObject = stream;
          await video.play();
          const loop = async () => {
            if (!scanning) return;
            try {
              const codes = await detector.detect(video);
              if (codes.length) onDetected(codes[0].rawValue);
            } catch (e) { }
            setTimeout(loop, 120);
          };
          loop();
          return;
        }
      }
      const hints = new Map();
      hints.set(ZXing.DecodeHintType.POSSIBLE_FORMATS, [ZXing.BarcodeFormat.EAN_13, ZXing.BarcodeFormat.EAN_8, ZXing.BarcodeFormat.UPC_A, ZXing.BarcodeFormat.UPC_E, ZXing.BarcodeFormat.CODE_128, ZXing.BarcodeFormat.CODE_39, ZXing.BarcodeFormat.ITF]);
      hints.set(ZXing.DecodeHintType.TRY_HARDER, true);
      zxingReader = new ZXing.BrowserMultiFormatReader(hints, 150);
      await zxingReader.decodeFromConstraints(constraints, video, (result) => {
        if (result && scanning) onDetected(result.getText());
      });
    } catch (e) {
      stopScan();
      flash("Kamera açılamadı: " + (e && e.message ? e.message : e), "err");
    }
  }

  function stopScan() {
    scanning = false;
    $("scanner").hidden = true;
    if (zxingReader) { try { zxingReader.reset(); } catch (e) { } zxingReader = null; }
    if (stream) { stream.getTracks().forEach(t => t.stop()); stream = null; }
    $("video").srcObject = null;
  }

  function search(q, limit) {
    q = lower(q).trim();
    if (!q) return products.slice(0, limit);
    const words = q.split(/\s+/);
    const out = [];
    for (const p of products) {
      const hay = lower(p.ad) + " " + p.barkod + " " + p.plu;
      if (words.every(w => hay.includes(w))) { out.push(p); if (out.length >= limit) break; }
    }
    return out;
  }

  function productLi(p, onClick) {
    const li = document.createElement("li");
    li.innerHTML = '<div class="info"><b></b><span class="muted small"></span></div><strong></strong>';
    li.querySelector("b").textContent = p.ad;
    li.querySelector("span").textContent = [p.barkod, p.plu ? "PLU " + p.plu : ""].filter(Boolean).join(" · ");
    li.querySelector("strong").textContent = tl(p.fiyat) + (isKg(p) ? "/kg" : "");
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

  function switchTab(name) {
    document.querySelectorAll(".tab").forEach(t => t.classList.toggle("active", t.id === "tab-" + name));
    document.querySelectorAll(".tabs button").forEach(b => b.classList.toggle("active", b.dataset.tab === name));
    if (name !== "hesap") stopScan();
    if (name === "urunler") renderList();
  }

  const FIELDS = [
    { key: "barkod", label: "Barkod", hints: ["barkod", "barcode", "ean", "barkodno", "barkodu"] },
    { key: "ad", label: "Ürün adı", hints: ["malincinsi", "urunadi", "stokadi", "ad", "adi", "isim", "name", "aciklama", "tanim", "urun", "stokismi", "pluadi"] },
    { key: "fiyat", label: "Satış fiyatı", hints: ["satisfiyati1", "satisfiyati", "satisfiyat", "fiyat", "fiyati", "price", "birimfiyat", "unitprice", "perakende", "satis"] },
    { key: "birim", label: "Birim", hints: ["birim", "birimi", "unit", "olcubirimi", "birimadi"] },
    { key: "plu", label: "Terazi PLU no", hints: ["plu", "pluno", "plukodu", "terazino", "terazikodu", "itemcode", "kod", "stokkodu"] }
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
      plu: Scale.normCode(cell(r, "plu"))
    })).filter(p => p.ad);
  }

  function renderPreview() {
    const list = mapped().slice(0, 5);
    $("preview").innerHTML = "";
    const ul = document.createElement("ul");
    ul.className = "list";
    list.forEach(p => ul.appendChild(productLi(p, () => { })));
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

  const SFIELDS = { sPrefixes: "prefixes", sLength: "length", sPluStart: "pluStart", sPluLen: "pluLen", sValStart: "valStart", sValLen: "valLen", sValType: "valType", sPluMatch: "pluMatch" };

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
    t += p ? " → " + p.ad + " (" + tl(parsed.valType === "price" ? parsed.amount : parsed.kg * p.fiyat) + ")" : " → ürün listede bulunamadı";
    $("sTestOut").textContent = t;
  }

  function bind() {
    document.querySelectorAll(".tabs button").forEach(b => b.onclick = () => switchTab(b.dataset.tab));
    $("startScan").onclick = startScan;
    $("stopScan").onclick = stopScan;
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
  loadProducts();
  if ("serviceWorker" in navigator) navigator.serviceWorker.register("sw.js").catch(() => { });
})();

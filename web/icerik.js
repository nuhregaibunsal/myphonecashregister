(function () {
  const KAYIT = "TR-41-K-033887";
  const ALERJEN = [
    ["gluten", "Gluten", "gluten"],
    ["yerfistigi", "Yer fıstığı", "yer fıstığı"],
    ["findik", "Fındık", "fındık"],
    ["badem", "Badem", "badem"],
    ["ceviz", "Ceviz", "ceviz"],
    ["kaju", "Kaju", "kaju"],
    ["antep", "Antep fıstığı", "antep fıstığı"],
    ["pikan", "Pikan cevizi", "pikan cevizi"],
    ["makadamya", "Makadamya", "makadamya"],
    ["brezilya", "Brezilya cevizi", "brezilya cevizi"],
    ["soya", "Soya", "soya"],
    ["sut", "Süt", "süt"],
    ["sulfit", "Sülfit", "sülfit"],
    ["lupin", "Acı bakla (lupin)", "acı bakla"]
  ];
  const BESIN = [
    ["yag", "Yağ (g)"],
    ["doymus", "Doymuş Yağ (g)"],
    ["karb", "Karbohidrat (g)"],
    ["seker", "Şekerler (g)"],
    ["lif", "Lif (g)"],
    ["protein", "Protein (g)"],
    ["tuz", "Tuz (g)"]
  ];
  const BASLIK = "~2Enerji ve ~2Besin ~2Öğeleri 100 gr için";

  const kalin = t => t.split(/\s+/).filter(Boolean).map(w => "~2" + w).join(" ");
  const buyukIlk = t => t ? t.charAt(0).toLocaleUpperCase("tr-TR") + t.slice(1) : t;
  const norm = t => String(t || "").toLocaleLowerCase("tr-TR").replace(/ı/g, "i").replace(/\s+/g, " ").trim();

  function olustur(v) {
    const satir = [];
    satir.push("~2İçindekiler: " + String(v.icindekiler || "").trim());
    satir.push(String(v.kayit || KAYIT).trim());
    const parca = [];
    const icerir = ALERJEN.filter(a => v.alerjen && v.alerjen[a[0]] === "icerir").map(a => a[2]);
    const eser = ALERJEN.filter(a => v.alerjen && v.alerjen[a[0]] === "eser").map(a => a[2]);
    icerir.forEach(a => parca.push(a + " içerir"));
    if (eser.length) parca.push(eser.join(", ") + " eser miktarda içerebilir");
    const serbest = String(v.alerjenEk || "").trim().replace(/[.,;\s]+$/, "");
    if (serbest) parca.push(serbest);
    if (parca.length) satir.push("~2Alerjen ~2Uyarısı: " + kalin(buyukIlk(parca.join(", ")) + "."));
    const b = v.besin || {};
    const dolu = k => String(b[k] == null ? "" : b[k]).trim();
    const besinSatir = [];
    const kj = dolu("kj"), kcal = dolu("kcal");
    if (kj && kcal) besinSatir.push("Enerji(kJ/Kcal) " + kj + "/" + kcal);
    else if (kcal) besinSatir.push("Enerji(Kcal) " + kcal);
    else if (kj) besinSatir.push("Enerji(kJ) " + kj);
    BESIN.forEach(([k, ad]) => { if (dolu(k)) besinSatir.push(ad + " " + dolu(k)); });
    if (besinSatir.length) { satir.push(BASLIK); satir.push(...besinSatir); }
    return satir.join("\r\n");
  }

  function coz(metin) {
    const v = { icindekiler: "", kayit: KAYIT, alerjen: {}, alerjenEk: "", besin: {}, taninmayan: [] };
    const lines = String(metin || "").split(/\r?\n/).map(l => l.trim()).filter(Boolean);
    for (const l of lines) {
      const duz = l.replace(/~2/g, "").replace(/\s+/g, " ").trim();
      let m;
      if ((m = duz.match(/^içindekiler\s*:\s*(.*)$/i)) || (m = duz.match(/^İçindekiler\s*:\s*(.*)$/))) { v.icindekiler = m[1].trim(); continue; }
      if (/^TR-\d+-[A-Z]-\d+$/i.test(duz)) { v.kayit = duz; continue; }
      if ((m = duz.match(/^Alerjen Uyarısı\s*:\s*(.*)$/i))) {
        const kalan = [];
        m[1].replace(/\.\s*$/, "").split(/,\s*/).forEach(p => {
          const t = p.trim();
          let mm;
          if ((mm = t.match(/^(.+?) içerir$/i))) {
            const a = ALERJEN.find(x => norm(x[2]) === norm(mm[1]) || norm(x[1]) === norm(mm[1]) || norm(x[2]).replace(/ /g, "") === norm(mm[1]).replace(/ /g, ""));
            if (a) { v.alerjen[a[0]] = "icerir"; return; }
          }
          if ((mm = t.match(/^(.+?) eser miktarda içerebilir$/i))) {
            const a = ALERJEN.find(x => norm(x[2]) === norm(mm[1]));
            if (a) { v.alerjen[a[0]] = "eser"; return; }
          }
          const a = ALERJEN.find(x => norm(x[2]) === norm(t));
          if (a && kalan.length === 0 && /eser miktarda/i.test(m[1])) { v.alerjen[a[0]] = "eser"; return; }
          if (t) kalan.push(t);
        });
        v.alerjenEk = kalan.join(", ");
        continue;
      }
      if (/^Enerji ?ve ?Besin ?Öğeleri/i.test(duz)) continue;
      if ((m = duz.match(/^Enerji\s*\(kJ\/Kcal\)\s*([\d.,]+)\s*\/\s*([\d.,]+)/i))) { v.besin.kj = m[1]; v.besin.kcal = m[2]; continue; }
      if ((m = duz.match(/^Enerji\s*\(Kcal\)\s*([\d.,]+)/i))) { v.besin.kcal = m[1]; continue; }
      if ((m = duz.match(/^Enerji\s*\(kJ\)\s*([\d.,]+)/i))) { v.besin.kj = m[1]; continue; }
      const b = BESIN.find(([k, ad]) => norm(duz).startsWith(norm(ad)));
      if (b) { v.besin[b[0]] = duz.slice(b[1].length).trim(); continue; }
      v.taninmayan.push(l);
    }
    if (!v.icindekiler && v.taninmayan.length && !Object.keys(v.besin).length && !Object.keys(v.alerjen).length) {
      v.icindekiler = v.taninmayan.map(t => t.replace(/~2/g, "")).join(" ");
      v.taninmayan = [];
    }
    return v;
  }

  function html(metin) {
    const esc = s => s.replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
    return String(metin || "").split(/\r?\n/).map(l => esc(l).replace(/~2(\S+)/g, "<b>$1</b>")).join("<br>");
  }

  const api = { ALERJEN, BESIN, KAYIT, olustur, coz, html, kalin };
  if (typeof window !== "undefined") window.Icerik = api;
  if (typeof module !== "undefined") module.exports = api;
})();

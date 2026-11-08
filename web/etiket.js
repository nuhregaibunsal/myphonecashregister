(function () {
  const MM = 8;
  const PT = 203 / 72;
  const BASE = "vendor/etiket/";
  const LATIN = "U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+0304,U+0308,U+0329,U+2000-206F,U+20AC,U+2122,U+2191,U+2193,U+2212,U+2215,U+FEFF,U+FFFD";
  const EXT = "U+0100-02BA,U+02BD-02C5,U+02C7-02CC,U+02CE-02D7,U+02DD-02FF,U+1D00-1DBF,U+1E00-1E9F,U+1EF2-1EFF,U+2020,U+20A0-20AB,U+20AD-20C0,U+2113,U+2C60-2C7F,U+A720-A7FF";
  const FONTS = [
    ["EtiketKalin", "archivo-black-latin-400-normal.woff2", "400", LATIN],
    ["EtiketKalin", "archivo-black-latin-ext-400-normal.woff2", "400", EXT],
    ["EtiketSerif", "tinos-latin-400-normal.woff2", "400", LATIN],
    ["EtiketSerif", "tinos-latin-ext-400-normal.woff2", "400", EXT],
    ["EtiketSans", "arimo-latin-700-normal.woff2", "700", LATIN],
    ["EtiketSans", "arimo-latin-ext-700-normal.woff2", "700", EXT]
  ];
  const FAM = { kalin: "EtiketKalin", serif: "EtiketSerif", sans: "EtiketSans" };
  let ready = null;

  function loadImg(src) {
    return new Promise((res, rej) => { const i = new Image(); i.onload = () => res(i); i.onerror = () => rej(new Error(src)); i.src = src; });
  }

  function hazirla() {
    if (ready) return ready;
    ready = (async () => {
      const faces = FONTS.map(([fam, file, weight, range]) => new FontFace(fam, "url(" + BASE + file + ")", { weight, unicodeRange: range }));
      faces.forEach(f => document.fonts.add(f));
      await Promise.all(faces.map(f => f.load()));
      const [tl, yerli] = await Promise.all([loadImg(BASE + "tl.png"), loadImg(BASE + "yerli.png")]);
      return { tl, yerli };
    })();
    ready.catch(() => { ready = null; });
    return ready;
  }

  const L = [0x0D, 0x19, 0x13, 0x3D, 0x23, 0x31, 0x2F, 0x3B, 0x37, 0x0B];
  const G = [0x27, 0x33, 0x1B, 0x21, 0x1D, 0x39, 0x05, 0x11, 0x09, 0x17];
  const R = [0x72, 0x66, 0x6C, 0x42, 0x5C, 0x4E, 0x50, 0x44, 0x48, 0x74];
  const PAR = ["LLLLLL", "LLGLGG", "LLGGLG", "LLGGGL", "LGLLGG", "LGGLLG", "LGGGLL", "LGLGLG", "LGLGGL", "LGGLGL"];

  function ean13(kod) {
    let s = String(kod || "").replace(/\D/g, "");
    if (!s || s.length > 13) return null;
    if (s.length < 13) s = s.padStart(12, "0").slice(-12);
    const d = s.slice(0, 12).split("").map(Number);
    const cs = (10 - (d.reduce((a, v, i) => a + v * (i % 2 ? 3 : 1), 0) % 10)) % 10;
    if (s.length === 12) s += cs;
    const bits = ["101"];
    const p = PAR[+s[0]];
    for (let i = 1; i <= 6; i++) bits.push((p[i - 1] === "L" ? L[+s[i]] : G[+s[i]]).toString(2).padStart(7, "0"));
    bits.push("01010");
    for (let i = 7; i <= 12; i++) bits.push(R[+s[i]].toString(2).padStart(7, "0"));
    bits.push("101");
    return { metin: s, bits: bits.join("") };
  }

  const iki = n => String(n).padStart(2, "0");
  const gun = d => iki(d.getDate()) + "." + iki(d.getMonth() + 1) + "." + d.getFullYear();
  function tarihYaz(v) {
    if (!v) return "";
    const d = new Date(v);
    if (isNaN(d)) return String(v);
    return gun(d) + " " + iki(d.getHours()) + ":" + iki(d.getMinutes()) + ":" + iki(d.getSeconds());
  }
  const fiyatYaz = n => (Math.round((Number(n) || 0) * 100) / 100).toFixed(2).replace(".", ",");

  function degerler(v) {
    const ag = Number(v.agirlik) || 0;
    const tett = new Date();
    tett.setDate(tett.getDate() + 366);
    return {
      ad: String(v.ad || ""),
      fiyat: fiyatYaz(v.fiyat),
      birimFiyat: ag > 0 ? (Number(v.fiyat) / ag).toFixed(2) : "0.00",
      tarih: tarihYaz(v.tarih),
      tett: gun(tett),
      kod6: String(v.kod6 || ""),
      kod10: String(v.kod10 || ""),
      barkod: String(v.barkod || "")
    };
  }

  const doldur = (s, d) => String(s || "").replace(/\{(\w+)\}/g, (m, k) => (k in d ? d[k] : ""));

  function kutuAc(ctx, o) {
    const yon = ((o.yon || 0) % 360 + 360) % 360;
    ctx.save();
    ctx.translate((o.x + o.w / 2) * MM, (o.y + o.h / 2) * MM);
    ctx.rotate(yon * Math.PI / 180);
    const yan = yon % 180 !== 0;
    return { bw: (yan ? o.h : o.w) * MM, bh: (yan ? o.w : o.h) * MM };
  }

  function metin(ctx, o, txt) {
    const lines = txt.split("\n");
    const { bw, bh } = kutuAc(ctx, o);
    const fam = FAM[o.font] || FAM.sans;
    let s = Math.max(4, Math.round((o.pt || 8) * PT));
    const sigar = () => {
      ctx.font = s + "px " + fam;
      return lines.every(l => ctx.measureText(l).width <= bw - 2) && (lines.length === 1 || lines.length * s * 1.1 <= bh + 2);
    };
    while (s > 6 && !sigar()) s--;
    ctx.fillStyle = o.beyaz ? "#fff" : "#000";
    ctx.textBaseline = "middle";
    const hiza = o.hiza || "orta";
    ctx.textAlign = hiza === "sol" ? "left" : hiza === "sag" ? "right" : "center";
    const x = hiza === "sol" ? -bw / 2 + 2 : hiza === "sag" ? bw / 2 - 2 : 0;
    lines.forEach((l, i) => ctx.fillText(l, x, (i - (lines.length - 1) / 2) * s * 1.1));
    ctx.restore();
  }

  function barkod(ctx, o, kod) {
    const b = ean13(kod);
    const { bw, bh } = kutuAc(ctx, o);
    ctx.fillStyle = "#000";
    const yazi = Math.round((o.pt || 7) * PT);
    if (b) {
      const m = Math.max(1, Math.floor(bw / b.bits.length));
      const x0 = -Math.round(b.bits.length * m / 2);
      const barH = bh - yazi - 2;
      for (let i = 0; i < b.bits.length; i++) if (b.bits[i] === "1") ctx.fillRect(x0 + i * m, -bh / 2, m, barH);
      ctx.font = yazi + "px " + FAM.sans;
      ctx.textAlign = "center"; ctx.textBaseline = "bottom";
      ctx.fillText(b.metin, 0, bh / 2);
    } else if (kod) {
      ctx.font = yazi + "px " + FAM.sans;
      ctx.textAlign = "center"; ctx.textBaseline = "middle";
      ctx.fillText(kod, 0, 0);
    }
    ctx.restore();
  }

  function resim(ctx, o, img) {
    const { bw, bh } = kutuAc(ctx, o);
    ctx.drawImage(img, -bw / 2, -bh / 2, bw, bh);
    ctx.restore();
  }

  async function ciz(v, canvas, secenek) {
    const img = await hazirla();
    const duzen = (secenek && secenek.duzen) || window.ETIKET_DUZEN;
    const d = degerler(v);
    const yerli = d.kod10.trim().toLocaleUpperCase("tr-TR") === "TURKIYE";
    const RW = Math.round(duzen.genislik * MM), RH = Math.round(duzen.yukseklik * MM);
    const r = document.createElement("canvas");
    r.width = RW; r.height = RH;
    const ctx = r.getContext("2d");
    ctx.fillStyle = "#fff"; ctx.fillRect(0, 0, RW, RH);
    ctx.strokeStyle = "#000"; ctx.lineWidth = 1;
    for (const o of duzen.ogeler) {
      if (o.kosul === "yerli" && !yerli) continue;
      if (o.kosul === "yerliDegil" && yerli) continue;
      if (o.tip === "kutu") { ctx.fillStyle = "#000"; ctx.fillRect(o.x * MM, o.y * MM, o.w * MM, o.h * MM); }
      else if (o.tip === "cerceve") ctx.strokeRect(Math.round(o.x * MM) + 0.5, Math.round(o.y * MM) + 0.5, Math.round(o.w * MM), Math.round(o.h * MM));
      else if (o.tip === "cizgi") { ctx.beginPath(); ctx.moveTo(Math.round(o.x * MM) + 0.5, Math.round(o.y * MM) + 0.5); ctx.lineTo(Math.round(o.x2 * MM) + 0.5, Math.round(o.y2 * MM) + 0.5); ctx.stroke(); }
      else if (o.tip === "metin") metin(ctx, o, doldur(o.deger, d));
      else if (o.tip === "barkod") barkod(ctx, o, doldur(o.deger, d));
      else if (o.tip === "resim" && img[o.kaynak]) resim(ctx, o, img[o.kaynak]);
    }
    const id = ctx.getImageData(0, 0, RW, RH);
    const p = id.data;
    for (let i = 0; i < p.length; i += 4) {
      const k = (p[i] * 299 + p[i + 1] * 587 + p[i + 2] * 114) / 1000 < 150 ? 0 : 255;
      p[i] = p[i + 1] = p[i + 2] = k; p[i + 3] = 255;
    }
    ctx.putImageData(id, 0, 0);
    if (secenek && secenek.okuma) return r;
    const c = canvas || document.createElement("canvas");
    c.width = RH; c.height = RW;
    const pc = c.getContext("2d");
    pc.translate(0, RW);
    pc.rotate(-Math.PI / 2);
    pc.drawImage(r, 0, 0);
    pc.setTransform(1, 0, 0, 1, 0, 0);
    return c;
  }

  window.Etiket = { ciz, ean13, hazirla, degerler };
})();

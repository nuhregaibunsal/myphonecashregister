(function () {
  const W = 304, H = 790;
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
    for (let i = 1; i <= 6; i++) {
      const v = p[i - 1] === "L" ? L[+s[i]] : G[+s[i]];
      bits.push(v.toString(2).padStart(7, "0"));
    }
    bits.push("01010");
    for (let i = 7; i <= 12; i++) bits.push(R[+s[i]].toString(2).padStart(7, "0"));
    bits.push("101");
    return { metin: s, bits: bits.join("") };
  }

  function fitFont(ctx, text, family, size, maxW) {
    let s = size;
    ctx.font = s + "px " + family;
    while (s > 8 && ctx.measureText(text).width > maxW) { s -= 1; ctx.font = s + "px " + family; }
    return s;
  }

  function dikey(ctx, text, x, yAlt, yUst, family, size) {
    if (!text) return;
    const s = fitFont(ctx, text, family, size, yAlt - yUst - 4);
    const w = ctx.measureText(text).width;
    const y = (yAlt + yUst) / 2 + w / 2;
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(-Math.PI / 2);
    ctx.textBaseline = "top";
    ctx.fillText(text, 0, 0);
    ctx.restore();
    return s;
  }

  function cerceve(ctx, x1, y1, x2, y2) { ctx.strokeRect(x1 + 0.5, y1 + 0.5, x2 - x1, y2 - y1); }
  function cizgi(ctx, x1, y1, x2, y2) { ctx.beginPath(); ctx.moveTo(x1 + 0.5, y1 + 0.5); ctx.lineTo(x2 + 0.5, y2 + 0.5); ctx.stroke(); }

  const iki = n => String(n).padStart(2, "0");
  function tarihYaz(v) {
    if (!v) return "";
    const d = new Date(v);
    if (isNaN(d)) return String(v);
    return d.getDate() + "." + iki(d.getMonth() + 1) + "." + d.getFullYear() + " " + d.getHours() + ":" + iki(d.getMinutes()) + ":" + iki(d.getSeconds());
  }
  const fiyatYaz = n => (Math.round((Number(n) || 0) * 100) / 100).toFixed(2).replace(".", ",");

  async function ciz(v, canvas) {
    const img = await hazirla();
    const c = canvas || document.createElement("canvas");
    c.width = W; c.height = H;
    const ctx = c.getContext("2d");
    ctx.fillStyle = "#fff"; ctx.fillRect(0, 0, W, H);
    ctx.fillStyle = "#000"; ctx.strokeStyle = "#000"; ctx.lineWidth = 1;

    ctx.fillRect(60, 4, 213, 71);
    ctx.fillStyle = "#fff";
    ctx.textBaseline = "top"; ctx.textAlign = "center";
    ctx.font = "20px EtiketKalin";
    ctx.fillText("ÜNSALLAR", 166, 22);
    ctx.fillText("KURUYEMİŞ", 166, 46);
    ctx.textAlign = "left";
    ctx.fillStyle = "#000";

    cizgi(ctx, 53, 13, 53, 761);
    cizgi(ctx, 53, 631, 268, 631);

    cerceve(ctx, 60, 77, 120, 290);
    ctx.font = "20px EtiketSerif";
    dikey(ctx, "Birim Fiyat  AD/KG F. :", 65, 290, 77, "EtiketSerif", 20);
    cizgi(ctx, 158, 80, 158, 288); cizgi(ctx, 107, 288, 158, 288); cizgi(ctx, 107, 80, 158, 80);
    const ag = Number(v.agirlik) || 0;
    dikey(ctx, ag > 0 ? (Number(v.fiyat) / ag).toFixed(2) : "0.00", 108, 288, 80, "EtiketKalin", 39);

    cerceve(ctx, 193, 82, 275, 303);
    if (String(v.kod10 || "").trim().toLocaleUpperCase("tr-TR") === "TURKIYE") {
      ctx.drawImage(img.yerli, 194, 83, 81, 220);
    } else {
      dikey(ctx, "Üretim Yeri", 198, 303, 82, "EtiketSerif", 23);
      dikey(ctx, String(v.kod10 || ""), 225, 303, 82, "EtiketSerif", 23);
    }

    ctx.drawImage(img.tl, 160, 288, 38, 31);

    dikey(ctx, fiyatYaz(v.fiyat), 60, 628, 296, "EtiketKalin", 102);
    dikey(ctx, "TL", 166, 628, 560, "EtiketKalin", 36);

    cerceve(ctx, 204, 319, 262, 633);
    dikey(ctx, "Fiyat Degişim Tarihi :", 209, 633, 319, "EtiketSerif", 23);
    dikey(ctx, tarihYaz(v.tarih), 236, 633, 319, "EtiketSerif", 23);

    cerceve(ctx, 266, 283, 302, 566);
    dikey(ctx, "T.E.T.T:" + String(v.kod7 || ""), 272, 566, 283, "EtiketSans", 20);
    cerceve(ctx, 266, 562, 302, 775);
    dikey(ctx, String(v.kod6 || ""), 272, 775, 562, "EtiketSans", 20);

    dikey(ctx, String(v.ad || ""), 12, 761, 13, "EtiketSerif", 31);

    const b = ean13(v.barkod);
    if (b) {
      const m = 2, x0 = 60 + Math.floor((213 - b.bits.length * m) / 2);
      for (let i = 0; i < b.bits.length; i++) if (b.bits[i] === "1") ctx.fillRect(x0 + i * m, 648, m, 89);
      ctx.textAlign = "center"; ctx.textBaseline = "top";
      fitFont(ctx, b.metin, "EtiketSans", 20, 200);
      ctx.fillText(b.metin, 60 + 213 / 2, 741);
      ctx.textAlign = "left";
    } else if (v.barkod) {
      ctx.textAlign = "center"; ctx.textBaseline = "top";
      fitFont(ctx, String(v.barkod), "EtiketSans", 20, 200);
      ctx.fillText(String(v.barkod), 60 + 213 / 2, 700);
      ctx.textAlign = "left";
    }

    const id = ctx.getImageData(0, 0, W, H);
    const p = id.data;
    for (let i = 0; i < p.length; i += 4) {
      const k = (p[i] * 299 + p[i + 1] * 587 + p[i + 2] * 114) / 1000 < 150 ? 0 : 255;
      p[i] = p[i + 1] = p[i + 2] = k; p[i + 3] = 255;
    }
    ctx.putImageData(id, 0, 0);
    return c;
  }

  window.Etiket = { ciz, ean13, hazirla, W, H };
})();

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

  function kutu(duzen, fr) {
    const k = duzen.birim, u = duzen.ustKayma || 0;
    return { x: fr[0] / k * MM, y: (fr[1] / k - u) * MM, w: fr[2] / k * MM, h: fr[3] / k * MM };
  }

  function kenarCiz(ctx, b, kenarlar) {
    const x1 = Math.round(b.x) + 0.5, y1 = Math.round(b.y) + 0.5, x2 = Math.round(b.x + b.w) + 0.5, y2 = Math.round(b.y + b.h) + 0.5;
    const seg = { sol: [x1, y1, x1, y2], sag: [x2, y1, x2, y2], ust: [x1, y1, x2, y1], alt: [x1, y2, x2, y2] };
    ctx.strokeStyle = "#000";
    ctx.beginPath();
    kenarlar.forEach(k => { const s = seg[k]; if (s) { ctx.moveTo(s[0], s[1]); ctx.lineTo(s[2], s[3]); } });
    ctx.stroke();
  }

  function sar(ctx, txt, w) {
    const out = [];
    txt.split("\n").forEach(par => {
      let cur = "";
      const words = par.split(" ");
      words.forEach((wd, i) => {
        const aday = cur ? cur + " " + wd : wd;
        if (ctx.measureText(aday).width <= w) { cur = aday; return; }
        if (cur) { out.push(cur); cur = ""; }
        let parca = "";
        for (const ch of wd) {
          if (parca && ctx.measureText(parca + ch).width > w) { out.push(parca); parca = ""; }
          parca += ch;
        }
        cur = parca;
      });
      out.push(cur);
    });
    return out;
  }

  function metin(ctx, b, o, txt) {
    ctx.save();
    ctx.translate(b.x + b.w / 2, b.y + b.h / 2);
    if (o.dondur) ctx.rotate(-Math.PI / 2);
    const bw = o.dondur ? b.h : b.w, bh = o.dondur ? b.w : b.h;
    const fam = FAM[o.font] || FAM.sans;
    let s = Math.max(4, Math.round((o.pt || 8) * PT));
    let lines = txt.split("\n");
    if (o.kaydir) {
      ctx.font = s + "px " + fam;
      lines = sar(ctx, txt, bw - 4);
    } else {
      const sigar = () => {
        ctx.font = s + "px " + fam;
        return lines.every(l => ctx.measureText(l).width <= bw - 2) && lines.length * s * 1.1 <= bh + 2;
      };
      while (s > 6 && !sigar()) s--;
    }
    ctx.beginPath();
    ctx.rect(-bw / 2, -bh / 2, bw, bh);
    ctx.clip();
    ctx.fillStyle = o.zemin ? "#fff" : "#000";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    const satir = s * (o.kaydir ? 1.04 : 1.1);
    const ilk = o.hiza === "ust" ? -bh / 2 + satir / 2 + 1 : -(lines.length - 1) * satir / 2;
    lines.forEach((l, i) => {
      const y = ilk + i * satir;
      if (o.kaydir && i > 0 && y + s / 2 > bh / 2 + 1) return;
      ctx.fillText(l, 0, y);
    });
    ctx.restore();
  }

  function barkod(ctx, b, o, kod) {
    const e = ean13(kod);
    const yazi = Math.round((o.pt || 7) * PT);
    ctx.fillStyle = "#000";
    ctx.font = yazi + "px " + FAM.sans;
    ctx.textAlign = "center";
    if (e) {
      const m = Math.max(1, Math.floor(b.w / e.bits.length));
      const x0 = Math.round(b.x + (b.w - e.bits.length * m) / 2);
      const barH = Math.round(b.h - yazi - 2);
      for (let i = 0; i < e.bits.length; i++) if (e.bits[i] === "1") ctx.fillRect(x0 + i * m, Math.round(b.y), m, barH);
      ctx.textBaseline = "bottom";
      ctx.fillText(e.metin, b.x + b.w / 2, b.y + b.h);
    } else if (kod) {
      ctx.textBaseline = "middle";
      ctx.fillText(kod, b.x + b.w / 2, b.y + b.h / 2);
    }
  }

  function resim(ctx, b, o, img) {
    if (!o.oran) { ctx.drawImage(img, b.x, b.y, b.w, b.h); return; }
    const r = Math.min(b.w / img.width, b.h / img.height);
    ctx.drawImage(img, b.x, b.y, img.width * r, img.height * r);
  }

  async function ciz(v, canvas, secenek) {
    const img = await hazirla();
    const duzen = (secenek && secenek.duzen) || window.ETIKET_DUZEN;
    const d = degerler(v);
    const yerli = d.kod10.trim().toLocaleUpperCase("tr-TR") === "TURKIYE";
    const PW = Math.round(duzen.sayfa.en * MM), PH = Math.round(duzen.sayfa.boy * MM);
    const c = document.createElement("canvas");
    c.width = PW; c.height = PH;
    const ctx = c.getContext("2d");
    ctx.fillStyle = "#fff"; ctx.fillRect(0, 0, PW, PH);
    ctx.lineWidth = 1;
    for (const o of duzen.ogeler) {
      if (o.kosul === "yerli" && !yerli) continue;
      if (o.kosul === "yerliDegil" && yerli) continue;
      if (o.tip === "cizgi") {
        const a = kutu(duzen, [o.fr[0], o.fr[1], 0, 0]), z = kutu(duzen, [o.fr[2], o.fr[3], 0, 0]);
        ctx.strokeStyle = "#000"; ctx.beginPath();
        ctx.moveTo(Math.round(a.x) + 0.5, Math.round(a.y) + 0.5); ctx.lineTo(Math.round(z.x) + 0.5, Math.round(z.y) + 0.5); ctx.stroke();
        continue;
      }
      const b = kutu(duzen, o.fr);
      if (o.zemin || o.cerceve) { ctx.fillStyle = o.zemin ? "#000" : "#fff"; ctx.fillRect(Math.round(b.x), Math.round(b.y), Math.round(b.w), Math.round(b.h)); }
      if (o.tip === "metin") metin(ctx, b, o, doldur(o.deger, d));
      else if (o.tip === "barkod") barkod(ctx, b, o, doldur(o.deger, d));
      else if (o.tip === "resim" && img[o.kaynak]) resim(ctx, b, o, img[o.kaynak]);
      if (o.cerceve) kenarCiz(ctx, b, ["sol", "sag", "ust", "alt"]);
      else if (o.kenar) kenarCiz(ctx, b, o.kenar);
    }
    const id = ctx.getImageData(0, 0, PW, PH);
    const p = id.data;
    for (let i = 0; i < p.length; i += 4) {
      const k = (p[i] * 299 + p[i + 1] * 587 + p[i + 2] * 114) / 1000 < 150 ? 0 : 255;
      p[i] = p[i + 1] = p[i + 2] = k; p[i + 3] = 255;
    }
    ctx.putImageData(id, 0, 0);
    if (!(secenek && secenek.okuma)) {
      if (!canvas) return c;
      canvas.width = PW; canvas.height = PH;
      canvas.getContext("2d").drawImage(c, 0, 0);
      return canvas;
    }
    const r = canvas || document.createElement("canvas");
    r.width = PH; r.height = PW;
    const rc = r.getContext("2d");
    rc.translate(PH, 0);
    rc.rotate(Math.PI / 2);
    rc.drawImage(c, 0, 0);
    rc.setTransform(1, 0, 0, 1, 0, 0);
    return r;
  }

  window.Etiket = { ciz, ean13, hazirla, degerler };
})();

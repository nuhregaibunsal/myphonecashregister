(function (root) {
  let workerP = null;

  function getWorker() {
    if (!workerP) {
      workerP = (async () => {
        const w = await Tesseract.createWorker("eng", 1, {
          workerPath: "vendor/ocr/worker.min.js",
          corePath: "vendor/ocr/core",
          langPath: "vendor/ocr/lang",
          workerBlobURL: false
        });
        await w.setParameters({ tessedit_char_whitelist: "0123456789.,", tessedit_pageseg_mode: "11" });
        return w;
      })().catch(e => { workerP = null; throw e; });
    }
    return workerP;
  }

  function prepare(src, rotate) {
    const maxW = 1600;
    const sw = src.width, sh = src.height;
    const k = Math.min(1, maxW / Math.max(sw, sh));
    const w = Math.round(sw * k), h = Math.round(sh * k);
    const c = document.createElement("canvas");
    const swap = rotate === 90 || rotate === 270;
    c.width = swap ? h : w;
    c.height = swap ? w : h;
    const g = c.getContext("2d");
    g.translate(c.width / 2, c.height / 2);
    g.rotate(rotate * Math.PI / 180);
    g.drawImage(src, -w / 2, -h / 2, w, h);
    const img = g.getImageData(0, 0, c.width, c.height);
    const d = img.data;
    let sum = 0;
    for (let i = 0; i < d.length; i += 4) {
      const y = 0.299 * d[i] + 0.587 * d[i + 1] + 0.114 * d[i + 2];
      d[i] = y;
      sum += y;
    }
    const mean = sum / (d.length / 4);
    for (let i = 0; i < d.length; i += 4) {
      const v = Math.max(0, Math.min(255, (d[i] - mean) * 1.8 + 150));
      d[i] = d[i + 1] = d[i + 2] = v;
    }
    g.setTransform(1, 0, 0, 1, 0, 0);
    g.putImageData(img, 0, 0);
    return c;
  }

  function gray(c) {
    const g = c.getContext("2d");
    const img = g.getImageData(0, 0, c.width, c.height);
    const d = img.data, n = c.width * c.height, y = new Float32Array(n);
    for (let i = 0; i < n; i++) y[i] = 0.299 * d[i * 4] + 0.587 * d[i * 4 + 1] + 0.114 * d[i * 4 + 2];
    return { g, img, y, w: c.width, h: c.height };
  }

  function boxBlur(y, w, h, r) {
    const out = new Float32Array(y.length), tmp = new Float32Array(y.length);
    for (let row = 0; row < h; row++) {
      let acc = 0, cnt = 0;
      for (let x = -r; x < w; x++) {
        const add = x + r, sub = x - r - 1;
        if (add < w) { acc += y[row * w + add]; cnt++; }
        if (sub >= 0) { acc -= y[row * w + sub]; cnt--; }
        if (x >= 0) tmp[row * w + x] = acc / cnt;
      }
    }
    for (let x = 0; x < w; x++) {
      let acc = 0, cnt = 0;
      for (let row = -r; row < h; row++) {
        const add = row + r, sub = row - r - 1;
        if (add < h) { acc += tmp[add * w + x]; cnt++; }
        if (sub >= 0) { acc -= tmp[sub * w + x]; cnt--; }
        if (row >= 0) out[row * w + x] = acc / cnt;
      }
    }
    return out;
  }

  function binarize(c, blurR, bias) {
    const { g, img, y, w, h } = gray(c);
    const b = blurR > 0 ? boxBlur(y, w, h, blurR) : y;
    const bg = boxBlur(b, w, h, Math.max(8, Math.round(Math.min(w, h) / 8)));
    const d = img.data;
    for (let i = 0; i < w * h; i++) {
      const v = b[i] < bg[i] - bias ? 0 : 255;
      d[i * 4] = d[i * 4 + 1] = d[i * 4 + 2] = v;
      d[i * 4 + 3] = 255;
    }
    g.putImageData(img, 0, 0);
    return c;
  }

  function regionRight(src, corners, opt) {
    const [tl, tr, br, bl] = corners;
    const ang = Math.atan2(tr.y - tl.y, tr.x - tl.x);
    const bw = Math.hypot(tr.x - tl.x, tr.y - tl.y);
    const bh = Math.max(Math.hypot(bl.x - tl.x, bl.y - tl.y), bw * 0.25);
    const cx = (tl.x + tr.x + br.x + bl.x) / 4, cy = (tl.y + tr.y + br.y + bl.y) / 4;
    const x0 = bw * (opt.left), x1 = bw * (opt.right);
    const y0 = -bh * opt.up, y1 = bh * opt.down;
    const scale = Math.min(4, Math.max(0.5, (opt.sc || 170) / bh));
    const c = document.createElement("canvas");
    c.width = Math.round((x1 - x0) * scale);
    c.height = Math.round((y1 - y0) * scale);
    const g = c.getContext("2d");
    g.fillStyle = "#fff";
    g.fillRect(0, 0, c.width, c.height);
    g.scale(scale, scale);
    g.translate(-x0, -y0);
    g.rotate(-ang);
    g.translate(-cx, -cy);
    g.drawImage(src, 0, 0);
    if (opt.mode === "bin") return binarize(c, opt.blur || 0, opt.bias || 12);
    return prepare(c, 0);
  }

  function numbers(text) {
    const out = [];
    const re = /(\d{1,6})[.,](\d{2,3})(?!\d)/g;
    let m;
    while ((m = re.exec(String(text || "")))) {
      out.push({ value: parseFloat(m[1] + "." + m[2]), decimals: m[2].length, text: m[0] });
    }
    return out;
  }

  function matchPrice(nums, kg) {
    if (!(kg > 0)) return null;
    const money = nums.filter(n => n.decimals === 2 && n.value > 0);
    let best = null;
    for (const u of money) {
      for (const t of money) {
        if (u === t) continue;
        const diff = Math.abs(u.value * kg - t.value);
        if (diff <= Math.max(0.06, t.value * 0.003) && (!best || diff < best.diff)) best = { unit: u.value, total: t.value, diff };
      }
    }
    return best;
  }

  const VARIANTS = [
    { left: 0.5, right: 1.95, up: 1.2, down: 1.1, mode: "bin", blur: 1, sc: 170, psm: "6" },
    { left: 0.5, right: 1.95, up: 1.2, down: 1.1, mode: "bin", blur: 1, sc: 240, psm: "11" },
    { left: 0.5, right: 1.95, up: 1.2, down: 1.1, mode: "contrast", sc: 170, psm: "6" },
    { left: 0.5, right: 1.95, up: 1.2, down: 1.1, mode: "bin", blur: 2, sc: 120, psm: "11" },
    { left: 0.5, right: 2.5, up: 1.9, down: 1.7, mode: "bin", blur: 1, sc: 170, psm: "11" },
    { left: 0.5, right: 2.5, up: 1.9, down: 1.7, mode: "contrast", sc: 240, psm: "6" }
  ];

  function roundUnit(total, kg) {
    if (!(kg > 0) || !(total > 0)) return null;
    for (const step of [5, 1, 0.5]) {
      const u = Math.round(total / kg / step) * step;
      if (u > 0 && Math.abs(Math.round(u * kg * 100) / 100 - total) < 0.006) return u;
    }
    return null;
  }

  function decide(all, kg) {
    const pair = matchPrice(all, kg);
    if (pair) return { unit: pair.unit, total: pair.total, how: "pair" };
    const votes = new Map();
    all.filter(n => n.decimals === 2 && n.value > 0).forEach(n => votes.set(n.value, (votes.get(n.value) || 0) + 1));
    const ranked = [...votes.entries()].sort((a, b) => b[1] - a[1] || b[0] - a[0]);
    for (const [total, count] of ranked) {
      if (count < 2) break;
      const unit = roundUnit(total, kg);
      if (unit) return { unit, total, how: "total" };
    }
    return null;
  }

  async function readLabel(canvas, kg, maxMs, corners) {
    const started = Date.now();
    const w = await getWorker();
    const all = [];
    const jobs = corners && corners.length === 4
      ? VARIANTS.map(v => ({ v, img: () => regionRight(canvas, corners, v) }))
      : [0, 90, 270].map(r => ({ v: { psm: "11" }, img: () => prepare(canvas, r) }));
    for (const job of jobs) {
      await w.setParameters({ tessedit_pageseg_mode: job.v.psm });
      const { data } = await w.recognize(job.img());
      numbers(data.text).forEach(n => all.push(n));
      const match = decide(all, kg);
      if (match) return { match, nums: all };
      if (Date.now() - started > (maxMs || 9000)) break;
    }
    return { match: null, nums: all };
  }

  root.LabelOCR = { warm: getWorker, readLabel, numbers, matchPrice, decide, roundUnit, prepare, regionRight, binarize };
})(typeof self !== "undefined" ? self : this);

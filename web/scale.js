(function (root) {
  const DEFAULTS = {
    prefixes: "27,28,29",
    length: 13,
    pluStart: 2,
    pluLen: 5,
    valStart: 7,
    valLen: 5,
    valType: "weight",
    pluMatch: "both",
    unknownScale: "ocr",
    unknownName: "Ağırlıklı işlem"
  };

  function eanValid(code) {
    if (!/^\d+$/.test(code) || (code.length !== 13 && code.length !== 8)) return false;
    const digits = code.split("").map(Number);
    const check = digits.pop();
    let sum = 0;
    digits.reverse().forEach((d, i) => { sum += d * (i % 2 === 0 ? 3 : 1); });
    return (10 - (sum % 10)) % 10 === check;
  }

  function parseScale(code, s) {
    s = Object.assign({}, DEFAULTS, s || {});
    code = String(code || "").trim();
    if (!/^\d+$/.test(code) || code.length !== Number(s.length)) return null;
    const prefixes = String(s.prefixes).split(",").map(p => p.trim()).filter(Boolean);
    const prefix = prefixes.find(p => code.startsWith(p));
    if (!prefix) return null;
    const plu = code.substr(Number(s.pluStart), Number(s.pluLen));
    const raw = code.substr(Number(s.valStart), Number(s.valLen));
    if (plu.length !== Number(s.pluLen) || raw.length !== Number(s.valLen)) return null;
    const value = parseInt(raw, 10);
    const out = { prefix, plu, pluNum: parseInt(plu, 10), valType: s.valType, raw: value };
    if (s.valType === "price") out.amount = value / 100;
    else out.kg = value / 1000;
    return out;
  }

  function normCode(v) {
    return String(v == null ? "" : v).trim().replace(/\.0+$/, "");
  }

  function findByPlu(products, parsed, s) {
    s = Object.assign({}, DEFAULTS, s || {});
    const mode = s.pluMatch;
    if (parsed.pluNum === 0) return null;
    if (mode === "plu" || mode === "both") {
      const hit = products.find(p => p.plu !== "" && p.plu != null && parseInt(normCode(p.plu), 10) === parsed.pluNum);
      if (hit) return hit;
    }
    if (mode === "barkod" || mode === "both") {
      const want = parsed.prefix + parsed.plu;
      const hit = products.find(p => {
        const b = normCode(p.barkod);
        return b === want || b === parsed.plu || (b.length < 8 && /^\d+$/.test(b) && parseInt(b, 10) === parsed.pluNum);
      });
      if (hit) return hit;
    }
    return null;
  }

  const api = { DEFAULTS, eanValid, parseScale, findByPlu, normCode };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.Scale = api;
})(typeof self !== "undefined" ? self : this);

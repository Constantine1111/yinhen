export class ExifInfo {
  make: string = '';
  model: string = '';
  lensMake: string = '';
  lensModel: string = '';
  exposureTime: string = '';
  fNumber: string = '';
  iso: string = '';
  focalLength: string = '';
  focal35: string = '';
  program: string = '';
  dateTime: string = '';
  signature: string = '';

  clone(): ExifInfo {
    const c: ExifInfo = new ExifInfo();
    c.make = this.make;
    c.model = this.model;
    c.lensMake = this.lensMake;
    c.lensModel = this.lensModel;
    c.exposureTime = this.exposureTime;
    c.fNumber = this.fNumber;
    c.iso = this.iso;
    c.focalLength = this.focalLength;
    c.focal35 = this.focal35;
    c.program = this.program;
    c.dateTime = this.dateTime;
    c.signature = this.signature;
    return c;
  }

  hasAny(): boolean {
    return this.make !== '' || this.model !== '' || this.lensModel !== '' ||
      this.exposureTime !== '' || this.fNumber !== '' || this.iso !== '' ||
      this.focalLength !== '' || this.focal35 !== '' || this.program !== '' ||
      this.dateTime !== '';
  }
}

export class PhotoItem {
  uri: string = '';
  exif: ExifInfo = new ExifInfo();
  exifLoaded: boolean = false;

  constructor(uri: string) {
    this.uri = uri;
  }
}

export function fillExifGaps(e: ExifInfo, m: ExifInfo): void {
  if (e.make === '') {
    e.make = m.make;
  }
  if (e.model === '') {
    e.model = m.model;
  }
  if (e.lensMake === '') {
    e.lensMake = m.lensMake;
  }
  if (e.lensModel === '') {
    e.lensModel = m.lensModel;
  }
  if (e.exposureTime === '') {
    e.exposureTime = m.exposureTime;
  }
  if (e.fNumber === '') {
    e.fNumber = m.fNumber;
  }
  if (e.iso === '') {
    e.iso = m.iso;
  }
  if (e.focalLength === '') {
    e.focalLength = m.focalLength;
  }
  if (e.focal35 === '') {
    e.focal35 = m.focal35;
  }
  if (e.program === '') {
    e.program = m.program;
  }
  if (e.dateTime === '') {
    e.dateTime = m.dateTime;
  }
  if (e.signature === '') {
    e.signature = m.signature;
  }
}

export function formatExposureTime(raw: string): string {
  let s: string = raw.trim();
  if (s === '') {
    return '';
  }
  const idx: number = s.toLowerCase().indexOf('sec');
  if (idx > 0) {
    s = s.substring(0, idx).trim();
  }
  if (s.startsWith('1/')) {
    return s;
  }
  const n: number = Number(s);
  if (Number.isFinite(n) && n > 0) {
    if (n >= 1) {
      return String(Math.round(n * 100) / 100);
    }
    const denom: number = Math.round(1 / n);
    return denom > 1 ? `1/${denom}` : s;
  }
  return s;
}

export function formatAperture(raw: string): string {
  let s: string = raw.trim();
  if (s === '') {
    return '';
  }
  if (s.startsWith('f/')) {
    s = s.substring(2);
  } else if (s.startsWith('F/')) {
    s = s.substring(2);
  }
  const n: number = Number(s);
  if (Number.isFinite(n) && n > 0) {
    return String(Math.round(n * 10) / 10);
  }
  return s;
}

export function formatFocal(raw: string): string {
  let s: string = raw.trim();
  if (s === '') {
    return '';
  }
  if (s.endsWith('mm')) {
    s = s.substring(0, s.length - 2).trim();
  }
  const n: number = Number(s);
  if (Number.isFinite(n) && n > 0) {
    return String(Math.round(n));
  }
  return s;
}

export function cleanNum(raw: string): string {
  const s: string = raw.trim();
  if (s === '') {
    return '';
  }
  const n: number = Number(s);
  if (Number.isFinite(n) && n > 0) {
    return String(Math.round(n));
  }
  return '';
}

export function formatDate(raw: string): string {
  const s: string = raw.trim();
  if (s.length < 10 || s.charAt(4) !== ':') {
    return s;
  }
  const y: string = s.substring(0, 4);
  const mo: string = s.substring(5, 7);
  const d: string = s.substring(8, 10);
  let out: string = `${y}.${mo}.${d}`;
  if (s.length >= 16) {
    out += ` ${s.substring(11, 16)}`;
  }
  return out;
}

export function mapProgram(raw: string): string {
  const s: string = raw.trim();
  if (s === '' || s === 'Not defined') {
    return '';
  }
  if (s === 'Manual') {
    return 'M 手动';
  }
  if (s === 'Normal program') {
    return 'P 程序';
  }
  if (s === 'Aperture priority') {
    return 'A 光圈优先';
  }
  if (s === 'Shutter priority') {
    return 'S 快门优先';
  }
  if (s.startsWith('Creative program (biased toward depth')) {
    return '创意程序';
  }
  if (s.startsWith('Creative program (biased toward fast')) {
    return '运动模式';
  }
  if (s.startsWith('Portrait')) {
    return '人像';
  }
  if (s.startsWith('Landscape')) {
    return '风景';
  }
  return s;
}

export function toRoman(n: number): string {
  const vals: number[] = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
  const syms: string[] = ['M', 'CM', 'D', 'CD', 'C', 'XC', 'L', 'XL', 'X', 'IX', 'V', 'IV', 'I'];
  let out: string = '';
  let v: number = Math.floor(n);
  for (let i = 0; i < vals.length; i++) {
    while (v >= vals[i]) {
      out += syms[i];
      v -= vals[i];
    }
  }
  return out;
}

const ROMAN_MARKS: string[] = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X'];

function normalizeRomanSuffix(s: string): string {
  const rm: RegExpMatchArray | null = s.match(/^(.+?)([ivxIVX]{1,4})$/);
  if (rm === null) {
    return s;
  }
  const roman: string = rm[2].toUpperCase();
  if (roman === 'I' || !ROMAN_MARKS.includes(roman)) {
    return s;
  }
  const head: string = rm[1].trimEnd();
  if (head === '') {
    return s;
  }
  return `${head} ${roman}`;
}

export function cleanMakeText(raw: string): string {
  let s: string = raw.replace('CORPORATION', '').trim();
  if (s === '') {
    return '';
  }
  return s.charAt(0) + s.substring(1).toLowerCase();
}

export function cleanModelText(make: string, model: string): string {
  let s: string = model.trim();
  if (s === '') {
    return '';
  }
  let mk: string = make.replace('CORPORATION', '').trim().toUpperCase();
  if (mk === '' && /^[Zz](\d|[fFrR])/.test(s)) {
    mk = 'NIKON';
  } else if (mk === '' && /^[Aa]\d/.test(s)) {
    mk = 'SONY';
  }
  if (mk !== '' && s.toUpperCase().startsWith(mk)) {
    s = s.substring(mk.length).trim();
  }
  const isNikon: boolean = mk.includes('NIKON') || mk.includes('尼康');
  const isSony: boolean = mk.includes('SONY') || mk.includes('索尼');
  if (isNikon && s.startsWith('尼康')) {
    s = s.substring(2).trim();
  } else if (isSony && s.startsWith('索尼')) {
    s = s.substring(2).trim();
  }
  const arr: string[] = s.split('_');
  if (arr.length > 1) {
    const last: string = arr[arr.length - 1].trim();
    const n: number = Number(last);
    const lastUp: string = last.toUpperCase();
    if (last !== '' && !Number.isNaN(n) && n > 0) {
      arr.pop();
      s = `${arr.join(' ').trimEnd()} ${toRoman(n)}`;
    } else if (last !== '' && lastUp !== 'I' && ROMAN_MARKS.includes(lastUp)) {
      arr.pop();
      s = `${arr.join(' ').trimEnd()} ${lastUp}`;
    } else {
      s = arr.join(' ');
    }
  }
  if (isNikon) {
    s = s.replace(/[Zz]/g, 'ℤ');
    s = s.replace(/ℤ\s*[fF]/, 'ℤ 𝒇');
    s = s.replace(/ℤ\s*[rR]/, 'ℤ R');
    const dm: RegExpMatchArray | null = s.match(/^(ℤ\d)([2-4])$/);
    if (dm !== null) {
      s = `${dm[1]} ${toRoman(Number(dm[2]))}`;
    } else {
      s = normalizeRomanSuffix(s);
    }
  } else if (isSony) {
    s = s.replace('ILCE-', 'α');
    s = s.replace(/([aA])(?=\d)/g, 'α');
    const lm: RegExpMatchArray | null = s.match(/^(α.+?)([a-zA-Z])([2-5])$/);
    if (lm !== null) {
      s = lm[2].toUpperCase() === 'M' ? `${lm[1]} ${toRoman(Number(lm[3]))}` :
        `${lm[1]}${lm[2].toUpperCase()} ${toRoman(Number(lm[3]))}`;
    } else {
      const dm: RegExpMatchArray | null = s.match(/^(α\d)([2-4])$/);
      if (dm !== null) {
        s = `${dm[1]} ${toRoman(Number(dm[2]))}`;
      } else {
        s = normalizeRomanSuffix(s);
      }
    }
  }
  return s.trim();
}

export class FrameLayout {
  photoW: number = 0;
  photoH: number = 0;
  pad: number = 0;
  gapAbove: number = 0;
  barH: number = 0;
  f1: number = 0;
  f2: number = 0;
  outW: number = 0;
  outH: number = 0;
  mode: number = 1;
  tailPad: number = 0;
  keylineW: number = 0;
}

export class CanvasLayout {
  photoW: number = 0;
  photoH: number = 0;
  pad: number = 0;
  gapAbove: number = 0;
  f1: number = 0;
  f2: number = 0;
  outW: number = 0;
  outH: number = 0;
  mode: number = 1;
  photoRadius: number = 0;
  barInset: number = 0;
  tailPad: number = 0;
  keylineW: number = 0;
}

export const BAR_LH: number = 1.55;
export const BAR_GAP: number = 0.7;
export const TITLE_FACTOR: number = 1.25;
export const TITLE_SPLIT_FACTOR: number = 1.55;
export const TITLE_SPLIT_LENS_FACTOR: number = 1.2;
export const DATE_SPLIT_FACTOR: number = 0.85;
// 台历：大字日号字号与行高系数（相对 f2）；日号视觉高度≈三行信息墨迹总高
export const CAL_DAY_FACTOR: number = 5.0;
export const CAL_DAY_LH: number = 1.0;
// 台历：信息行行盒系数与信息区上下留白
export const CAL_BOX_LH: number = 1.2;
export const CAL_MARGIN: number = 0.3;
// 台历：年月红色
export const CAL_YM_COLOR: string = '#C0392B';
// 会展：白框左下三行（署名/相机型号/曝光参数·拍摄时间）行盒与行距系数（相对 f2）
export const EXPO_HEAD_LH: number = 1.3;
export const EXPO_SUB_LH: number = 1.15;
export const EXPO_GAP: number = 0.45;

const TITLE_PCT: number = 2.5;
const BODY_PCT: number = 1.85;

export function orientationDegrees(v: string): number {
  const s: string = v.trim();
  if (s === 'Bottom-right' || s === '3') {
    return 180;
  }
  if (s === 'Right-top' || s === '6') {
    return 90;
  }
  if (s === 'Left-bottom' || s === '8') {
    return 270;
  }
  return 0;
}

function clampNum(v: number, lo: number, hi: number): number {
  return Math.min(Math.max(v, lo), hi);
}

export function computeFrameLayout(imgW: number, imgH: number, padPct: number, sizeScalePct: number,
  mode: number, titleOn: boolean, bodyCount: number, split: boolean,
  leftBody: number, rightBody: number, layoutKind: number, keylineOn: boolean,
  calContent: number): FrameLayout {
  const lay: FrameLayout = new FrameLayout();
  if (imgW <= 0 || imgH <= 0) {
    return lay;
  }
  lay.mode = mode;
  lay.photoW = imgW;
  lay.photoH = imgH;
  const scale: number = clampNum(sizeScalePct, 40, 220) / 100;
  lay.f1 = Math.max(6, imgW * TITLE_PCT * scale / 100);
  lay.f2 = Math.max(5, imgW * BODY_PCT * scale / 100);
  lay.keylineW = keylineOn ? Math.max(lay.f2 * 0.12, 1) : 0;
  const gap: number = lay.f2 * BAR_GAP;
  let barH: number = 0;
  if (calContent > 0) {
    // 台历布局：calContent 为内容高（相对 f2），上下各加 CAL_MARGIN 呼吸留白
    barH = lay.f2 * calContent + lay.f2 * CAL_MARGIN * 2;
  } else if (split) {
    const leftN: number = (titleOn ? 1 : 0) + leftBody;
    let leftH: number = 0;
    if (titleOn) {
      const tf: number = leftBody > 0 ? TITLE_SPLIT_LENS_FACTOR : TITLE_SPLIT_FACTOR;
      leftH += lay.f1 * tf * BAR_LH;
    }
    leftH += leftBody * lay.f2 * BAR_LH;
    if (leftN > 1) {
      leftH += (leftN - 1) * lay.f2 * 0.45;
    }
    let rightH: number = 0;
    if (rightBody >= 1) {
      rightH += lay.f2 * BAR_LH;
    }
    if (rightBody >= 2) {
      rightH += lay.f2 * 0.45 + lay.f2 * DATE_SPLIT_FACTOR * BAR_LH;
    }
    barH = Math.max(leftH, rightH);
  } else {
    const n: number = (titleOn ? 1 : 0) + bodyCount;
    if (titleOn) {
      barH += lay.f1 * BAR_LH;
    }
    barH += bodyCount * lay.f2 * BAR_LH;
    if (n > 1) {
      barH += (n - 1) * gap;
    }
  }
  lay.barH = barH;
  if (mode === 0) {
    lay.pad = 0;
    lay.gapAbove = 0;
    lay.outW = imgW;
    lay.outH = imgH;
  } else {
    lay.pad = imgW * clampNum(padPct, 0, 30) / 100;
    if (layoutKind === 1) {
      const sidePad: number = lay.pad * 0.75;
      const band: number = Math.max(sidePad * 5.8, barH + sidePad * 2 + lay.f2 * 1.4);
      lay.pad = sidePad;
      lay.gapAbove = 0;
      lay.tailPad = 0;
      lay.outW = imgW + sidePad * 2;
      lay.outH = imgH + sidePad + band;
    } else {
      lay.tailPad = layoutKind === 2 ? lay.pad : 0;
      lay.gapAbove = calContent > 0 ? lay.f2 : (barH > 0 ? lay.f2 : 0);
      lay.outW = imgW + lay.pad * 2;
      lay.outH = imgH + lay.pad * 2 + lay.gapAbove + lay.barH + lay.tailPad;
    }
  }
  return lay;
}

export function scaleLayout(lay: FrameLayout, k: number): CanvasLayout {
  const c: CanvasLayout = new CanvasLayout();
  c.mode = lay.mode;
  c.photoW = lay.photoW * k;
  c.photoH = lay.photoH * k;
  c.pad = lay.pad * k;
  c.gapAbove = lay.gapAbove * k;
  c.f1 = lay.f1 * k;
  c.f2 = lay.f2 * k;
  c.outW = lay.outW * k;
  c.outH = lay.outH * k;
  c.photoRadius = lay.mode === 2 ? lay.f2 * k * 0.8 : 0;
  c.barInset = lay.mode === 0 ? lay.f2 * k * 1.2 : 0;
  c.tailPad = lay.tailPad * k;
  c.keylineW = lay.keylineW * k;
  return c;
}

export const WM_TEXT_COLORS: string[] = [
  '#222222', '#FFFFFF', '#9AA1AC', '#C0392B', '#2C6E49', '#1F4E8C', '#7C4D9B', '#B8860B'
];

export const FRAME_COLORS: string[] = [
  '#FFFFFF', '#111111', '#F7F2E7', '#EAF0FA', '#FBEFF2'
];

export class StylePreset {
  name: string = '';
  frameMode: number = 1;
  layoutKind: number = 0;
  directPos: number = 0;
  frameColor: string = '#FFFFFF';
  textColor: string = '#222222';
  keylineOn: boolean = false;
  keylineColor: string = '#222222';
  barLayout: number = 0;
  alignMode: number = 1;
  frameMarginPct: number = 6;
  sizeScalePct: number = 100;
  blurPct: number = 12;
  showMask: number = 238;
  shadowMode: number = 1;
  filmStyle: boolean = false;
  // 曝光参数以四枚胶囊标签展示（焦距/光圈/快门/ISO 各一枚）
  parTags: boolean = false;
  desc: string = '';
  refFile: string = '';
  refAspect: number = 1.4;
}

function preset(name: string, frameMode: number, layoutKind: number, directPos: number,
  frameColor: string, textColor: string, keylineOn: boolean, keylineColor: string,
  barLayout: number, alignMode: number, frameMarginPct: number, sizeScalePct: number,
  blurPct: number, showMask: number, shadowMode: number = 1, filmStyle: boolean = false,
  parTags: boolean = false): StylePreset {
  const p: StylePreset = new StylePreset();
  p.name = name;
  p.frameMode = frameMode;
  p.layoutKind = layoutKind;
  p.directPos = directPos;
  p.frameColor = frameColor;
  p.textColor = textColor;
  p.keylineOn = keylineOn;
  p.keylineColor = keylineColor;
  p.barLayout = barLayout;
  p.alignMode = alignMode;
  p.frameMarginPct = frameMarginPct;
  p.sizeScalePct = sizeScalePct;
  p.blurPct = blurPct;
  p.showMask = showMask;
  p.shadowMode = shadowMode;
  p.filmStyle = filmStyle;
  p.parTags = parTags;
  return p;
}

export function buildPresets(): StylePreset[] {
  const arr: StylePreset[] = [
    preset('标准白框', 1, 0, 0, '#FFFFFF', '#222222', false, '#222222', 1, 1, 6, 100, 12, 1791),
    preset('标签参数', 1, 0, 0, '#FFFFFF', '#222222', false, '#222222', 1, 1, 6, 100, 12, 1791, 1, false, true),
    preset('台历', 1, 0, 0, '#FFFFFF', '#222222', false, '#222222', 2, 1, 0, 100, 12, 1787),
    preset('会展', 1, 0, 0, '#FFFFFF', '#222222', false, '#222222', 3, 0, 5, 100, 12, 1787, 2),
    preset('拍立得', 1, 1, 0, '#FFFFFF', '#222222', false, '#222222', 1, 1, 6, 100, 12, 1791, 2),
    preset('胶片', 0, 0, 1, '#000000', '#FF8C00', false, '#222222', 0, 2, 6, 100, 12, 1538, 0, true),
    preset('背景模糊', 2, 0, 0, '#000000', '#FFFFFF', false, '#FFFFFF', 0, 1, 6, 100, 12, 1279)
  ];
  const descs: string[] = [
    '白框下方水印',
    '曝光参数胶囊标签',
    '大字日期台历',
    '白框左下角信息',
    '窄边宽底居中',
    '右下角橙标注',
    '模糊底白水印'
  ];
  const refFiles: string[] = [
    'presets/preset-standard.jpg',
    'presets/preset-partags.jpg',
    'presets/preset-calendar.jpg',
    'presets/preset-expo.jpg',
    'presets/preset-polaroid.jpg',
    'presets/preset-film.jpg',
    'presets/preset-blur.jpg'
  ];
  const refAspects: number[] = [4588 / 3640, 4588 / 3640, 4096 / 3231, 4506 / 3557, 4465 / 3984, 4096 / 2731, 4588 / 3798];
  for (let i = 0; i < arr.length; i++) {
    arr[i].desc = descs[i];
    arr[i].refFile = refFiles[i];
    arr[i].refAspect = refAspects[i];
  }
  return arr;
}

export const KEYLINE_COLORS: string[] = [
  '#222222', '#9AA1AC', '#C0392B', '#1F4E8C', '#B8860B', '#2C6E49'
];

export class BrandLogo {
  key: string = '';
  name: string = '';
  blackFile: string = '';
  whiteFile: string = '';
  aspect: number = 4;
  imageFile: string = '';
  imageAspect: number = 0;

  constructor(key: string, name: string, blackFile: string, whiteFile: string, aspect: number,
    imageFile: string = '', imageAspect: number = 0) {
    this.key = key;
    this.name = name;
    this.blackFile = blackFile;
    this.whiteFile = whiteFile;
    this.aspect = aspect;
    this.imageFile = imageFile;
    this.imageAspect = imageAspect;
  }
}

export const BRAND_LOGOS: BrandLogo[] = [
  new BrandLogo('canon', '佳能', 'logos/canon-b.svg', 'logos/canon-w.svg', 4.75),
  new BrandLogo('nikon', '尼康', 'logos/nikon-b.svg', 'logos/nikon-w.svg', 3.61),
  new BrandLogo('sony', '索尼', 'logos/sony-b.svg', 'logos/sony-w.svg', 5.68),
  new BrandLogo('fujifilm', '富士', 'logos/fujifilm-b.svg', 'logos/fujifilm-w.svg', 5.99),
  new BrandLogo('leica', '徕卡', 'logos/leica-b.svg', 'logos/leica-w.svg', 2.25),
  new BrandLogo('hasselblad', '哈苏', 'logos/hasselblad-h-b.png', 'logos/hasselblad-h-w.png', 1.35),
  new BrandLogo('pentax', '宾得', 'logos/pentax-b.svg', 'logos/pentax-w.svg', 5.15),
  new BrandLogo('ricoh', '理光', 'logos/ricoh-b.svg', 'logos/ricoh-w.svg', 5.61),
  new BrandLogo('olympus', '奥林巴斯', 'logos/olympus-b.svg', 'logos/olympus-w.svg', 8.02),
  new BrandLogo('panasonic', '松下', 'logos/panasonic-b.svg', 'logos/panasonic-w.svg', 5.08),
  new BrandLogo('sigma', '适马', 'logos/sigma-b.svg', 'logos/sigma-w.svg', 4.62),
  new BrandLogo('dji', '大疆', 'logos/dji-b.svg', 'logos/dji-w.svg', 1.70),
  new BrandLogo('songdian', '松典', 'logos/songdian-b.svg', 'logos/songdian-w.svg', 5.62),
  new BrandLogo('apple', '苹果', 'logos/apple.png', 'logos/apple.png', 0.82),
  new BrandLogo('huawei', '华为', 'logos/huawei-word-b.svg', 'logos/huawei-word-w.svg', 6.14, 'logos/xmage-red.png', 4.94)
];

export function detectBrand(make: string, model: string): string {
  const s: string = `${make} ${model}`.toUpperCase();
  if (s.trim() === '') {
    return '';
  }
  if (s.includes('APPLE') || s.includes('IPHONE')) {
    return 'apple';
  }
  if (s.includes('HUAWEI') || s.includes('HONOR') || s.includes('XMAGE')) {
    return 'huawei';
  }
  if (s.includes('PENTAX')) {
    return 'pentax';
  }
  if (s.includes('RICOH')) {
    return 'ricoh';
  }
  if (s.includes('CANON')) {
    return 'canon';
  }
  if (s.includes('NIKON') || s.includes('尼康')) {
    return 'nikon';
  }
  if (s.includes('SONY') || s.includes('索尼')) {
    return 'sony';
  }
  if (s.includes('FUJIFILM') || s.includes('FUJI')) {
    return 'fujifilm';
  }
  if (s.includes('LEICA')) {
    return 'leica';
  }
  if (s.includes('HASSELBLAD')) {
    return 'hasselblad';
  }
  if (s.includes('OLYMPUS') || s.includes('OM DIGITAL') || s.includes('OM SYSTEM') || s.includes('OM-')) {
    return 'olympus';
  }
  if (s.includes('PANASONIC') || s.includes('LUMIX')) {
    return 'panasonic';
  }
  if (s.includes('SIGMA')) {
    return 'sigma';
  }
  if (s.includes('DJI')) {
    return 'dji';
  }
  if (s.includes('SONGDIAN')) {
    return 'songdian';
  }
  return '';
}

export function brandByKey(key: string): BrandLogo | undefined {
  for (const b of BRAND_LOGOS) {
    if (b.key === key) {
      return b;
    }
  }
  return undefined;
}

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Logger } from '../utils/Logger';
import { ExifInfo, detectBrand } from './WatermarkModels';

// ============ 导出记录（每次导出成功后写一条）============

export class ExportRecord {
  ts: number = 0;
  camera: string = '';
  lens: string = '';
  brand: string = '';
  focal: number = 0;
  focal35: number = 0;
  aperture: number = 0;
  shutter: string = '';
  shutterSec: number = 0;
  iso: number = 0;
  hour: number = 0;
  ratio: string = '';
  exifNative: boolean = false;
}

// ============ 聚合统计（增量更新，O(1)）============

export class ProfileStats {
  totalExports: number = 0;
  firstExportTs: number = 0;
  cameraCounts: Record<string, number> = {};
  lensCounts: Record<string, number> = {};
  brandCounts: Record<string, number> = {};
  focalBuckets: Record<string, number> = {};
  apertureBuckets: Record<string, number> = {};
  shutterBuckets: Record<string, number> = {};
  isoBuckets: Record<string, number> = {};
  hourBuckets: number[] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
  ratioCounts: Record<string, number> = {};
  isoSum: number = 0;
  isoCount: number = 0;
  fullParamCount: number = 0;
  streakDays: number = 0;
  lastExportDayTs: number = 0;
  unlockedAchievements: Record<string, number> = {};
  popupDayTs: number = 0;
  popupCountToday: number = 0;
}

export class NameCount {
  name: string = '';
  count: number = 0;

  constructor(name: string, count: number) {
    this.name = name;
    this.count = count;
  }
}

// ============ 基础工具 ============

function asNum(v: Object | undefined): number {
  if (v === undefined || v === null) {
    return 0;
  }
  const n: number = Number(v);
  return Number.isFinite(n) ? n : 0;
}

function recFrom(v: Object | undefined): Record<string, number> {
  const out: Record<string, number> = {};
  if (v === undefined || v === null) {
    return out;
  }
  const m: Record<string, Object> = v as Record<string, Object>;
  const keys: string[] = Object.keys(m);
  for (const k of keys) {
    out[k] = asNum(m[k]);
  }
  return out;
}

export function parseStats(text: string): ProfileStats {
  const s: ProfileStats = new ProfileStats();
  if (text === '') {
    return s;
  }
  try {
    const raw: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
    s.totalExports = asNum(raw['totalExports']);
    s.firstExportTs = asNum(raw['firstExportTs']);
    s.cameraCounts = recFrom(raw['cameraCounts']);
    s.lensCounts = recFrom(raw['lensCounts']);
    s.brandCounts = recFrom(raw['brandCounts']);
    s.focalBuckets = recFrom(raw['focalBuckets']);
    s.apertureBuckets = recFrom(raw['apertureBuckets']);
    s.shutterBuckets = recFrom(raw['shutterBuckets']);
    s.isoBuckets = recFrom(raw['isoBuckets']);
    s.ratioCounts = recFrom(raw['ratioCounts']);
    s.unlockedAchievements = recFrom(raw['unlockedAchievements']);
    s.isoSum = asNum(raw['isoSum']);
    s.isoCount = asNum(raw['isoCount']);
    s.fullParamCount = asNum(raw['fullParamCount']);
    s.streakDays = asNum(raw['streakDays']);
    s.lastExportDayTs = asNum(raw['lastExportDayTs']);
    s.popupDayTs = asNum(raw['popupDayTs']);
    s.popupCountToday = asNum(raw['popupCountToday']);
    const hb: Object | undefined = raw['hourBuckets'];
    if (hb !== undefined && hb !== null) {
      const arr: Object[] = hb as Object[];
      for (let i = 0; i < 24 && i < arr.length; i++) {
        s.hourBuckets[i] = asNum(arr[i]);
      }
    }
  } catch (err) {
    Logger.error(`parseStats failed: ${JSON.stringify(err)}`);
    return new ProfileStats();
  }
  return s;
}

export function recGet(r: Record<string, number>, k: string): number {
  const keys: string[] = Object.keys(r);
  if (!keys.includes(k)) {
    return 0;
  }
  return r[k];
}

export function recTotal(r: Record<string, number>): number {
  const keys: string[] = Object.keys(r);
  let t: number = 0;
  for (const k of keys) {
    t += r[k];
  }
  return t;
}

export function recCount(r: Record<string, number>): number {
  return Object.keys(r).length;
}

export function recMax(r: Record<string, number>): number {
  const keys: string[] = Object.keys(r);
  let m: number = 0;
  for (const k of keys) {
    if (r[k] > m) {
      m = r[k];
    }
  }
  return m;
}

function bumpRec(r: Record<string, number>, k: string): void {
  r[k] = recGet(r, k) + 1;
}

export function topEntries(r: Record<string, number>, n: number): NameCount[] {
  const keys: string[] = Object.keys(r);
  const all: NameCount[] = [];
  for (const k of keys) {
    if (r[k] > 0) {
      all.push(new NameCount(k, r[k]));
    }
  }
  all.sort((a: NameCount, b: NameCount) => b.count - a.count);
  return all.slice(0, n);
}

export function isoMean(s: ProfileStats): number {
  if (s.isoCount <= 0) {
    return 0;
  }
  return s.isoSum / s.isoCount;
}

export function hourRangeSum(buckets: number[], from: number, to: number): number {
  let sum: number = 0;
  if (from <= to) {
    for (let h = from; h <= to; h++) {
      sum += buckets[h];
    }
  } else {
    for (let h = from; h <= 23; h++) {
      sum += buckets[h];
    }
    for (let h = 0; h <= to; h++) {
      sum += buckets[h];
    }
  }
  return sum;
}

export function dayStartTs(ts: number): number {
  const d: Date = new Date(ts);
  d.setHours(0, 0, 0, 0);
  return d.getTime();
}

export function isUnlocked(s: ProfileStats, key: string): boolean {
  return Object.keys(s.unlockedAchievements).includes(key);
}

export function unlockTs(s: ProfileStats, key: string): number {
  return recGet(s.unlockedAchievements, key);
}

export function unlockedCount(s: ProfileStats): number {
  return Object.keys(s.unlockedAchievements).length;
}

// ============ 分桶 ============

function focalBucketKey(f: number): string {
  if (f < 24) {
    return '超广';
  }
  if (f < 36) {
    return '广角';
  }
  if (f <= 70) {
    return '标准';
  }
  if (f <= 135) {
    return '中长焦';
  }
  return '长焦';
}

function apertureBucketKey(a: number): string {
  if (a <= 2.8) {
    return '大光圈';
  }
  if (a <= 5.6) {
    return '中等';
  }
  return '小光圈';
}

function shutterBucketKey(sec: number): string {
  if (sec <= 1 / 250) {
    return '高速';
  }
  if (sec > 1 / 100) {
    return '慢门';
  }
  return '常规';
}

function isoBucketKey(iso: number): string {
  if (iso <= 400) {
    return '低感';
  }
  if (iso <= 1600) {
    return '中感';
  }
  return '高感';
}

// ============ 记录构建（防作弊：只读 EXIF 解析器输出）============

function parseNum(raw: string): number {
  const t: string = raw.trim();
  if (t === '') {
    return 0;
  }
  const n: number = Number(t);
  return Number.isFinite(n) && n > 0 ? n : 0;
}

function parseShutterSec(raw: string): number {
  const t: string = raw.trim();
  if (t === '') {
    return 0;
  }
  const slash: number = t.indexOf('/');
  if (slash > 0) {
    const n: number = Number(t.substring(0, slash));
    const d: number = Number(t.substring(slash + 1));
    if (Number.isFinite(n) && Number.isFinite(d) && n > 0 && d > 0) {
      return n / d;
    }
    return 0;
  }
  const v: number = Number(t);
  return Number.isFinite(v) && v > 0 ? v : 0;
}

function parseHour(dateTime: string, now: number): number {
  const t: string = dateTime.trim();
  if (t.length >= 13) {
    const h: number = Number(t.substring(11, 13));
    if (Number.isFinite(h) && h >= 0 && h <= 23) {
      return Math.floor(h);
    }
  }
  const d: Date = new Date(now);
  return d.getHours();
}

export function buildExportRecord(native: ExifInfo, ratio: string, now: number): ExportRecord {
  const r: ExportRecord = new ExportRecord();
  r.ts = now;
  const make: string = native.make.trim();
  const model: string = native.model.trim();
  r.camera = make !== '' ? `${make} ${model}`.trim() : model;
  r.brand = detectBrand(make, model);
  r.lens = native.lensModel.trim();
  r.focal = parseNum(native.focalLength);
  r.focal35 = parseNum(native.focal35);
  r.aperture = parseNum(native.fNumber);
  r.shutter = native.exposureTime.trim();
  r.shutterSec = parseShutterSec(r.shutter);
  r.iso = parseNum(native.iso);
  r.hour = parseHour(native.dateTime, now);
  r.ratio = ratio;
  r.exifNative = make !== '' || model !== '' || r.lens !== '';
  return r;
}

// ============ 聚合更新（增量）============

export function applyRecord(s: ProfileStats, rec: ExportRecord): void {
  s.totalExports++;
  if (s.firstExportTs === 0) {
    s.firstExportTs = rec.ts;
  }
  if (rec.camera !== '') {
    bumpRec(s.cameraCounts, rec.camera);
  }
  if (rec.lens !== '') {
    bumpRec(s.lensCounts, rec.lens);
  }
  if (rec.brand !== '') {
    bumpRec(s.brandCounts, rec.brand);
  }
  const f: number = rec.focal35 > 0 ? rec.focal35 : rec.focal;
  if (f > 0) {
    bumpRec(s.focalBuckets, focalBucketKey(f));
  }
  if (rec.aperture > 0) {
    bumpRec(s.apertureBuckets, apertureBucketKey(rec.aperture));
  }
  if (rec.shutterSec > 0) {
    bumpRec(s.shutterBuckets, shutterBucketKey(rec.shutterSec));
  }
  if (rec.iso > 0) {
    bumpRec(s.isoBuckets, isoBucketKey(rec.iso));
    s.isoSum += rec.iso;
    s.isoCount++;
  }
  if (rec.camera !== '' && rec.lens !== '' && rec.focal > 0 &&
    rec.aperture > 0 && rec.shutterSec > 0 && rec.iso > 0) {
    s.fullParamCount++;
  }
  if (rec.hour >= 0 && rec.hour <= 23) {
    s.hourBuckets[rec.hour]++;
  }
  if (rec.ratio !== '') {
    bumpRec(s.ratioCounts, rec.ratio);
  }
  const day: number = dayStartTs(rec.ts);
  if (s.lastExportDayTs !== day) {
    if (s.lastExportDayTs > 0 && dayStartTs(s.lastExportDayTs + 86400000) === day) {
      s.streakDays++;
    } else {
      s.streakDays = 1;
    }
    s.lastExportDayTs = day;
  }
}

// ============ 成就定义 ============

export class AchievementDef {
  key: string = '';
  name: string = '';
  desc: string = '';
  rarity: string = 'bronze';
  group: string = '';
  icon: string = '🏅';
  minSamples: number = 1;
  hidden: boolean = false;
  mutex: string = '';
  check: (s: ProfileStats) => boolean = (_s: ProfileStats) => false;
  progress: (s: ProfileStats) => string = (_s: ProfileStats) => '';
  metric: (s: ProfileStats) => number = (_s: ProfileStats) => 0;
}

function mk(key: string, name: string, desc: string, rarity: string, group: string, icon: string,
  minSamples: number, check: (s: ProfileStats) => boolean, progress: (s: ProfileStats) => string,
  metric: (s: ProfileStats) => number, hidden: boolean = false, mutex: string = ''): AchievementDef {
  const d: AchievementDef = new AchievementDef();
  d.key = key;
  d.name = name;
  d.desc = desc;
  d.rarity = rarity;
  d.group = group;
  d.icon = icon;
  d.minSamples = minSamples;
  d.hidden = hidden;
  d.mutex = mutex;
  d.check = check;
  d.progress = progress;
  d.metric = metric;
  return d;
}

function brandUnlockedOf(s: ProfileStats, keys: string[]): number {
  let n: number = 0;
  for (const k of keys) {
    if (isUnlocked(s, k)) {
      n++;
    }
  }
  return n;
}

const BRAND_KEYS: string[] = ['nikon_lord', 'sony_party', 'canon_faith', 'fuji_rich', 'leica_de'];
const TRIO_KEYS: string[] = ['nikon_lord', 'sony_party', 'canon_faith'];
const TIME_KEYS: string[] = ['early_bird', 'night_owl', 'dawn_patrol'];

function pctText(a: number, b: number): string {
  if (b <= 0) {
    return '0%';
  }
  return `${Math.round(a * 100 / b)}%`;
}

export const ACHIEVEMENTS: AchievementDef[] = [
  // ---- 金色成就（meta / count）----
  mk('thousand', '千张老手', '一千张，已经不是习惯，是生活。', 'gold', 'meta', '🏔', 1,
    (s: ProfileStats) => s.totalExports >= 1000,
    (s: ProfileStats) => `${Math.min(s.totalExports, 1000)}/1000`,
    (s: ProfileStats) => s.totalExports),
  mk('legend', '万张传说', '传说级仓库管理员。你的快门比时钟还准。', 'gold', 'meta', '👑', 1,
    (s: ProfileStats) => s.totalExports >= 10000,
    (s: ProfileStats) => `${Math.min(s.totalExports, 10000)}/10000`,
    (s: ProfileStats) => s.totalExports, true),
  mk('polyglot', '全能摄影师', '什么题材都拍，什么光圈都敢开。八边形战士，说的就是你。', 'gold', 'meta', '🧭', 30,
    (s: ProfileStats): boolean => {
      const ft: number = recTotal(s.focalBuckets);
      const at: number = recTotal(s.apertureBuckets);
      return ft > 0 && at > 0 &&
        recGet(s.focalBuckets, '广角') / ft >= 0.15 &&
        recGet(s.focalBuckets, '中长焦') / ft >= 0.15 &&
        recGet(s.apertureBuckets, '大光圈') / at >= 0.15 &&
        recGet(s.apertureBuckets, '小光圈') / at >= 0.15;
    },
    (s: ProfileStats): string => {
      const ft: number = recTotal(s.focalBuckets);
      const at: number = recTotal(s.apertureBuckets);
      const w: number = ft > 0 ? recGet(s.focalBuckets, '广角') / ft : 0;
      const t: number = ft > 0 ? recGet(s.focalBuckets, '中长焦') / ft : 0;
      const bg: number = at > 0 ? recGet(s.apertureBuckets, '大光圈') / at : 0;
      const sd: number = at > 0 ? recGet(s.apertureBuckets, '小光圈') / at : 0;
      return `广角${pctText(Math.round(w * 100), 100)} 中长焦${pctText(Math.round(t * 100), 100)}`;
    },
    (s: ProfileStats) => 0),
  mk('decathlon', '十项全能', '十个徽章，是你用快门换来的勋章。', 'gold', 'meta', '🏅', 1,
    (s: ProfileStats) => unlockedCount(s) >= 10,
    (s: ProfileStats) => `${Math.min(unlockedCount(s), 10)}/10`,
    (s: ProfileStats) => unlockedCount(s)),
  mk('brand_united', '品牌制霸', '器材界的联合国，非你莫属。', 'gold', 'meta', '🌍', 1,
    (s: ProfileStats) => brandUnlockedOf(s, BRAND_KEYS) >= 5,
    (s: ProfileStats) => `${brandUnlockedOf(s, BRAND_KEYS)}/5`,
    (s: ProfileStats) => brandUnlockedOf(s, BRAND_KEYS)),
  mk('time_traveler', '时间旅行者', '你见过这座城市所有的光。', 'gold', 'time', '⏳', 1,
    (s: ProfileStats) => brandUnlockedOf(s, TIME_KEYS) >= 3,
    (s: ProfileStats) => `${brandUnlockedOf(s, TIME_KEYS)}/3`,
    (s: ProfileStats) => brandUnlockedOf(s, TIME_KEYS)),
  mk('streak_30', '水印大师', '雷打不动，风雨无阻。', 'gold', 'meta', '📅', 1,
    (s: ProfileStats) => s.streakDays >= 30,
    (s: ProfileStats) => `${Math.min(s.streakDays, 30)}/30天`,
    (s: ProfileStats) => s.streakDays),
  mk('anniversary', '一年之约', '你和印痕的周年纪念。', 'gold', 'meta', '🎂', 1,
    (s: ProfileStats): boolean => {
      if (s.firstExportTs <= 0) {
        return false;
      }
      return Date.now() - s.firstExportTs >= 365 * 86400000;
    },
    (s: ProfileStats): string => {
      if (s.firstExportTs <= 0) {
        return '0/365天';
      }
      const days: number = Math.floor((Date.now() - s.firstExportTs) / 86400000);
      return `${Math.min(days, 365)}/365天`;
    },
    (s: ProfileStats) => 0),
  // ---- 彩蛋成就 ----
  mk('dragon', '召唤神龙', '五家血脉集齐，神龙从镜头里抬起了头——你下一步打算拍啥？', 'legend', 'brand', '🐉', 1,
    (s: ProfileStats) => brandUnlockedOf(s, BRAND_KEYS) >= 5,
    (s: ProfileStats) => '',
    (s: ProfileStats) => 0, true),
  // ---- 品牌梗成就（仅 EXIF 原生字段计数）----
  mk('nikon_lord', '尼康佬', '你有一台尼康，和一颗想拍星空的心。', 'bronze', 'brand', '🎯', 5,
    (s: ProfileStats) => recGet(s.brandCounts, 'nikon') >= 5,
    (s: ProfileStats) => `${Math.min(recGet(s.brandCounts, 'nikon'), 5)}/5`,
    (s: ProfileStats) => recGet(s.brandCounts, 'nikon')),
  mk('sony_party', '索尼党', '嘴上说不在乎，心里全是镜头群。', 'bronze', 'brand', '🎮', 5,
    (s: ProfileStats) => recGet(s.brandCounts, 'sony') >= 5,
    (s: ProfileStats) => `${Math.min(recGet(s.brandCounts, 'sony'), 5)}/5`,
    (s: ProfileStats) => recGet(s.brandCounts, 'sony')),
  mk('canon_faith', '佳能人', '红圈在你眼里，就是信仰。', 'bronze', 'brand', '❤️', 5,
    (s: ProfileStats) => recGet(s.brandCounts, 'canon') >= 5,
    (s: ProfileStats) => `${Math.min(recGet(s.brandCounts, 'canon'), 5)}/5`,
    (s: ProfileStats) => recGet(s.brandCounts, 'canon')),
  mk('fuji_rich', '富家子弟', '胶片模拟，是你对世界的温柔滤镜。', 'bronze', 'brand', '🎞', 5,
    (s: ProfileStats) => recGet(s.brandCounts, 'fujifilm') >= 5,
    (s: ProfileStats) => `${Math.min(recGet(s.brandCounts, 'fujifilm'), 5)}/5`,
    (s: ProfileStats) => recGet(s.brandCounts, 'fujifilm')),
  mk('leica_de', '德味少年', '每一张，都带着一点「钱的味道」。', 'bronze', 'brand', '🔴', 5,
    (s: ProfileStats) => recGet(s.brandCounts, 'leica') + recGet(s.brandCounts, 'hasselblad') >= 5,
    (s: ProfileStats) => `${Math.min(recGet(s.brandCounts, 'leica') + recGet(s.brandCounts, 'hasselblad'), 5)}/5`,
    (s: ProfileStats) => recGet(s.brandCounts, 'leica') + recGet(s.brandCounts, 'hasselblad')),
  mk('trio', '御三家', '索尼的镜头、佳能的肤色、尼康的宽容度——别人选一家，你全都要。', 'silver', 'brand', '👑', 1,
    (s: ProfileStats) => brandUnlockedOf(s, TRIO_KEYS) >= 3,
    (s: ProfileStats) => `${brandUnlockedOf(s, TRIO_KEYS)}/3`,
    (s: ProfileStats) => brandUnlockedOf(s, TRIO_KEYS)),
  // ---- 器材梗成就 ----
  mk('gearhead', '器材党', '你的柜子里，不止一台伙伴。', 'bronze', 'gear', '🧰', 2,
    (s: ProfileStats) => recCount(s.cameraCounts) >= 2,
    (s: ProfileStats) => `${Math.min(recCount(s.cameraCounts), 2)}/2`,
    (s: ProfileStats) => recCount(s.cameraCounts)),
  mk('one_glass', '一镜走天下', '一个镜头，陪你走遍所有地方。', 'bronze', 'gear', '🔭', 20,
    (s: ProfileStats): boolean => {
      const t: number = recTotal(s.lensCounts);
      return t >= 20 && recMax(s.lensCounts) / t > 0.8;
    },
    (s: ProfileStats) => `${Math.min(recTotal(s.lensCounts), 20)}/20`,
    (s: ProfileStats) => recMax(s.lensCounts)),
  mk('all_rounder', '全家桶', '什么镜头都来一点，什么活都能接。', 'bronze', 'gear', '🧳', 3,
    (s: ProfileStats) => recCount(s.lensCounts) >= 3,
    (s: ProfileStats) => `${Math.min(recCount(s.lensCounts), 3)}/3`,
    (s: ProfileStats) => recCount(s.lensCounts)),
  mk('param_party', '参数党', '型号、镜头、焦距、光圈、快门、ISO——六样参数，一张全齐的照片。', 'bronze', 'gear', '🧾', 1,
    (s: ProfileStats) => s.fullParamCount >= 1,
    (s: ProfileStats) => `参数全齐 ${Math.min(s.fullParamCount, 1)}/1`,
    (s: ProfileStats) => s.fullParamCount),
  mk('first_tag', '第一个标签', '你的第一个标签，已经挂上了。', 'bronze', 'count', '🏷', 1,
    (s: ProfileStats): boolean => {
      return recTotal(s.focalBuckets) > 0 ||
        recTotal(s.apertureBuckets) > 0 || recTotal(s.shutterBuckets) > 0;
    },
    (s: ProfileStats) => '',
    (s: ProfileStats) => s.totalExports),
  // ---- 数量成就 ----
  mk('first', '初见海面', '欢迎来到你的摄影档案，第 1 张照片已记下。', 'bronze', 'count', '🌊', 1,
    (s: ProfileStats) => s.totalExports >= 1,
    (s: ProfileStats) => '',
    (s: ProfileStats) => s.totalExports),
  mk('ten', '熟手', '第十张。快门开始有手感了。', 'bronze', 'count', '🖐', 1,
    (s: ProfileStats) => s.totalExports >= 10,
    (s: ProfileStats) => `${Math.min(s.totalExports, 10)}/10`,
    (s: ProfileStats) => s.totalExports),
  mk('streak_7', '一周之约', '连续七天，你和印痕每天都不见不散。', 'bronze', 'time', '📅', 1,
    (s: ProfileStats) => s.streakDays >= 7,
    (s: ProfileStats) => `${Math.min(s.streakDays, 7)}/7天`,
    (s: ProfileStats) => s.streakDays),
  mk('hundred', '百张俱乐部', '第一百张。你的档案开始有厚度了。', 'silver', 'count', '💯', 1,
    (s: ProfileStats) => s.totalExports >= 100,
    (s: ProfileStats) => `${Math.min(s.totalExports, 100)}/100`,
    (s: ProfileStats) => s.totalExports),
  // ---- 风格成就 ----
  mk('wide', '广角控', '你的镜头总想装下更多世界。', 'silver', 'style', '🌐', 5,
    (s: ProfileStats): boolean => {
      const t: number = recTotal(s.focalBuckets);
      return t >= 5 && recGet(s.focalBuckets, '广角') / t > 0.5;
    },
    (s: ProfileStats) => `广角 ${Math.min(recGet(s.focalBuckets, '广角'), 5)}/5`,
    (s: ProfileStats) => recGet(s.focalBuckets, '广角'),
    false, 'focal'),
  mk('tele', '偷拍侠', '远远地，把故事拉近。', 'silver', 'style', '🔍', 5,
    (s: ProfileStats): boolean => {
      const t: number = recTotal(s.focalBuckets);
      return t >= 5 && recGet(s.focalBuckets, '中长焦') / t > 0.5;
    },
    (s: ProfileStats) => `中长焦 ${Math.min(recGet(s.focalBuckets, '中长焦'), 5)}/5`,
    (s: ProfileStats) => recGet(s.focalBuckets, '中长焦'),
    false, 'focal'),
  mk('big_glass', '大光圈信仰', '虚化是你的签名。', 'silver', 'style', '⭕', 5,
    (s: ProfileStats): boolean => {
      const t: number = recTotal(s.apertureBuckets);
      return t >= 5 && recGet(s.apertureBuckets, '大光圈') / t > 0.5;
    },
    (s: ProfileStats) => `大光圈 ${Math.min(recGet(s.apertureBuckets, '大光圈'), 5)}/5`,
    (s: ProfileStats) => recGet(s.apertureBuckets, '大光圈'),
    false, 'aperture'),
  mk('stop_down', '收光圈党', '你相信细节比氛围更诚实。', 'silver', 'style', '🔸', 5,
    (s: ProfileStats): boolean => {
      const t: number = recTotal(s.apertureBuckets);
      return t >= 5 && recGet(s.apertureBuckets, '小光圈') / t > 0.5;
    },
    (s: ProfileStats) => `小光圈 ${Math.min(recGet(s.apertureBuckets, '小光圈'), 5)}/5`,
    (s: ProfileStats) => recGet(s.apertureBuckets, '小光圈'),
    false, 'aperture'),
  mk('fast_hand', '快门手', '1/250 只是你的起手式。', 'silver', 'style', '⚡', 5,
    (s: ProfileStats): boolean => {
      const t: number = recTotal(s.shutterBuckets);
      return t >= 5 && recGet(s.shutterBuckets, '高速') / t > 0.5;
    },
    (s: ProfileStats) => `高速 ${Math.min(recGet(s.shutterBuckets, '高速'), 5)}/5`,
    (s: ProfileStats) => recGet(s.shutterBuckets, '高速'),
    false, 'shutter'),
  mk('slow_mo', '慢门玩家', '你让时间在画面里流动。', 'silver', 'style', '🌊', 5,
    (s: ProfileStats): boolean => {
      const t: number = recTotal(s.shutterBuckets);
      return t >= 5 && recGet(s.shutterBuckets, '慢门') / t > 0.5;
    },
    (s: ProfileStats) => `慢门 ${Math.min(recGet(s.shutterBuckets, '慢门'), 5)}/5`,
    (s: ProfileStats) => recGet(s.shutterBuckets, '慢门'),
    false, 'shutter'),
  mk('low_iso', 'ISO 洁癖', '噪点？不存在的。', 'silver', 'style', '❄️', 10,
    (s: ProfileStats) => s.isoCount >= 10 && isoMean(s) <= 400,
    (s: ProfileStats) => `ISO均值 ${Math.round(isoMean(s))}`,
    (s: ProfileStats) => isoMean(s),
    false, 'iso'),
  mk('high_iso', '高感狂魔', '光线再暗，你也敢按快门。', 'silver', 'style', '🔥', 10,
    (s: ProfileStats) => s.isoCount >= 10 && isoMean(s) > 1600,
    (s: ProfileStats) => `ISO均值 ${Math.round(isoMean(s))}`,
    (s: ProfileStats) => isoMean(s),
    false, 'iso'),
  // ---- 时间成就 ----
  mk('early_bird', '早鸟', '第一缕光，被你收下了。', 'silver', 'time', '🌅', 5,
    (s: ProfileStats): boolean => {
      return s.totalExports >= 5 && hourRangeSum(s.hourBuckets, 5, 9) / s.totalExports > 0.4;
    },
    (s: ProfileStats) => `早间占比 ${pctText(hourRangeSum(s.hourBuckets, 5, 9), s.totalExports)}`,
    (s: ProfileStats) => hourRangeSum(s.hourBuckets, 5, 9)),
  mk('night_owl', '夜猫子', '城市的灯，比太阳更懂你。', 'silver', 'time', '🦉', 5,
    (s: ProfileStats): boolean => {
      return s.totalExports >= 5 && hourRangeSum(s.hourBuckets, 21, 4) / s.totalExports > 0.4;
    },
    (s: ProfileStats) => `夜间占比 ${pctText(hourRangeSum(s.hourBuckets, 21, 4), s.totalExports)}`,
    (s: ProfileStats) => hourRangeSum(s.hourBuckets, 21, 4)),
  mk('dawn_patrol', '凌晨四点的光', '凌晨四点的光，只给陪它的人看。', 'silver', 'time', '🌌', 1,
    (s: ProfileStats) => hourRangeSum(s.hourBuckets, 3, 5) >= 1,
    (s: ProfileStats) => `凌晨3-5点 ${Math.min(hourRangeSum(s.hourBuckets, 3, 5), 1)}/1`,
    (s: ProfileStats) => hourRangeSum(s.hourBuckets, 3, 5)),
  // ---- 行为成就 ----
  mk('wide_ratio', '横幅党', '你的构图里，总有更宽的风景。', 'silver', 'behavior', '🖥', 5,
    (s: ProfileStats): boolean => {
      return s.totalExports >= 5 && recGet(s.ratioCounts, '16:9') / s.totalExports > 0.5;
    },
    (s: ProfileStats) => `16:9占比 ${pctText(recGet(s.ratioCounts, '16:9'), s.totalExports)}`,
    (s: ProfileStats) => recGet(s.ratioCounts, '16:9'),
    false, 'ratio'),
  mk('square', '方图控', '方方正正，自有秩序。', 'silver', 'behavior', '⬛', 5,
    (s: ProfileStats): boolean => {
      return s.totalExports >= 5 && recGet(s.ratioCounts, '1:1') / s.totalExports > 0.5;
    },
    (s: ProfileStats) => `1:1占比 ${pctText(recGet(s.ratioCounts, '1:1'), s.totalExports)}`,
    (s: ProfileStats) => recGet(s.ratioCounts, '1:1'),
    false, 'ratio'),
  mk('raw_first', '原图至上', '你舍不得裁掉任何一个像素。', 'silver', 'behavior', '🖼', 10,
    (s: ProfileStats): boolean => {
      return s.totalExports >= 10 && recGet(s.ratioCounts, '原图') / s.totalExports > 0.8;
    },
    (s: ProfileStats) => `原图占比 ${pctText(recGet(s.ratioCounts, '原图'), s.totalExports)}`,
    (s: ProfileStats) => recGet(s.ratioCounts, '原图'))
];

// ============ 成就蚀刻章徽章图（key → app.media 资源）============

export const ACH_BADGES: Record<string, Resource> = {
  'thousand': $r('app.media.badge_thousand'),
  'legend': $r('app.media.badge_legend'),
  'polyglot': $r('app.media.badge_polyglot'),
  'decathlon': $r('app.media.badge_decathlon'),
  'brand_united': $r('app.media.badge_brand_united'),
  'time_traveler': $r('app.media.badge_time_traveler'),
  'streak_30': $r('app.media.badge_streak_30'),
  'anniversary': $r('app.media.badge_anniversary'),
  'dragon': $r('app.media.badge_dragon'),
  'nikon_lord': $r('app.media.badge_nikon_lord'),
  'sony_party': $r('app.media.badge_sony_party'),
  'canon_faith': $r('app.media.badge_canon_faith'),
  'fuji_rich': $r('app.media.badge_fuji_rich'),
  'leica_de': $r('app.media.badge_leica_de'),
  'trio': $r('app.media.badge_trio'),
  'gearhead': $r('app.media.badge_gearhead'),
  'one_glass': $r('app.media.badge_one_glass'),
  'all_rounder': $r('app.media.badge_all_rounder'),
  'param_party': $r('app.media.badge_param_party'),
  'first_tag': $r('app.media.badge_first_tag'),
  'first': $r('app.media.badge_first'),
  'ten': $r('app.media.badge_ten'),
  'streak_7': $r('app.media.badge_streak_7'),
  'hundred': $r('app.media.badge_hundred'),
  'wide': $r('app.media.badge_wide'),
  'tele': $r('app.media.badge_tele'),
  'big_glass': $r('app.media.badge_big_glass'),
  'stop_down': $r('app.media.badge_stop_down'),
  'fast_hand': $r('app.media.badge_fast_hand'),
  'slow_mo': $r('app.media.badge_slow_mo'),
  'low_iso': $r('app.media.badge_low_iso'),
  'high_iso': $r('app.media.badge_high_iso'),
  'early_bird': $r('app.media.badge_early_bird'),
  'night_owl': $r('app.media.badge_night_owl'),
  'dawn_patrol': $r('app.media.badge_dawn_patrol'),
  'wide_ratio': $r('app.media.badge_wide_ratio'),
  'square': $r('app.media.badge_square'),
  'raw_first': $r('app.media.badge_raw_first')
};

export function achBadgeOf(key: string): Resource {
  const r: Resource | undefined = ACH_BADGES[key];
  return r !== undefined ? r : $r('app.media.startIcon');
}

// ============ 成就判定（幂等 + 互斥组 + 链式多轮）============

export function judgeAchievements(s: ProfileStats): AchievementDef[] {
  const out: AchievementDef[] = [];
  for (let round = 0; round < 5; round++) {
    const direct: AchievementDef[] = [];
    const groups: Record<string, AchievementDef> = {};
    for (const d of ACHIEVEMENTS) {
      if (isUnlocked(s, d.key)) {
        continue;
      }
      if (s.totalExports < d.minSamples) {
        continue;
      }
      if (!d.check(s)) {
        continue;
      }
      if (d.mutex === '') {
        direct.push(d);
      } else {
        const cur: AchievementDef | undefined = groups[d.mutex];
        if (cur === undefined || d.metric(s) > cur.metric(s)) {
          groups[d.mutex] = d;
        }
      }
    }
    const winners: AchievementDef[] = direct.slice();
    const gks: string[] = Object.keys(groups);
    for (const g of gks) {
      winners.push(groups[g]);
    }
    if (winners.length === 0) {
      break;
    }
    const now: number = Date.now();
    for (const d of winners) {
      s.unlockedAchievements[d.key] = now;
      out.push(d);
    }
  }
  return out;
}

// ============ 本地持久化（Preferences）============

export class ProfileStore {
  private static readonly PREF_NAME: string = 'profile_stats';
  private static readonly KEY_STATS: string = 'stats';

  static async load(context: common.UIAbilityContext): Promise<ProfileStats> {
    try {
      const p: preferences.Preferences = await preferences.getPreferences(context, ProfileStore.PREF_NAME);
      const text: string = p.getSync(ProfileStore.KEY_STATS, '') as string;
      return parseStats(text);
    } catch (err) {
      Logger.error(`profile load failed: ${JSON.stringify(err)}`);
      return new ProfileStats();
    }
  }

  static async save(context: common.UIAbilityContext, s: ProfileStats): Promise<void> {
    try {
      const p: preferences.Preferences = await preferences.getPreferences(context, ProfileStore.PREF_NAME);
      await p.put(ProfileStore.KEY_STATS, JSON.stringify(s));
      await p.flush();
    } catch (err) {
      Logger.error(`profile save failed: ${JSON.stringify(err)}`);
    }
  }

  static async recordExport(context: common.UIAbilityContext, s: ProfileStats,
    rec: ExportRecord): Promise<AchievementDef[]> {
    applyRecord(s, rec);
    const newly: AchievementDef[] = judgeAchievements(s);
    await ProfileStore.save(context, s);
    return newly;
  }
}

// 统计维度数据看板：胶囊维度 Tab（焦段/光圈/快门/ISO/时段/画幅）
// + 主图卡（直方图或雷达）+ 环形占比卡 + Top3 数字卡
// 数据在进入统计页时计算一次并缓存于组件内；Tab 切换不重算，仅重挂载重绘 Canvas，不做实时监听刷新
import { ProfileStats, recGet, recTotal, hourRangeSum, topEntries, NameCount } from '../model/ProfileModels';
import { SegmentItem, SegmentedControl } from './Widgets';

// ============ 数据模型 ============

// 维度柱数据：label 档位名，count 次数，pct 百分比（0-100，取整）
export class DimBar {
  label: string = '';
  count: number = 0;
  pct: number = 0;
}

// 单个维度的看板数据（同一套档位定义，与成就判定共用）
export class DimensionData {
  dim: string = '';
  title: string = '';       // 主图卡标题
  ringTitle: string = '';   // 环形卡标题
  radar: boolean = false;   // true → 主图用六轴雷达（仅时段）
  bars: DimBar[] = [];      // 直方图柱（时段 = 雷达轴）
  ring: DimBar[] = [];      // 环形占比分类
  top3: DimBar[] = [];      // 数字卡 Top3
  total: number = 0;
}

const DIM_KEYS: string[] = ['focal', 'aperture', 'shutter', 'iso', 'time', 'ratio'];
const FOCAL_KEYS: string[] = ['超广', '广角', '标准', '中长焦', '长焦'];
const APERTURE_KEYS: string[] = ['大光圈', '中等', '小光圈'];
const SHUTTER_KEYS: string[] = ['高速', '常规', '慢门'];
const ISO_KEYS: string[] = ['低感', '中感', '高感'];

// 图表配色：与成就/风格分布同源的主题色板
const PALETTE: string[] = ['#4E6EF2', '#6BCB77', '#FFB020', '#FF6B6B', '#B983FF', '#4EC9E1'];

export function paletteColor(i: number): string {
  return PALETTE[i % PALETTE.length];
}

function mkBar(label: string, count: number, total: number): DimBar {
  const b: DimBar = new DimBar();
  b.label = label;
  b.count = count;
  b.pct = total > 0 ? Math.round(count * 100 / total) : 0;
  return b;
}

function barsFromRec(keys: string[], rec: Record<string, number>): DimBar[] {
  const total: number = recTotal(rec);
  const out: DimBar[] = [];
  for (const k of keys) {
    out.push(mkBar(k, recGet(rec, k), total));
  }
  return out;
}

function sumBars(bars: DimBar[]): number {
  let t: number = 0;
  for (const b of bars) {
    t += b.count;
  }
  return t;
}

function sortedTop(bars: DimBar[], n: number): DimBar[] {
  const copy: DimBar[] = bars.slice();
  copy.sort((a: DimBar, b: DimBar) => b.count - a.count);
  const out: DimBar[] = [];
  for (const b of copy) {
    if (b.count <= 0 || out.length >= n) {
      continue;
    }
    out.push(b);
  }
  return out;
}

// 由聚合统计构建某一维度的看板数据（档位与成就判定同一套）
export function buildDimensionData(s: ProfileStats, dim: string): DimensionData {
  const d: DimensionData = new DimensionData();
  d.dim = dim;
  if (dim === 'focal') {
    d.title = '焦段分布';
    d.ringTitle = '焦段占比';
    d.bars = barsFromRec(FOCAL_KEYS, s.focalBuckets);
    d.ring = d.bars;
  } else if (dim === 'aperture') {
    d.title = '光圈分布';
    d.ringTitle = '光圈占比';
    d.bars = barsFromRec(APERTURE_KEYS, s.apertureBuckets);
    d.ring = d.bars;
  } else if (dim === 'shutter') {
    d.title = '快门分布';
    d.ringTitle = '快门占比';
    d.bars = barsFromRec(SHUTTER_KEYS, s.shutterBuckets);
    d.ring = d.bars;
  } else if (dim === 'iso') {
    d.title = 'ISO 分布';
    d.ringTitle = 'ISO 占比';
    d.bars = barsFromRec(ISO_KEYS, s.isoBuckets);
    d.ring = d.bars;
  } else if (dim === 'time') {
    d.title = '拍摄时段';
    d.ringTitle = '时段占比';
    d.radar = true;
    // 六段划分（覆盖全 24 小时）：清晨 5-8 / 上午 9-11 / 中午 12-13 / 下午 14-17 / 傍晚 18-20 / 深夜 21-4
    const dawn: number = hourRangeSum(s.hourBuckets, 5, 8);
    const morning: number = hourRangeSum(s.hourBuckets, 9, 11);
    const noon: number = hourRangeSum(s.hourBuckets, 12, 13);
    const afternoon: number = hourRangeSum(s.hourBuckets, 14, 17);
    const dusk: number = hourRangeSum(s.hourBuckets, 18, 20);
    const lateNight: number = hourRangeSum(s.hourBuckets, 21, 4);
    const t: number = dawn + morning + noon + afternoon + dusk + lateNight;
    d.bars = [mkBar('清晨', dawn, t), mkBar('上午', morning, t), mkBar('中午', noon, t),
      mkBar('下午', afternoon, t), mkBar('傍晚', dusk, t), mkBar('深夜', lateNight, t)];
    d.ring = d.bars;
  } else {
    d.title = '画幅分布';
    d.ringTitle = '画幅占比';
    const entries: NameCount[] = topEntries(s.ratioCounts, 6);
    const total: number = recTotal(s.ratioCounts);
    const bars: DimBar[] = [];
    for (const e of entries) {
      bars.push(mkBar(e.name, e.count, total));
    }
    d.bars = bars;
    d.ring = bars;
  }
  d.top3 = sortedTop(d.ring, 3);
  d.total = sumBars(d.ring);
  return d;
}

// ============ 主图卡：柱状直方图（点柱子弹浮层，点浮层任意处关闭）============

@Component
struct HistogramCard {
  data: DimensionData = new DimensionData();
  @State activeBar: number = -1;
  private canvasW: number = 0;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  private hasData(): boolean {
    return this.data.bars.length > 0 && this.data.total > 0;
  }

  private draw(): void {
    const w: number = this.ctx.width;
    const h: number = this.ctx.height;
    this.canvasW = w;
    this.ctx.clearRect(0, 0, w, h);
    const bars: DimBar[] = this.data.bars;
    const n: number = bars.length;
    if (w <= 0 || n === 0) {
      return;
    }
    const slot: number = w / n;
    const barW: number = Math.min(30, slot * 0.55);
    let max: number = 0;
    for (const b of bars) {
      if (b.count > max) {
        max = b.count;
      }
    }
    if (max <= 0) {
      max = 1;
    }
    const plotH: number = h - 10;
    // 基线
    this.ctx.strokeStyle = '#E4E8EF';
    this.ctx.lineWidth = 1;
    this.ctx.beginPath();
    this.ctx.moveTo(0, h - 0.5);
    this.ctx.lineTo(w, h - 0.5);
    this.ctx.stroke();
    for (let i = 0; i < n; i++) {
      const b: DimBar = bars[i];
      const bh: number = b.count > 0 ? Math.max(6, plotH * b.count / max) : 2;
      const x: number = slot * i + (slot - barW) / 2;
      this.ctx.fillStyle = b.count > 0 ? paletteColor(i) : '#E4E8EF';
      this.ctx.fillRect(x, h - bh, barW, bh);
    }
  }

  private onTapBar(x: number): void {
    const bars: DimBar[] = this.data.bars;
    const n: number = bars.length;
    if (n === 0 || this.canvasW <= 0) {
      return;
    }
    const slot: number = this.canvasW / n;
    let idx: number = Math.floor(x / slot);
    if (idx < 0) {
      idx = 0;
    }
    if (idx > n - 1) {
      idx = n - 1;
    }
    if (bars[idx].count <= 0) {
      this.activeBar = -1;
      return;
    }
    this.activeBar = this.activeBar === idx ? -1 : idx;
  }

  private bubbleLeft(): number {
    const n: number = this.data.bars.length;
    if (n === 0 || this.canvasW <= 0) {
      return 8;
    }
    const slot: number = this.canvasW / n;
    const center: number = slot * this.activeBar + slot / 2;
    return Math.max(4, Math.min(center - 65, this.canvasW - 134));
  }

  build() {
    Column({ space: 12 }) {
      Text(this.data.title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_main'))
        .width('100%')
      if (this.hasData()) {
        Stack({ alignContent: Alignment.TopStart }) {
          Canvas(this.ctx)
            .width('100%')
            .height(170)
            .onReady(() => {
              this.draw();
            })
            .onClick((e: ClickEvent) => {
              this.onTapBar(e.x);
            })
          if (this.activeBar >= 0 && this.activeBar < this.data.bars.length) {
            Column({ space: 3 }) {
              Text(`${this.data.bars[this.activeBar].label}：${this.data.bars[this.activeBar].count} 次`)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_main'))
              Text(`占 ${this.data.bars[this.activeBar].pct}%`)
                .fontSize(11)
                .fontColor($r('app.color.text_sub'))
            }
            .padding({ left: 14, right: 14, top: 9, bottom: 9 })
            .borderRadius(12)
            .backgroundColor($r('app.color.card_bg'))
            .border({ width: 1, color: $r('app.color.border_soft') })
            .shadow({ radius: 12, color: '#22000000', offsetX: 0, offsetY: 3 })
            .margin({ left: this.bubbleLeft(), top: 6 })
            .onClick(() => {
              this.activeBar = -1;
            })
          }
        }
        .width('100%')

        Row() {
          ForEach(this.data.bars, (b: DimBar) => {
            Text(b.label)
              .fontSize(10)
              .fontColor($r('app.color.text_hint'))
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
              .maxLines(1)
          }, (b: DimBar) => `${b.label}-${b.count}`)
        }
        .width('100%')
      } else {
        Text('暂无数据')
          .fontSize(12)
          .fontColor($r('app.color.text_hint'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 32, bottom: 32 })
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius(12)
    .backgroundColor($r('app.color.field_bg'))
  }
}

// ============ 主图卡：六轴雷达（清晨/上午/中午/下午/傍晚/深夜，静态无交互）============

@Component
struct RadarCard {
  data: DimensionData = new DimensionData();
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  private hasData(): boolean {
    return this.data.bars.length > 0 && this.data.total > 0;
  }

  private draw(): void {
    const cx: number = 110;
    const cy: number = 110;
    const r: number = 78;
    const bars: DimBar[] = this.data.bars;
    const n: number = bars.length;
    const step: number = 360 / n;
    this.ctx.clearRect(0, 0, 220, 220);
    if (n === 0) {
      return;
    }
    // 网格环（三层五边形）
    this.ctx.strokeStyle = '#E4E8EF';
    this.ctx.lineWidth = 1;
    const fracs: number[] = [1 / 3, 2 / 3, 1];
    for (const f of fracs) {
      this.ctx.beginPath();
      for (let i = 0; i < n; i++) {
        const ang: number = (-90 + step * i) * Math.PI / 180;
        const px: number = cx + r * f * Math.cos(ang);
        const py: number = cy + r * f * Math.sin(ang);
        if (i === 0) {
          this.ctx.moveTo(px, py);
        } else {
          this.ctx.lineTo(px, py);
        }
      }
      this.ctx.closePath();
      this.ctx.stroke();
    }
    // 轴线
    for (let i = 0; i < n; i++) {
      const ang: number = (-90 + step * i) * Math.PI / 180;
      this.ctx.beginPath();
      this.ctx.moveTo(cx, cy);
      this.ctx.lineTo(cx + r * Math.cos(ang), cy + r * Math.sin(ang));
      this.ctx.stroke();
    }
    // 数据多边形
    let max: number = 0;
    for (const b of bars) {
      if (b.count > max) {
        max = b.count;
      }
    }
    if (max <= 0) {
      max = 1;
    }
    this.ctx.beginPath();
    for (let i = 0; i < n; i++) {
      const ang: number = (-90 + step * i) * Math.PI / 180;
      const rr: number = r * bars[i].count / max;
      const px: number = cx + rr * Math.cos(ang);
      const py: number = cy + rr * Math.sin(ang);
      if (i === 0) {
        this.ctx.moveTo(px, py);
      } else {
        this.ctx.lineTo(px, py);
      }
    }
    this.ctx.closePath();
    this.ctx.globalAlpha = 0.22;
    this.ctx.fillStyle = '#4E6EF2';
    this.ctx.fill();
    this.ctx.globalAlpha = 1;
    this.ctx.strokeStyle = '#4E6EF2';
    this.ctx.lineWidth = 2;
    this.ctx.stroke();
    // 顶点圆点
    this.ctx.fillStyle = '#4E6EF2';
    for (let i = 0; i < n; i++) {
      const ang: number = (-90 + step * i) * Math.PI / 180;
      const rr: number = r * bars[i].count / max;
      this.ctx.beginPath();
      this.ctx.arc(cx + rr * Math.cos(ang), cy + rr * Math.sin(ang), 3, 0, Math.PI * 2);
      this.ctx.fill();
    }
  }

  private labelPos(i: number): Position {
    const step: number = 360 / this.data.bars.length;
    const ang: number = (-90 + step * i) * Math.PI / 180;
    const p: Position = { x: 110 + 98 * Math.cos(ang), y: 110 + 98 * Math.sin(ang) };
    return p;
  }

  build() {
    Column({ space: 12 }) {
      Text(this.data.title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_main'))
        .width('100%')
      if (this.hasData()) {
        Stack({ alignContent: Alignment.TopStart }) {
          Canvas(this.ctx)
            .width(220)
            .height(220)
            .onReady(() => {
              this.draw();
            })
          ForEach(this.data.bars, (b: DimBar, i: number) => {
            Text(b.label)
              .fontSize(11)
              .fontColor($r('app.color.text_hint'))
              .position(this.labelPos(i))
              .markAnchor({ x: '50%', y: '50%' })
              .maxLines(1)
          }, (b: DimBar, i: number) => `${i}-${b.label}`)
        }
        .width(220)
        .height(220)
      } else {
        Text('暂无数据')
          .fontSize(12)
          .fontColor($r('app.color.text_hint'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 32, bottom: 32 })
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius(12)
    .backgroundColor($r('app.color.field_bg'))
    .alignItems(HorizontalAlign.Center)
  }
}

// ============ 环形占比卡（静态无交互）============

@Component
struct RingCard {
  data: DimensionData = new DimensionData();
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  private hasData(): boolean {
    return this.data.ring.length > 0 && this.data.total > 0;
  }

  private draw(): void {
    const cx: number = 80;
    const cy: number = 80;
    const midR: number = 62;
    const ring: DimBar[] = this.data.ring;
    const total: number = this.data.total;
    this.ctx.clearRect(0, 0, 160, 160);
    if (total <= 0) {
      return;
    }
    // 底环
    this.ctx.strokeStyle = '#E4E8EF';
    this.ctx.lineWidth = 20;
    this.ctx.beginPath();
    this.ctx.arc(cx, cy, midR, 0, Math.PI * 2);
    this.ctx.stroke();
    let start: number = -Math.PI / 2;
    for (let i = 0; i < ring.length; i++) {
      const b: DimBar = ring[i];
      if (b.count <= 0) {
        continue;
      }
      const sweep: number = b.count / total * Math.PI * 2;
      this.ctx.strokeStyle = paletteColor(i);
      this.ctx.lineWidth = 20;
      this.ctx.beginPath();
      this.ctx.arc(cx, cy, midR, start, start + sweep);
      this.ctx.stroke();
      start += sweep;
    }
  }

  build() {
    Column({ space: 12 }) {
      Text(this.data.ringTitle)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_main'))
        .width('100%')
      if (this.hasData()) {
        Stack({ alignContent: Alignment.Center }) {
          Canvas(this.ctx)
            .width(160)
            .height(160)
            .onReady(() => {
              this.draw();
            })
          Column() {
            Text(`${this.data.total}`)
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_main'))
            Text('张')
              .fontSize(10)
              .fontColor($r('app.color.text_hint'))
          }
          .alignItems(HorizontalAlign.Center)
        }
        .width(160)
        .height(160)

        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
          ForEach(this.data.ring, (b: DimBar, i: number) => {
            if (b.count > 0) {
              Row({ space: 5 }) {
                Circle({ width: 8, height: 8 })
                  .fill(paletteColor(i))
                Text(`${b.label} ${b.pct}%`)
                  .fontSize(11)
                  .fontColor($r('app.color.text_sub'))
              }
              .margin({ right: 12, bottom: 4 })
            }
          }, (b: DimBar, i: number) => `${i}-${b.label}-${b.count}`)
        }
        .width('100%')
      } else {
        Text('暂无数据')
          .fontSize(12)
          .fontColor($r('app.color.text_hint'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 32, bottom: 32 })
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius(12)
    .backgroundColor($r('app.color.field_bg'))
    .alignItems(HorizontalAlign.Center)
  }
}

// ============ Top3 数字卡（静态无交互）============

@Component
struct Top3Card {
  data: DimensionData = new DimensionData();

  build() {
    Column({ space: 12 }) {
      Text('最常用 Top3')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_main'))
        .width('100%')
      if (this.data.top3.length > 0) {
        ForEach(this.data.top3, (b: DimBar, i: number) => {
          Column({ space: 7 }) {
            Row({ space: 8 }) {
              Text(`${i + 1}`)
                .fontSize(11)
                .fontColor($r('app.color.text_hint'))
                .width(14)
              Text(b.label)
                .fontSize(13)
                .fontColor($r('app.color.text_sub'))
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`${b.count} 次 · ${b.pct}%`)
                .fontSize(12)
                .fontColor($r('app.color.accent'))
            }
            .width('100%')

            Row() {
              Row()
                .width(`${Math.max(4, b.pct)}%`)
                .height(3)
                .borderRadius(2)
                .backgroundColor(paletteColor(i))
            }
            .width('100%')
            .backgroundColor($r('app.color.chip_bg'))
            .borderRadius(2)
          }
          .width('100%')
        }, (b: DimBar, i: number) => `${i}-${b.label}-${b.count}`)
      } else {
        Text('暂无数据')
          .fontSize(12)
          .fontColor($r('app.color.text_hint'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 24, bottom: 24 })
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius(12)
    .backgroundColor($r('app.color.field_bg'))
  }
}

// ============ 看板：维度 Tab + 三张卡片 ============

@Component
export struct StatsDashboard {
  stats: ProfileStats = new ProfileStats();
  @State dim: number = 0;
  private cached: DimensionData[] = [];
  private dimItems: SegmentItem[] = [
    new SegmentItem('焦段', 0),
    new SegmentItem('光圈', 1),
    new SegmentItem('快门', 2),
    new SegmentItem('ISO', 3),
    new SegmentItem('时段', 4),
    new SegmentItem('画幅', 5)
  ];

  aboutToAppear(): void {
    // 进入统计页整体算一次并缓存；Tab 切换不重算
    const out: DimensionData[] = [];
    for (const k of DIM_KEYS) {
      out.push(buildDimensionData(this.stats, k));
    }
    this.cached = out;
  }

  private cur(): DimensionData {
    if (this.dim >= 0 && this.dim < this.cached.length) {
      return this.cached[this.dim];
    }
    return new DimensionData();
  }

  build() {
    Column({ space: 12 }) {
      SegmentedControl({
        items: this.dimItems,
        selected: this.dim,
        onPick: (v: number) => {
          this.dim = v;
        }
      })
      // 以维度为 key 的 ForEach：切换 Tab 时整组卡片重挂载，Canvas 重绘（数据不重算）
      ForEach([this.dim], (d: number) => {
        Column({ space: 12 }) {
          if (this.cached[d].radar) {
            RadarCard({ data: this.cached[d] })
          } else {
            HistogramCard({ data: this.cached[d] })
          }
          RingCard({ data: this.cached[d] })
          Top3Card({ data: this.cached[d] })
        }
        .width('100%')
      }, (d: number) => `${d}`)
    }
    .width('100%')
  }
}

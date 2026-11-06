import { image } from '@kit.ImageKit';
import { display, window, router, uiMaterial, componentSnapshot, curves } from '@kit.ArkUI';
import {
  PhotoPickerComponent,
  PickerController,
  PickerOptions,
  ReminderMode,
  photoAccessHelper
} from '@kit.MediaLibraryKit';
import { common, bundleManager, ConfigurationConstant } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { pasteboard } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { ImageTools, HdrJpegParts, PersonalLogoResult } from '../utils/ImageTools';
import { Logger } from '../utils/Logger';
import {
  ExifInfo,
  CanvasLayout,
  FrameLayout,
  StylePreset,
  PhotoItem,
  fillExifGaps,
  buildPresets,
  computeFrameLayout,
  scaleLayout,
  BAR_GAP,
  BAR_LH,
  TITLE_FACTOR,
  TITLE_SPLIT_FACTOR,
  TITLE_SPLIT_LENS_FACTOR,
  DATE_SPLIT_FACTOR,
  CAL_DAY_FACTOR,
  CAL_DAY_LH,
  CAL_BOX_LH,
  CAL_MARGIN,
  CAL_YM_COLOR,
  EXPO_HEAD_LH,
  EXPO_SUB_LH,
  EXPO_GAP,
  WM_TEXT_COLORS,
  FRAME_COLORS,
  KEYLINE_COLORS,
  BrandLogo,
  BRAND_LOGOS,
  detectBrand,
  brandByKey,
  cleanModelText,
  cleanMakeText,
  savedStylesToRaw,
  parseSavedStyles,
  builtinFavsToRaw,
  applyBuiltinFavs
} from '../model/WatermarkModels';
import {
  SegmentItem,
  SegmentedControl,
  SectionTabs,
  LabeledSlider,
  ColorSwatches,
  ToggleRow,
  FieldRow
} from '../components/Widgets';
import { StatsDashboard } from '../components/StatsCharts';
import {
  ExportRecord,
  ProfileStats,
  AchievementDef,
  ACHIEVEMENTS,
  achBadgeOf,
  ProfileStore,
  buildExportRecord,
  dayStartTs,
  isUnlocked,
  unlockTs,
  unlockedCount,
  topEntries,
  NameCount
} from '../model/ProfileModels';

const BIT_MAKE: number = 1;
const BIT_MODEL: number = 2;
const BIT_LENS: number = 4;
const BIT_FOCAL: number = 8;
const BIT_FOCAL35: number = 16;
const BIT_APERTURE: number = 32;
const BIT_SHUTTER: number = 64;
const BIT_ISO: number = 128;
const BIT_PROGRAM: number = 256;
const BIT_DATE: number = 512;
const BIT_SIGN: number = 1024;
const DEFAULT_MASK: number = 255;
const PAR_TAG_FACTOR: number = 0.8;
const CONTACT_EMAIL: string = '1194942391@qq.com';

// 成就墙分组（彩蛋 → 金 → 银 → 铜）
class AchGroup {
  title: string = '';
  defs: AchievementDef[] = [];
  unlocked: number = 0;
}

@CustomDialog
struct AboutDialog {
  controller?: CustomDialogController;
  @State verName: string = '1.0.0';

  aboutToAppear(): void {
    bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      .then((info: bundleManager.BundleInfo) => {
        if (info.versionName !== '') {
          this.verName = info.versionName;
        }
      })
      .catch((err: Object) => {
        Logger.error(`AboutDialog version failed: ${JSON.stringify(err)}`);
      });
  }

  build() {
    Column({ space: 16 }) {
      Image($r('app.media.foreground'))
        .width(80)
        .height(80)
        .borderRadius(20)
      Text('印痕')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_main'))
      Text(`版本 ${this.verName}`)
        .fontSize(13)
        .fontColor($r('app.color.text_sub'))
      Column({ space: 8 }) {
        Text('系统要求：HarmonyOS 7.0 及以上')
          .fontSize(13)
          .fontColor($r('app.color.text_sub'))
        Text('开发者：潘思哲')
          .fontSize(13)
          .fontColor($r('app.color.text_sub'))
      }
      .alignItems(HorizontalAlign.Center)
      Text('隐私协议')
        .fontSize(14)
        .fontColor($r('app.color.accent'))
        .padding({ left: 28, right: 28, top: 10, bottom: 10 })
        .backgroundColor($r('app.color.chip_bg'))
        .borderRadius(18)
        .onClick(() => {
          this.controller?.close();
          router.pushUrl({ url: 'pages/WebViewer' });
        })
      Text('关闭')
        .fontSize(14)
        .fontColor($r('app.color.text_sub'))
        .padding({ top: 4, bottom: 4 })
        .onClick(() => {
          this.controller?.close();
        })
    }
    .padding({ top: 28, bottom: 20, left: 28, right: 28 })
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(20)
    .alignItems(HorizontalAlign.Center)
  }
}

@CustomDialog
struct AchievementDetailDialog {
  controller?: CustomDialogController;
  def: AchievementDef = new AchievementDef();
  unlocked: boolean = false;
  unlockTime: string = '';
  progressText: string = '';

  build() {
    Column({ space: 12 }) {
      if (this.unlocked || !this.def.hidden) {
        Image(achBadgeOf(this.def.key))
          .width(72)
          .height(72)
          .opacity(this.unlocked ? 1 : 0.4)
      } else {
        Image($r('app.media.badge_hidden'))
          .width(72)
          .height(72)
      }
      Text(this.unlocked || !this.def.hidden ? this.def.name : '???')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_main'))
      Text(this.unlocked ? this.def.desc : (this.def.hidden ? '隐藏成就，继续探索吧' : this.def.desc))
        .fontSize(13)
        .fontColor($r('app.color.text_sub'))
        .textAlign(TextAlign.Center)
        .lineHeight(20)
      Text(this.unlocked ? `解锁于 ${this.unlockTime}` :
        (this.progressText === '' ? '继续加油' : `进度 ${this.progressText}`))
        .fontSize(12)
        .fontColor($r('app.color.accent'))
      Text('关闭')
        .fontSize(14)
        .fontColor($r('app.color.text_hint'))
        .padding({ left: 20, right: 20, top: 6, bottom: 6 })
        .onClick(() => {
          this.controller?.close();
        })
    }
    .width(280)
    .padding(24)
    .borderRadius(20)
    .backgroundColor($r('app.color.card_bg'))
    .alignItems(HorizontalAlign.Center)
  }
}

@Entry
@Component
struct Index {
  @State pixelMap: image.PixelMap | undefined = undefined;
  @State bgMap: image.PixelMap | undefined = undefined;
  @State imgW: number = 0;
  @State imgH: number = 0;
  @State exif: ExifInfo = new ExifInfo();
  @State showMask: number = DEFAULT_MASK;
  @State alignMode: number = 1;
  @State textColor: string = '#222222';
  @State sizeScalePct: number = 100;
  @State frameMode: number = 1;
  @State layoutKind: number = 0;
  @State directPos: number = 0;
  @State keylineOn: boolean = false;
  @State keylineColor: string = '#222222';
  @State barLayout: number = 0;
  // 曝光参数以胶囊标签展示（四枚：焦距/光圈/快门/ISO）
  @State parTags: boolean = false;
  @State shadowMode: number = 1;
  @State filmStyle: boolean = false;
  @State blurPct: number = 12;
  @State frameMarginPct: number = 6;
  @State frameColor: string = '#FFFFFF';
  @State exportRatio: number = 0;
  @State exportPng: boolean = false;
  @State activeTab: number = 0;
  @State saving: boolean = false;
  // 风格画像：本地聚合统计 + 成就解锁弹窗队列
  @State profileStats: ProfileStats = new ProfileStats();
  @State achToastShow: boolean = false;
  @State achToastDefs: AchievementDef[] = [];
  // 版式页内分段：0=排版 1=边框
  @State layoutSection: number = 0;
  // 我的页内分段：0=统计 1=成就墙 2=设置
  @State mineSection: number = 0;
  private achQueue: AchievementDef[][] = [];
  private achToastTimer: number = -1;
  private panelScroller: Scroller = new Scroller();
  @State statusBarH: number = 0;
  @State navBarH: number = 0;
  // 上划隐藏导航胶囊、下滑恢复
  @State navBarHidden: boolean = false;
  private lastPanelScrollY: number = 0;
  @State photoItems: PhotoItem[] = [];
  @State currentIdx: number = 0;
  @State batchRunning: boolean = false;
  @State batchStatus: string = '';
  private manualDefaults: ExifInfo = new ExifInfo();
  @State activePreset: string = '';
  @State skinMode: number = -1;
  @StorageProp('sysColorMode') @Watch('onSysColorChange') sysColorMode: number = -1;
  @State cacheText: string = '';
  @State tabClickXPct: string = '50%';
  @State private presetGridW: number = 320;
  aboutCtl: CustomDialogController = new CustomDialogController({
    builder: AboutDialog(),
    customStyle: true,
    alignment: DialogAlignment.Center
  });
  @State logoOn: boolean = true;
  @State brandPick: string = '';
  // 个人 Logo：aspect>0 表示已导入可用；mode 0=关闭 1=替换品牌Logo 2=替换署名
  @State personalLogoAspect: number = 0;
  @State personalLogoColor: boolean = false;
  @State personalLogoMode: number = 0;
  private logoDir: string = '';
  private personalEntry: BrandLogo = new BrandLogo('', '', '', '', 4);
  private personalModeItems: SegmentItem[] = [
    new SegmentItem('关闭', 0),
    new SegmentItem('替换品牌Logo', 1),
    new SegmentItem('替换署名', 2)
  ];
  @State canvasC: CanvasLayout = new CanvasLayout();
  @State zoomScale: number = 1;
  @State zoomX: number = 0;
  @State zoomY: number = 0;
  private pinchStartScale: number = 1;
  private pinchStartX: number = 0;
  private pinchStartY: number = 0;
  private panStartX: number = 0;
  private panStartY: number = 0;
  @State private previewAreaW: number = 0;
  @State private previewAreaH: number = 0;
  private sourceUri: string = '';
  private decodedLongEdge: number = -1;
  private decodedRatio: number = -1;
  private density: number = 3;
  private screenWVp: number = 360;
  private screenHVp: number = 780;
  @State private winWVp: number = 360;
  @State private winHVp: number = 780;
  @State private isWide: boolean = false;
  @State private hoverMode: boolean = false;
  @State private hoverVertical: boolean = false;
  @State private hoverCreaseTopVp: number = 0;
  @State private hoverCreaseH: number = 0;
  @State private hoverCreaseLeftVp: number = 0;
  @State private hoverCreaseW: number = 0;
  @State private hoverMenuLeft: boolean = false;
  @State private hoverPickerShow: boolean = false;
  @State private hoverPickerInlineShow: boolean = false;
  @State private hoverPickCount: number = 0;
  @State private hoverPickerController: PickerController = new PickerController();
  private hoverPickerOptions: PickerOptions = new PickerOptions();
  private hoverPickUris: string[] = [];
  @State private paneRatio: number = 0.36;
  @State private stripWVp: number = 0;
  @State private panelScrollHVp: number = 0;
  @State private presetSingleCol: boolean = false;
  private paneDragStart: number = 0.36;
  private floatBarMaterial: uiMaterial.ImmersiveMaterial = new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.THIN,
    colorInvert: true,
    applyShadow: false,
    interactive: true,
    lightEffect: { color: Color.White }
  });
  @State private barOverDark: boolean = false;
  private barLumaBusy: boolean = false;
  private barLumaLast: number = 0;
  private foldStatusCb: Callback<display.FoldStatus> = (s: display.FoldStatus) => {
    this.applyFoldStatus(s, true);
  };
  private displayChangeCb: Callback<number> = () => {
    if (this.hoverMode) {
      this.applyFoldStatus(display.getFoldStatus(), true);
      this.scheduleHoverReverify();
    }
  };
  private hoverVerifyTimer: number = -1;
  private presets: StylePreset[] = buildPresets();
  // 个人样式与收藏：styleList 为展示序列（收藏置顶），savedStyles 仅个人样式
  @State styleList: StylePreset[] = [];
  @State favIds: string[] = [];
  private savedStyles: StylePreset[] = [];
  private styleDir: string = '';
  // 收藏红心动画：heartAnimId 命中当前播放的卡片，fill 0→1 为填充进度
  @State heartAnimId: string = '';
  @State heartFill: number = 0;
  @State heartPop: number = 1;
  @State heartAlpha: number = 0;
  private lastLongPressAt: number = 0;
  private tabItems: SegmentItem[] = [
    new SegmentItem('样式', 0),
    new SegmentItem('参数', 1),
    new SegmentItem('版式', 2),
    new SegmentItem('导出', 3),
    new SegmentItem('我的', 4)
  ];
  // 版式页分段：0=排版 1=边框
  private layoutSectionItems: SegmentItem[] = [
    new SegmentItem('排版', 0),
    new SegmentItem('边框', 1)
  ];
  // 我的页分段：0=统计 1=成就墙 2=设置
  private mineSectionItems: SegmentItem[] = [
    new SegmentItem('统计', 0),
    new SegmentItem('成就墙', 1),
    new SegmentItem('设置', 2)
  ];
  private skinItems: SegmentItem[] = [
    new SegmentItem('深色', 0),
    new SegmentItem('浅色', 1),
    new SegmentItem('跟随系统', -1)
  ];
  private frameModeItems: SegmentItem[] = [
    new SegmentItem('直印', 0),
    new SegmentItem('纯色', 1),
    new SegmentItem('模糊', 2)
  ];
  private barLayoutItems: SegmentItem[] = [
    new SegmentItem('居中', 0),
    new SegmentItem('分栏', 1),
    new SegmentItem('台历', 2),
    new SegmentItem('会展', 3)
  ];
  private shadowItems: SegmentItem[] = [
    new SegmentItem('偏移', 0),
    new SegmentItem('悬浮', 1),
    new SegmentItem('下沉', 2)
  ];
  private alignItems: SegmentItem[] = [
    new SegmentItem('左对齐', 0),
    new SegmentItem('居中', 1),
    new SegmentItem('右对齐', 2)
  ];
  private directPosItems: SegmentItem[] = [
    new SegmentItem('底部', 0),
    new SegmentItem('右下', 1),
    new SegmentItem('左下', 2),
    new SegmentItem('左上', 3)
  ];
  private layoutKindItems: SegmentItem[] = [
    new SegmentItem('标准', 0),
    new SegmentItem('拍立得', 1),
    new SegmentItem('画廊', 2)
  ];
  private exportRatioItems: SegmentItem[] = [
    new SegmentItem('原图', 0),
    new SegmentItem('1:1', 1),
    new SegmentItem('4:3', 4 / 3),
    new SegmentItem('3:4', 3 / 4),
    new SegmentItem('16:9', 16 / 9),
    new SegmentItem('9:16', 9 / 16)
  ];
  private formatItems: SegmentItem[] = [
    new SegmentItem('JPG', 0),
    new SegmentItem('PNG', 1)
  ];

  aboutToAppear(): void {
    const disp: display.Display = display.getDefaultDisplaySync();
    this.density = disp.densityPixels;
    this.screenWVp = disp.width / this.density;
    this.screenHVp = disp.height / this.density;
    this.winWVp = this.screenWVp;
    this.winHVp = this.screenHVp;
    this.updateWide();
    Logger.init(this.getUIContext().getHostContext() as common.UIAbilityContext);
    try {
      Logger.info(`material level=${uiMaterial.getGlobalMaterialLevel()} ` +
        `supported=${uiMaterial.isImmersiveMaterialSupported()} ` +
        `state=${uiMaterial.getMaterialInfo().state}`);
    } catch (err) {
      Logger.error(`material info failed: ${JSON.stringify(err)}`);
    }
    try {
      this.applyFoldStatus(display.getFoldStatus(), false);
      display.on('foldStatusChange', this.foldStatusCb);
      display.on('change', this.displayChangeCb);
    } catch (err) {
      Logger.error(`foldStatusChange subscribe failed: ${JSON.stringify(err)}`);
    }
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    window.getLastWindow(ctx).then((win: window.Window) => {
      const rect = win.getWindowProperties().windowRect;
      this.winWVp = Math.round(rect.width / this.density);
      this.winHVp = Math.round(rect.height / this.density);
      this.updateWide();
      try {
        const sysAvoid: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        this.statusBarH = sysAvoid.topRect.height / this.density;
        const navAvoid: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
        this.navBarH = navAvoid.bottomRect.height / this.density;
      } catch (err) {
        Logger.error(`getAvoidArea failed: ${JSON.stringify(err)}`);
      }
      win.on('windowSizeChange', (data: window.Size) => {
        this.winWVp = Math.round(data.width / this.density);
        this.winHVp = Math.round(data.height / this.density);
        this.updateWide();
        if (this.hoverMode) {
          this.applyFoldStatus(display.getFoldStatus(), true);
          this.scheduleHoverReverify();
        }
      });
    });
    this.hoverPickerOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    this.hoverPickerOptions.maxSelectNumber = 20;
    this.hoverPickerOptions.maxSelectedReminderMode = ReminderMode.TOAST;
    this.loadSettings();
    this.refreshCacheSize();
    const profileCtx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    ProfileStore.load(profileCtx).then((s: ProfileStats) => {
      this.profileStats = s;
    }).catch((err: Object) => {
      Logger.error(`profile load failed: ${JSON.stringify(err)}`);
    });
  }

  aboutToDisappear(): void {
    if (this.achToastTimer >= 0) {
      clearTimeout(this.achToastTimer);
      this.achToastTimer = -1;
    }
    try {
      display.off('foldStatusChange', this.foldStatusCb);
      display.off('change', this.displayChangeCb);
    } catch (err) {
      Logger.error(`foldStatusChange unsubscribe failed: ${JSON.stringify(err)}`);
    }
  }

  private async loadSettings(): Promise<void> {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.logoDir = `${context.filesDir}/logo`;
    this.styleDir = `${context.filesDir}/styles`;
    try {
      if (!fileIo.accessSync(this.styleDir)) {
        fileIo.mkdirSync(this.styleDir);
      }
    } catch (err) {
      Logger.error(`WMSTYLE styles dir init failed: ${JSON.stringify(err)}`);
    }
    this.rebuildStyleList();
    try {
      const p: preferences.Preferences = await preferences.getPreferences(context, 'app_settings');
      this.skinMode = p.getSync('skinMode', -1) as number;
      // 恢复个人样式（校验缩略图仍存在）与内置样式收藏
      this.savedStyles = parseSavedStyles(p.getSync('savedStyles', '[]') as string, this.styleDir);
      for (let i = this.savedStyles.length - 1; i >= 0; i--) {
        if (!fileIo.accessSync(this.savedStyles[i].refFile)) {
          this.savedStyles.splice(i, 1);
        }
      }
      applyBuiltinFavs(this.presets, p.getSync('builtinFavs', '[]') as string);
      this.rebuildStyleList();
      // 恢复个人 Logo（校验文件仍存在）
      const pa: number = p.getSync('personalAspect', 0) as number;
      if (pa > 0 && this.logoDir !== '') {
        const bOk: boolean = fileIo.accessSync(`${this.logoDir}/personal-b.png`);
        const wOk: boolean = fileIo.accessSync(`${this.logoDir}/personal-w.png`);
        if (bOk && wOk) {
          this.personalLogoAspect = pa;
          this.personalLogoColor = fileIo.accessSync(`${this.logoDir}/personal-img.png`);
          this.personalLogoMode = p.getSync('personalMode', 0) as number;
          this.rebuildPersonalEntry();
          Logger.info(`WMLOGO personal restored: aspect=${pa.toFixed(2)} color=${this.personalLogoColor} mode=${this.personalLogoMode}`);
        }
      }
    } catch (err) {
      Logger.error(`loadSettings failed: ${JSON.stringify(err)}`);
    }
    this.applySkin();
  }

  private rebuildPersonalEntry(): void {
    if (this.personalLogoAspect > 0 && this.logoDir !== '') {
      this.personalEntry = new BrandLogo('personal', '个人',
        `${this.logoDir}/personal-b.png`, `${this.logoDir}/personal-w.png`, this.personalLogoAspect,
        this.personalLogoColor ? `${this.logoDir}/personal-img.png` : '', this.personalLogoAspect);
    }
  }

  private personalLogoActive(): boolean {
    return this.logoOn && this.personalLogoMode === 1 && this.personalLogoAspect > 0;
  }

  private signLogoActive(): boolean {
    return this.personalLogoMode === 2 && this.personalLogoAspect > 0;
  }

  private personalPreviewFile(): string {
    if (this.logoDir === '') {
      return '';
    }
    return `${this.logoDir}/personal-${this.personalLogoColor ? 'img' : 'b'}.png`;
  }

  private async pickPersonalLogo(targetMode: number): Promise<void> {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const uris: string[] = await ImageTools.pickImageUris(1);
    if (uris.length === 0) {
      return;
    }
    this.toast('正在处理个人 Logo...');
    const res: PersonalLogoResult | undefined = await ImageTools.importPersonalLogo(context, uris[0]);
    if (res === undefined || res.aspect <= 0) {
      this.toast('Logo 处理失败，请换一张图片');
      return;
    }
    this.personalLogoAspect = res.aspect;
    this.personalLogoColor = res.hasColor;
    this.rebuildPersonalEntry();
    this.personalLogoMode = targetMode;
    this.toast('已应用个人 Logo');
    try {
      const p: preferences.Preferences = await preferences.getPreferences(context, 'app_settings');
      await p.put('personalAspect', res.aspect);
      await p.put('personalColor', res.hasColor);
      await p.put('personalMode', this.personalLogoMode);
      await p.flush();
    } catch (err) {
      Logger.error(`WMLOGO personal persist failed: ${JSON.stringify(err)}`);
    }
  }

  private async setPersonalLogoMode(v: number): Promise<void> {
    if (this.personalLogoAspect <= 0) {
      return;
    }
    this.personalLogoMode = v;
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      const p: preferences.Preferences = await preferences.getPreferences(context, 'app_settings');
      await p.put('personalMode', v);
      await p.flush();
    } catch (err) {
      Logger.error(`WMLOGO personal persist failed: ${JSON.stringify(err)}`);
    }
  }

  private scheduleBarLumaCheck(force: boolean, wide: boolean): void {
    const now: number = Date.now();
    if (!force && now - this.barLumaLast < 300) {
      return;
    }
    this.barLumaLast = now;
    this.checkBarLuma();
  }

  // 根据面板滚动方向隐藏/恢复悬浮导航条：上划（向内容深处滚动）隐藏，下滑（回滚）或回到顶部恢复
  private handlePanelScroll(): void {
    const y: number = this.panelScroller.currentOffset().yOffset;
    const dy: number = y - this.lastPanelScrollY;
    this.lastPanelScrollY = y;
    if (Math.abs(dy) < 2) {
      return;
    }
    if (dy > 0 && y > 12 && !this.navBarHidden) {
      this.setNavBarHidden(true);
    } else if ((dy < 0 || y <= 4) && this.navBarHidden) {
      this.setNavBarHidden(false);
    }
  }

  private setNavBarHidden(hidden: boolean): void {
    if (this.navBarHidden === hidden) {
      return;
    }
    this.getUIContext().animateTo({ duration: 220, curve: Curve.Friction }, () => {
      this.navBarHidden = hidden;
    });
    if (!hidden) {
      setTimeout(() => this.scheduleBarLumaCheck(true, false), 300);
    }
  }

  private async checkBarLuma(): Promise<void> {
    if (this.barLumaBusy) {
      return;
    }
    this.barLumaBusy = true;
    try {
      const pm: image.PixelMap =
        await this.getUIContext().getComponentSnapshot().get('panelScroll');
      const info: image.ImageInfo = await pm.getImageInfo();
      const w: number = info.size.width;
      const h: number = info.size.height;
      if (w > 0 && h > 0) {
        // 采样带对齐悬浮胶囊条：条底距面板底（物理屏底）14vp，条高约 56vp
        const dens: number = this.density > 0 ? this.density : 3.375;
        const barBottomPx: number = Math.round(14 * dens);
        const bandHpx: number = Math.round(56 * dens);
        let y0: number = h - barBottomPx - bandHpx;
        if (y0 < 0) {
          y0 = Math.max(0, h - Math.floor(h * 0.15));
        }
        const bandH: number = Math.min(bandHpx, h - y0);
        if (bandH >= 4) {
          const buf: ArrayBuffer = new ArrayBuffer(w * bandH * 4);
          const area: image.PositionArea = {
            pixels: buf,
            offset: 0,
            stride: w * 4,
            region: { x: 0, y: y0, size: { width: w, height: bandH } }
          };
          await pm.readPixels(area);
          const dv: DataView = new DataView(buf);
          let darkCnt: number = 0;
          let cnt: number = 0;
          for (let y: number = 0; y < bandH; y += 6) {
            const rowOff: number = y * w * 4;
            for (let x: number = 0; x < w; x += 4) {
              const off: number = rowOff + x * 4;
              if (off + 3 < buf.byteLength) {
                const b: number = dv.getUint8(off);
                const g: number = dv.getUint8(off + 1);
                const r: number = dv.getUint8(off + 2);
                const pl: number = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
                if (pl < 0.35) {
                  darkCnt++;
                }
                cnt++;
              }
            }
          }
          const frac: number = cnt > 0 ? darkCnt / cnt : 0;
          Logger.info(`bar frac=${frac.toFixed(3)} dark=${this.barOverDark}`);
          if (frac > 0.3) {
            this.barOverDark = true;
          } else if (frac < 0.15) {
            this.barOverDark = false;
          }
        }
      }
      pm.release();
    } catch (err) {
      Logger.warn(`bar luma check failed: ${JSON.stringify(err)}`);
    }
    this.barLumaBusy = false;
  }

  private portraitCapsuleW(): number {
    return Math.min(this.winWVp - 32, 328);
  }

  private navStripNarrow(): boolean {
    let w: number;
    if (this.hoverMode && this.hoverVertical) {
      w = this.hoverMenuLeft ? this.hoverCreaseLeftVp :
        this.winWVp - this.hoverCreaseLeftVp - this.hoverCreaseW;
    } else if (this.hoverMode) {
      w = this.winWVp;
    } else if (this.isWide) {
      w = this.paneRatio * this.winWVp;
    } else {
      w = this.portraitCapsuleW();
    }
    return w < 300;
  }

  private capsuleStripLeftMargin(): number {
    return (this.winWVp - this.portraitCapsuleW()) / 2;
  }

  // 宽屏悬浮条两侧留白：条宽约为所在面板宽的 69% 并居中；窄面板维持原 16vp 边距
  private wideBarSideMargin(): number {
    return this.stripWVp >= 330 ? this.stripWVp * 0.155 : 16;
  }

  // 悬浮条实际宽度：与 barFloatingStyle 胶囊同宽（容器宽-两侧留白），描边层复用保证边框贴住胶囊
  private floatBarWVp(wide: boolean): number {
    if (wide) {
      return Math.max(48, this.stripWVp - 2 * this.wideBarSideMargin());
    }
    return this.portraitCapsuleW();
  }

  // 面板底部渐变模糊：条顶边框以上 0 模糊，向下渐深，条底边框处达全模糊并保持到底（与胶囊轮廓对齐）
  private panelBlurOptions(): LinearGradientBlurOptions {
    const h: number = this.panelScrollHVp;
    if (h <= 100) {
      return {
        fractionStops: [[0, 0.85], [1, 1]],
        direction: GradientDirection.Bottom
      };
    }
    const fTop: number = Math.min(0.95, Math.max(0.5, (h - 70) / h));
    const fBot: number = Math.min(0.98, Math.max(0.55, (h - 14) / h));
    return {
      fractionStops: [[0, 0], [0, fTop], [1, fBot], [1, 1]],
      direction: GradientDirection.Bottom
    };
  }

  private lenToVp(v: Length): number {
    return typeof v === 'number' ? v : 0;
  }

  private updateTabClickXPct(i: number, wide: boolean): void {
    const n: number = this.tabItems.length;
    if (wide) {
      const paneW: number = this.paneRatio * this.winWVp;
      const barW: number = paneW >= 330 ? paneW * 0.69 : Math.min(paneW - 32, 328);
      const clickX: number = (paneW - barW) / 2 + ((i + 0.5) / n) * barW;
      this.tabClickXPct = `${((clickX / paneW) * 100).toFixed(1)}%`;
    } else {
      const barW: number = this.portraitCapsuleW();
      const stripLeft: number = (this.winWVp - barW) / 2;
      const clickX: number = stripLeft + ((i + 0.5) / n) * barW;
      this.tabClickXPct = `${((clickX / this.winWVp) * 100).toFixed(1)}%`;
    }
  }

  private applySkin(): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const mode: ConfigurationConstant.ColorMode = this.skinMode === 0 ?
      ConfigurationConstant.ColorMode.COLOR_MODE_DARK :
      (this.skinMode === 1 ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT :
      ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    try {
      context.getApplicationContext().setColorMode(mode);
    } catch (err) {
      Logger.error(`applySkin failed: ${JSON.stringify(err)}`);
    }
    this.applySystemBar();
    setTimeout(() => this.scheduleBarLumaCheck(true, false), 350);
  }

  // 深色背景下把系统导航条内容（指示条/按键）置白，浅色置黑
  private applySystemBar(): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    let dark: boolean = false;
    if (this.skinMode === 0) {
      dark = true;
    } else if (this.skinMode !== 1) {
      // 跟随系统（含未初始化 -1）：优先取 Ability 上报值，回退当前 context 配置
      const sys: number = this.sysColorMode === 0 || this.sysColorMode === 1 ?
        this.sysColorMode : context.config.colorMode as number;
      dark = sys === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    }
    window.getLastWindow(context).then((win: window.Window) => {
      win.setWindowSystemBarProperties({
        navigationBarContentColor: dark ? '#FFFFFF' : '#000000'
      }).catch((err: Object) => {
        Logger.error(`setSystemBar failed: ${JSON.stringify(err)}`);
      });
    }).catch((err: Object) => {
      Logger.error(`applySystemBar getLastWindow failed: ${JSON.stringify(err)}`);
    });
  }

  onSysColorChange(): void {
    this.applySystemBar();
  }

  private async onSkinPick(v: number): Promise<void> {
    if (v === this.skinMode) {
      return;
    }
    this.skinMode = v;
    this.applySkin();
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const p: preferences.Preferences = await preferences.getPreferences(context, 'app_settings');
      await p.put('skinMode', v);
      await p.flush();
    } catch (err) {
      Logger.error(`onSkinPick save failed: ${JSON.stringify(err)}`);
    }
  }

  private copyEmail(): void {
    const data: pasteboard.PasteData =
      pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, CONTACT_EMAIL);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      this.toast('邮箱已复制');
    }).catch((err: Object) => {
      Logger.error(`copyEmail failed: ${JSON.stringify(err)}`);
      this.toast('复制失败，请重试');
    });
  }

  private dirSize(dir: string): number {
    let total: number = 0;
    try {
      const names: string[] = fileIo.listFileSync(dir);
      for (let i = 0; i < names.length; i++) {
        const p: string = `${dir}/${names[i]}`;
        const st: fileIo.Stat = fileIo.statSync(p);
        if (st.isDirectory()) {
          total += this.dirSize(p);
        } else {
          total += st.size;
        }
      }
    } catch (err) {
      Logger.error(`dirSize failed: ${JSON.stringify(err)}`);
    }
    return total;
  }

  private formatSize(n: number): string {
    if (n < 1024) {
      return `${n}B`;
    }
    if (n < 1024 * 1024) {
      return `${Math.round(n / 1024)}KB`;
    }
    return `${(n / 1024 / 1024).toFixed(1)}MB`;
  }

  private async refreshCacheSize(): Promise<void> {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    let total: number = 0;
    try {
      total += this.dirSize(context.cacheDir);
      total += this.dirSize(context.tempDir);
    } catch (err) {
      Logger.error(`refreshCacheSize failed: ${JSON.stringify(err)}`);
    }
    this.cacheText = this.formatSize(total);
  }

  private clearDir(dir: string): void {
    try {
      const names: string[] = fileIo.listFileSync(dir);
      for (let i = 0; i < names.length; i++) {
        const p: string = `${dir}/${names[i]}`;
        try {
          const st: fileIo.Stat = fileIo.statSync(p);
          if (st.isDirectory()) {
            this.clearDir(p);
            fileIo.rmdirSync(p);
          } else {
            fileIo.unlinkSync(p);
          }
        } catch (err) {
          Logger.error(`clearDir entry failed: ${JSON.stringify(err)}`);
        }
      }
    } catch (err) {
      Logger.error(`clearDir failed: ${JSON.stringify(err)}`);
    }
  }

  private async cleanCache(): Promise<void> {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      this.clearDir(context.cacheDir);
      this.clearDir(context.tempDir);
    } catch (err) {
      Logger.error(`cleanCache failed: ${JSON.stringify(err)}`);
    }
    await this.refreshCacheSize();
    this.toast('缓存已清理');
  }

  private updateWide(): void {
    const wide: boolean = this.winWVp >= 600 && this.winWVp > this.winHVp;
    if (wide !== this.isWide) {
      this.getUIContext().animateTo({ duration: 320, curve: Curve.Friction }, () => {
        this.isWide = wide;
        this.syncPaneDerived();
      });
    } else {
      this.isWide = wide;
      this.syncPaneDerived();
    }
  }

  private syncPaneDerived(): void {
    const minR: number = 260 / this.winWVp;
    const maxR: number = Math.min(350, this.winWVp * 0.62) / this.winWVp;
    this.paneRatio = Math.min(maxR, Math.max(minR, this.paneRatio));
    const leftW: number = this.paneRatio * this.winWVp;
    this.presetSingleCol = this.isWide && leftW < 290;
  }

  private applyFoldStatus(s: display.FoldStatus, animate: boolean): void {
    const halfFold: boolean = s === display.FoldStatus.FOLD_STATUS_HALF_FOLDED ||
      s === display.FoldStatus.FOLD_STATUS_EXPANDED_WITH_SECOND_HALF_FOLDED ||
      s === display.FoldStatus.FOLD_STATUS_HALF_FOLDED_WITH_SECOND_EXPANDED ||
      s === display.FoldStatus.FOLD_STATUS_HALF_FOLDED_WITH_SECOND_HALF_FOLDED;
    if (!halfFold) {
      Logger.info(`foldStatus: ${s}, hover off`);
      this.setHoverState(false, false, false, 0, 0, 0, 0, animate);
      return;
    }
    try {
      const region: display.FoldCreaseRegion = display.getCurrentFoldCreaseRegion();
      const rot: number = display.getDefaultDisplaySync().rotation;
      let vertical: boolean = false;
      let menuLeft: boolean = false;
      let topVp: number = 0;
      let hVp: number = 0;
      let leftVp: number = 0;
      let wVp: number = 0;
      if (region.creaseRects.length > 0) {
        const r: display.Rect = region.creaseRects[0];
        if (rot === 1 || rot === 3) {
          vertical = true;
          wVp = r.height / this.density;
          if (rot === 1) {
            leftVp = this.winWVp - (r.top + r.height) / this.density;
            menuLeft = true;
          } else {
            leftVp = r.top / this.density;
            menuLeft = false;
          }
        } else {
          vertical = false;
          topVp = r.top / this.density;
          hVp = r.height / this.density;
        }
      }
      if (vertical && leftVp <= 0) {
        leftVp = this.winWVp / 2 - 8;
        wVp = 16;
      }
      if (!vertical && topVp <= 0) {
        topVp = this.winHVp / 2 - 8;
        hVp = 16;
      }
      Logger.info(`foldStatus: ${s}, rot: ${rot}, win: ${this.winWVp}x${this.winHVp}, ` +
        `vertical: ${vertical}, menuLeft: ${menuLeft}, top: ${topVp}, h: ${hVp}, left: ${leftVp}, w: ${wVp}`);
      this.setHoverState(true, vertical, menuLeft, topVp, hVp, leftVp, wVp, animate);
    } catch (err) {
      Logger.error(`hover layout calc failed: ${JSON.stringify(err)}`);
      this.setHoverState(false, false, false, 0, 0, 0, 0, animate);
    }
  }

  private scheduleHoverReverify(): void {
    if (this.hoverVerifyTimer >= 0) {
      clearTimeout(this.hoverVerifyTimer);
    }
    this.hoverVerifyTimer = setTimeout(() => {
      this.hoverVerifyTimer = -1;
      if (this.hoverMode) {
        Logger.info(`hover reverify`);
        this.applyFoldStatus(display.getFoldStatus(), true);
      }
    }, 500);
  }

  private setHoverState(on: boolean, vertical: boolean, menuLeft: boolean, topVp: number, hVp: number,
    leftVp: number, wVp: number, animate: boolean): void {
    const apply = () => {
      this.hoverMode = on;
      this.hoverVertical = vertical;
      this.hoverMenuLeft = menuLeft;
      this.hoverCreaseTopVp = topVp;
      this.hoverCreaseH = hVp;
      this.hoverCreaseLeftVp = leftVp;
      this.hoverCreaseW = wVp;
      if (!on) {
        this.hoverPickerInlineShow = false;
      }
    };
    if (animate) {
      this.getUIContext().animateTo({ duration: 320, curve: Curve.Friction }, apply);
    } else {
      apply();
    }
  }

  private camMakeText(): string {
    if ((this.showMask & BIT_MAKE) === 0 || this.exif.make === '') {
      return '';
    }
    if (this.makeReplacedByTitleLogo()) {
      return '';
    }
    return cleanMakeText(this.exif.make);
  }

  private camModelText(): string {
    let mk: string = this.exif.make;
    if (mk === '') {
      const key: string = this.brandPick !== '' ? this.brandPick : detectBrand(this.exif.make, this.exif.model);
      if (key === 'nikon') {
        mk = 'NIKON';
      } else if (key === 'sony') {
        mk = 'SONY';
      }
    }
    return cleanModelText(mk, this.exif.model);
  }

  private camLine(): string {
    const parts: string[] = [];
    const mk: string = this.camMakeText();
    if (mk !== '') {
      parts.push(mk);
    }
    const cm: string = this.camModelText();
    if ((this.showMask & BIT_MODEL) !== 0 && cm !== '') {
      parts.push(cm);
    }
    return parts.join(' ');
  }

  private makeReplacedByTitleLogo(): boolean {
    if (this.exif.make === '' || this.titleLogoFile() === '') {
      return false;
    }
    const shownKey: string = this.brandPick !== '' ? this.brandPick : detectBrand(this.exif.make, this.exif.model);
    return shownKey === detectBrand(this.exif.make, this.exif.model);
  }

  // 曝光参数四段：焦距/光圈/快门/ISO（胶囊标签模式各渲染一枚）
  private parSegs(): string[] {
    const segs: string[] = [];
    if ((this.showMask & BIT_FOCAL35) !== 0 && this.exif.focal35 !== '') {
      segs.push(`${this.exif.focal35}mm`);
    } else if ((this.showMask & BIT_FOCAL) !== 0 && this.exif.focalLength !== '') {
      segs.push(`${this.exif.focalLength}mm`);
    }
    if ((this.showMask & BIT_APERTURE) !== 0 && this.exif.fNumber !== '') {
      segs.push(`f/${this.exif.fNumber}`);
    }
    if ((this.showMask & BIT_SHUTTER) !== 0 && this.exif.exposureTime !== '') {
      segs.push(`${this.exif.exposureTime}s`);
    }
    if ((this.showMask & BIT_ISO) !== 0 && this.exif.iso !== '') {
      segs.push(`ISO${this.exif.iso}`);
    }
    return segs;
  }

  private parLine(): string {
    return this.parSegs().join(' ');
  }

  private lensLine(): string {
    return (this.showMask & BIT_LENS) !== 0 ? this.exif.lensModel.trim() : '';
  }

  private signSuffix(): string {
    if ((this.showMask & BIT_SIGN) === 0) {
      return '';
    }
    const s: string = this.exif.signature.trim();
    return s === '' ? '' : `©${s}`;
  }

  private datLine(): string {
    const segs: string[] = [];
    const dateOn: boolean = (this.showMask & BIT_DATE) !== 0 && this.exif.dateTime !== '';
    const sign: string = this.signSuffix();
    if (dateOn && sign !== '') {
      segs.push(`${this.exif.dateTime} ${sign}`);
    } else if (dateOn) {
      segs.push(this.exif.dateTime);
    } else if (sign !== '') {
      segs.push(sign);
    }
    if ((this.showMask & BIT_PROGRAM) !== 0 && this.exif.program !== '') {
      segs.push(this.exif.program);
    }
    return segs.join(' · ');
  }

  private signLine(): string {
    return '';
  }

  private datDateStr(): string {
    return (this.showMask & BIT_DATE) !== 0 && this.exif.dateTime !== '' ? this.exif.dateTime : '';
  }

  // 署名位置的个人 Logo（模式 2）：返回文件路径，空串表示不启用
  private signSlotLogo(): string {
    if (!this.signLogoActive() || (this.showMask & BIT_SIGN) === 0 || this.logoDir === '') {
      return '';
    }
    return `${this.logoDir}/personal-${this.isDarkColor(this.textColor) ? 'b' : 'w'}.png`;
  }

  private signSlotText(): string {
    if (this.signSlotLogo() !== '') {
      return '';
    }
    return this.signSuffix();
  }

  private datProgramStr(): string {
    return (this.showMask & BIT_PROGRAM) !== 0 && this.exif.program !== '' ? this.exif.program : '';
  }

  private datHasContent(): boolean {
    if (this.barLayout === 1) {
      return this.datDateStr() !== '' || this.datProgramStr() !== '';
    }
    return this.datDateStr() !== '' || this.signSlotText() !== '' || this.signSlotLogo() !== ''
      || this.datProgramStr() !== '';
  }

  // 分栏日期行内容（仅日期与程序，署名独立成行）
  private splitDatLine(): string {
    const segs: string[] = [];
    if ((this.showMask & BIT_DATE) !== 0 && this.exif.dateTime !== '') {
      segs.push(this.exif.dateTime);
    }
    if ((this.showMask & BIT_PROGRAM) !== 0 && this.exif.program !== '') {
      segs.push(this.exif.program);
    }
    return segs.join(' · ');
  }

  // 分栏署名行是否存在（Logo 或 ©文字）
  private signRowOn(): boolean {
    return this.signSlotLogo() !== '' || this.signSlotText() !== '';
  }

  // 台历：大字日号（如 16）
  private calDayStr(): string {
    if ((this.showMask & BIT_DATE) === 0) {
      return '';
    }
    const s: string = this.exif.dateTime;
    if (s.length < 10 || s.charAt(4) !== '.' || s.charAt(7) !== '.') {
      return '';
    }
    return s.substring(8, 10);
  }

  // 台历：年月（如 2025.03）
  private calYearMonth(): string {
    if ((this.showMask & BIT_DATE) === 0) {
      return '';
    }
    const s: string = this.exif.dateTime;
    if (s.length < 7 || s.charAt(4) !== '.') {
      return '';
    }
    return s.substring(0, 7);
  }

  // 台历：日号右侧信息列行盒总高（相对 f2）
  private calColH(): number {
    let h: number = 0;
    let lineN: number = 0;
    if (this.calYearMonth() !== '') {
      h += DATE_SPLIT_FACTOR * CAL_BOX_LH;
      lineN++;
    }
    if (this.camLine() !== '') {
      h += CAL_BOX_LH;
      lineN++;
    }
    if (this.parLine() !== '') {
      h += DATE_SPLIT_FACTOR * CAL_BOX_LH;
      lineN++;
    }
    if (lineN > 1) {
      h += (lineN - 1) * 0.45;
    }
    return h;
  }

  // 台历：三行信息列上移量——行盒顶与大字日号行盒顶对齐
  private calLiftMargin(): number {
    if (this.calDayStr() === '') {
      return 0;
    }
    const diff: number = CAL_DAY_FACTOR * CAL_DAY_LH - this.calColH();
    return diff > 0 ? diff * this.canvasC.f2 : 0;
  }

  // 会展：白框内容高（相对 f2）——署名/相机型号/曝光参数·拍摄时间行盒与行距
  private expoContent(): number {
    let h: number = 0;
    let n: number = 0;
    if (this.expoHeadHas()) {
      h += EXPO_HEAD_LH;
      n++;
    }
    if (this.camLine() !== '') {
      h += EXPO_SUB_LH;
      n++;
    }
    if (this.expoParDate() !== '') {
      h += EXPO_SUB_LH;
      n++;
    }
    if (n > 1) {
      h += (n - 1) * EXPO_GAP;
    }
    return h;
  }

  // 分栏署名行高度（供竖线与排版计算）
  private signRowH(): number {
    if (this.signSlotLogo() !== '') {
      return this.signLogoH();
    }
    if (this.signSlotText() !== '') {
      return this.canvasC.f2 * DATE_SPLIT_FACTOR * BAR_LH;
    }
    return 0;
  }

  private datProgramNeedsSeparator(): boolean {
    if (this.barLayout === 1) {
      return this.datDateStr() !== '';
    }
    return this.datDateStr() !== '' || this.signSlotLogo() !== '' || this.signSlotText() !== '';
  }

  private signLogoH(): number {
    const base: number = this.canvasC.f2 * (this.barLayout === 1 ? DATE_SPLIT_FACTOR : 1);
    let h: number = base * 1.12 * this.logoBoost(this.personalLogoAspect);
    const maxW: number = this.canvasC.outW * 0.35;
    if (h * this.personalLogoAspect > maxW) {
      h = maxW / this.personalLogoAspect;
    }
    return h;
  }

  private signLogoW(): number {
    return this.signLogoH() * this.personalLogoAspect;
  }

  private currentBrand(): BrandLogo | undefined {
    if (!this.logoOn) {
      return undefined;
    }
    if (this.personalLogoMode === 1 && this.personalLogoAspect > 0) {
      return this.personalEntry;
    }
    const key: string = this.brandPick !== '' ? this.brandPick : detectBrand(this.exif.make, this.exif.model);
    if (key === '') {
      return undefined;
    }
    return brandByKey(key);
  }

  private titleFont(): number {
    if (this.barLayout === 1) {
      const factor: number = this.lensLine() !== '' || this.signLine() !== ''
        ? TITLE_SPLIT_LENS_FACTOR : TITLE_SPLIT_FACTOR;
      return this.canvasC.f1 * factor;
    }
    return this.canvasC.f1 * TITLE_FACTOR;
  }

  private logoFile(): string {
    const b: BrandLogo | undefined = this.currentBrand();
    if (b === undefined) {
      return '';
    }
    return this.isDarkColor(this.textColor) ? b.blackFile : b.whiteFile;
  }

  private titleLogoFile(): string {
    const b: BrandLogo | undefined = this.currentBrand();
    if (b === undefined || b.key === 'huawei') {
      return '';
    }
    if (this.barLayout === 1 && this.directPos === 0) {
      return '';
    }
    // 台历布局不渲染标题 Logo，品牌名保留在型号行文字中
    if (this.barLayout === 2) {
      return '';
    }
    // 会展布局不渲染标题 Logo，相机型号行保留完整品牌名
    if (this.barLayout === 3) {
      return '';
    }
    return this.logoFile();
  }

  private logoBoost(aspect: number): number {
    return aspect < 2.2 ? Math.min(1.47, Math.sqrt(2.2 / aspect)) : 1;
  }

  private logoH(): number {
    const b: BrandLogo | undefined = this.currentBrand();
    if (b === undefined || b.aspect <= 0) {
      return 0;
    }
    let h: number = this.titleFont() * 0.85 * this.logoBoost(b.aspect);
    const maxW: number = this.canvasC.outW * 0.5;
    if (h * b.aspect > maxW) {
      h = maxW / b.aspect;
    }
    return h;
  }

  private logoW(): number {
    const b: BrandLogo | undefined = this.currentBrand();
    if (b === undefined) {
      return 0;
    }
    return this.logoH() * b.aspect;
  }

  private imgLogoFile(): string {
    const b: BrandLogo | undefined = this.currentBrand();
    if (b === undefined) {
      return '';
    }
    if (b.imageFile !== '') {
      return b.imageFile;
    }
    return this.logoFile();
  }

  private imgAspect(): number {
    const b: BrandLogo | undefined = this.currentBrand();
    if (b === undefined) {
      return 0;
    }
    return b.imageAspect > 0 ? b.imageAspect : b.aspect;
  }

  private imgLogoH(): number {
    const b: BrandLogo | undefined = this.currentBrand();
    const a: number = this.imgAspect();
    if (b === undefined || a <= 0) {
      return 0;
    }
    let h: number = this.canvasC.f2 * BAR_LH * 0.95 * this.logoBoost(a);
    const maxW: number = this.canvasC.outW * 0.35;
    if (h * a > maxW) {
      h = maxW / a;
    }
    return h;
  }

  private imgLogoW(): number {
    const b: BrandLogo | undefined = this.currentBrand();
    if (b === undefined) {
      return 0;
    }
    return this.imgLogoH() * this.imgAspect();
  }

  private dividerH(): number {
    let h: number = 0;
    if (this.parLine() !== '') {
      h += this.canvasC.f2 * BAR_LH;
    }
    if (this.splitDatLine() !== '') {
      h += this.canvasC.f2 * 0.45 + this.canvasC.f2 * DATE_SPLIT_FACTOR * BAR_LH;
    }
    if (this.signRowOn()) {
      h += this.canvasC.f2 * 0.45 + this.signRowH();
    }
    return h;
  }

  private resetZoom(): void {
    this.zoomScale = 1;
    this.zoomX = 0;
    this.zoomY = 0;
  }

  private clampZoomX(v: number, s: number): number {
    const maxX: number =
      (this.canvasC.outW * (s - 1)) / 2 + Math.max(this.previewAreaW - this.canvasC.outW, 0) / 2;
    return Math.min(Math.max(v, -maxX), maxX);
  }

  private clampZoomY(v: number, s: number): number {
    const maxY: number =
      (this.canvasC.outH * (s - 1)) / 2 + Math.max(this.previewAreaH - this.canvasC.outH, 0) / 2;
    return Math.min(Math.max(v, -maxY), maxY);
  }

  private layoutPx(): FrameLayout {
    const camOn: boolean = this.camLine() !== '';
    let body: number = 0;
    let leftBody: number = 0;
    let rightBody: number = 0;
    if (this.parLine() !== '') {
      body++;
      rightBody++;
    }
    if (this.lensLine() !== '') {
      body++;
      leftBody++;
    }
    if (this.barLayout === 1) {
      if (this.splitDatLine() !== '') {
        body++;
        rightBody++;
      }
      if (this.signRowOn()) {
        body++;
        rightBody++;
      }
    } else {
      if (this.datLine() !== '') {
        body++;
        rightBody++;
      }
    }
    if (this.signLine() !== '') {
      body++;
      leftBody++;
    }
    // 台历内容高（相对 f2）：三行信息行盒与 gaps、大字日号取较高者；仅署名时为单行行盒
    let calContent: number = 0;
    if (this.barLayout === 2) {
      const colH: number = this.calColH();
      const dayH: number = this.calDayStr() !== '' ? CAL_DAY_FACTOR * CAL_DAY_LH : 0;
      if (colH === 0 && dayH === 0) {
        calContent = this.signRowOn() ? CAL_BOX_LH : 0;
      } else {
        calContent = Math.max(colH, dayH);
      }
    } else if (this.barLayout === 3) {
      // 会展内容高：白框左下三行行盒与行距（减去台历呼吸留白，条高=文字实际高度）
      const ec: number = this.expoContent();
      calContent = ec > 0 ? ec - CAL_MARGIN * 2 : 0;
    }
    return computeFrameLayout(this.imgW, this.imgH, this.frameMarginPct, this.sizeScalePct,
      this.frameMode, camOn, body, this.barLayout === 1, leftBody, rightBody,
      this.layoutKind, this.keylineOn, calContent);
  }

  private previewScale(): number {
    if (this.pixelMap === undefined) {
      return 0;
    }
    const lay: FrameLayout = this.layoutPx();
    if (lay.outW <= 0 || lay.outH <= 0) {
      return 0;
    }
    const availW: number = this.previewAreaW > 0 ? this.previewAreaW : this.screenWVp - 32;
    const availH: number = this.previewAreaH > 0 ? this.previewAreaH : this.screenHVp * 0.40;
    return Math.min(availW / lay.outW, availH / lay.outH) * 0.98;
  }

  private previewLayout(): CanvasLayout {
    return scaleLayout(this.layoutPx(), this.previewScale());
  }

  private refreshLayouts(): void {
    this.canvasC = this.previewLayout();
  }

  private barTextAlign(): TextAlign {
    if (this.alignMode === 2) {
      return TextAlign.End;
    }
    if (this.alignMode === 1) {
      return TextAlign.Center;
    }
    return TextAlign.Start;
  }

  private hasBar(): boolean {
    return this.camLine() !== '' || this.parLine() !== '' || this.lensLine() !== '' ||
      this.datLine() !== '' || this.signLine() !== '' || this.signRowOn();
  }

  private desiredLongEdge(): number {
    return 4096;
  }

  private async ensureDecoded(): Promise<void> {
    const want: number = this.desiredLongEdge();
    if (this.sourceUri === '' || (this.decodedLongEdge === want && this.decodedRatio === this.exportRatio &&
      this.pixelMap !== undefined)) {
      return;
    }
    const pm: image.PixelMap | undefined = await ImageTools.decodeScaled(this.sourceUri, want, this.exportRatio);
    if (pm === undefined) {
      this.toast('图片加载失败，请重新选择');
      return;
    }
    const old: image.PixelMap | undefined = this.pixelMap;
    this.pixelMap = pm;
    const info: image.ImageInfo = await pm.getImageInfo();
    this.imgW = info.size.width;
    this.imgH = info.size.height;
    this.decodedLongEdge = want;
    this.decodedRatio = this.exportRatio;
    this.refreshLayouts();
    if (old !== undefined) {
      old.release();
    }
  }

  private async pickImage(): Promise<void> {
    this.resetZoom();
    if (this.hoverMode) {
      this.hoverPickUris = [];
      this.hoverPickCount = 0;
      if (this.hoverVertical) {
        this.hoverPickerInlineShow = true;
      } else {
        this.hoverPickerShow = true;
      }
      return;
    }
    const uris: string[] = await ImageTools.pickImageUris(20);
    await this.applyPickedUris(uris);
  }

  private async applyPickedUris(uris: string[]): Promise<void> {
    if (uris.length === 0) {
      return;
    }
    const firstPick: boolean = this.photoItems.length === 0;
    const items: PhotoItem[] = [];
    for (let i = 0; i < uris.length; i++) {
      items.push(new PhotoItem(uris[i]));
    }
    this.photoItems = items;
    this.currentIdx = 0;
    if (firstPick) {
      for (let i = 0; i < this.presets.length; i++) {
        if (this.presets[i].name === '标准白框') {
          this.applyPreset(this.presets[i]);
          break;
        }
      }
    }
    await this.loadCurrentPhoto();
  }

  private async confirmHoverPick(): Promise<void> {
    this.hoverPickerShow = false;
    this.hoverPickerInlineShow = false;
    await this.applyPickedUris(this.hoverPickUris);
  }

  private async loadCurrentPhoto(): Promise<boolean> {
    const item: PhotoItem | undefined = this.photoItems[this.currentIdx];
    if (item === undefined) {
      return false;
    }
    this.sourceUri = item.uri;
    this.decodedLongEdge = -1;
    this.decodedRatio = -1;
    if (!item.exifLoaded) {
      const info: ExifInfo | undefined = await ImageTools.readExif(item.uri);
      const e: ExifInfo = new ExifInfo();
      if (info !== undefined) {
        e.make = cleanMakeText(info.make);
        e.model = cleanModelText(info.make, info.model);
        e.lensMake = info.lensMake;
        e.lensModel = info.lensModel;
        e.exposureTime = info.exposureTime;
        e.fNumber = info.fNumber;
        e.iso = info.iso;
        e.focalLength = info.focalLength;
        e.focal35 = info.focal35;
        e.program = info.program;
        e.dateTime = info.dateTime;
      }
      item.exif = e;
      item.exifLoaded = true;
      // 原生快照：仅解析器输出（清洗后的 Make/Model/LensModel），手动编辑不会触碰它
      item.nativeExif = e.clone();
      item.nativeLoaded = true;
    }
    fillExifGaps(item.exif, this.manualDefaults);
    this.exif = item.exif.clone();
    await this.ensureDecoded();
    if (this.pixelMap === undefined || this.decodedLongEdge !== this.desiredLongEdge() ||
      this.decodedRatio !== this.exportRatio) {
      return false;
    }
    this.refreshBlurredBg();
    return true;
  }

  private async switchPhoto(idx: number): Promise<void> {
    if (this.batchRunning || idx === this.currentIdx || idx < 0 || idx >= this.photoItems.length) {
      return;
    }
    this.currentIdx = idx;
    this.resetZoom();
    await this.loadCurrentPhoto();
  }

  private async refreshBlurredBg(): Promise<void> {
    if (this.sourceUri === '' || this.frameMode !== 2) {
      return;
    }
    const pm: image.PixelMap | undefined = await ImageTools.makeBlurredBg(this.sourceUri, this.blurPct);
    if (pm === undefined) {
      return;
    }
    const old: image.PixelMap | undefined = this.bgMap;
    this.bgMap = pm;
    if (old !== undefined) {
      old.release();
    }
  }

  private scheduleBgRefresh(): void {
    setTimeout(() => {
      this.refreshBlurredBg();
    }, 150);
  }

  private updateExif(field: number, v: string): void {
    const c: ExifInfo = this.exif.clone();
    if (field === 0) {
      const t: string = v.trim();
      c.make = t === '' ? '' : t.charAt(0).toUpperCase() + t.substring(1).toLowerCase();
      this.manualDefaults.make = c.make;
    } else if (field === 1) {
      c.model = v.trim();
      this.manualDefaults.model = c.model;
    } else if (field === 2) {
      c.lensModel = v.trim();
      this.manualDefaults.lensModel = c.lensModel;
    } else if (field === 3) {
      c.focalLength = v.trim();
      this.manualDefaults.focalLength = c.focalLength;
    } else if (field === 4) {
      c.focal35 = v.trim();
      this.manualDefaults.focal35 = c.focal35;
    } else if (field === 5) {
      c.fNumber = v.trim();
      this.manualDefaults.fNumber = c.fNumber;
    } else if (field === 6) {
      c.exposureTime = v.trim();
      this.manualDefaults.exposureTime = c.exposureTime;
    } else if (field === 7) {
      c.iso = v.trim();
      this.manualDefaults.iso = c.iso;
    } else if (field === 8) {
      c.program = v.trim();
      this.manualDefaults.program = c.program;
    } else if (field === 9) {
      c.dateTime = v.trim();
      this.manualDefaults.dateTime = c.dateTime;
    } else if (field === 10) {
      c.signature = v;
      this.manualDefaults.signature = c.signature;
    }
    this.exif = c;
    const item: PhotoItem | undefined = this.photoItems[this.currentIdx];
    if (item !== undefined) {
      item.exif = c.clone();
    }
    this.refreshLayouts();
  }

  private toggleFieldBit(bit: number, on: boolean): void {
    this.showMask = on ? (this.showMask | bit) : (this.showMask & ~bit);
    this.refreshLayouts();
  }

  private expoGroupOn(): boolean {
    return (this.showMask & BIT_FOCAL) !== 0;
  }

  private toggleExpoGroup(on: boolean): void {
    const m: number = BIT_FOCAL | BIT_FOCAL35 | BIT_APERTURE | BIT_SHUTTER | BIT_ISO;
    this.showMask = on ? (this.showMask | m) : (this.showMask & ~m);
    this.refreshLayouts();
  }

  private applyPreset(p: StylePreset): void {
    this.activePreset = p.id;
    this.frameMode = p.frameMode;
    this.layoutKind = p.layoutKind;
    this.directPos = p.directPos;
    this.frameColor = p.frameColor;
    this.textColor = p.textColor;
    this.keylineOn = p.keylineOn;
    this.keylineColor = p.keylineColor;
    this.barLayout = p.barLayout;
    this.parTags = p.parTags;
    this.alignMode = p.alignMode;
    this.frameMarginPct = p.frameMarginPct;
    this.sizeScalePct = p.sizeScalePct;
    this.showMask = p.showMask;
    this.shadowMode = p.shadowMode;
    this.filmStyle = p.filmStyle;
    if (p.frameMode === 2) {
      this.blurPct = p.blurPct;
      this.refreshBlurredBg();
    }
    this.refreshLayouts();
  }

  // ===== 个人样式与收藏 =====

  // 展示序列：收藏置顶（个人样式按保存时间倒序，随后内置样式原顺序）
  private rebuildStyleList(): void {
    const favs: StylePreset[] = [];
    const rest: StylePreset[] = [];
    const customs: StylePreset[] = this.savedStyles.slice();
    customs.sort((a: StylePreset, b: StylePreset) => b.createdAt - a.createdAt);
    for (const p of customs) {
      if (p.favorite) {
        favs.push(p);
      } else {
        rest.push(p);
      }
    }
    for (const p of this.presets) {
      if (p.favorite) {
        favs.push(p);
      } else {
        rest.push(p);
      }
    }
    this.styleList = favs.concat(rest);
    const ids: string[] = [];
    for (const p of favs) {
      ids.push(p.id);
    }
    this.favIds = ids;
  }

  private async persistSavedStyles(): Promise<void> {
    try {
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      const p: preferences.Preferences = await preferences.getPreferences(context, 'app_settings');
      await p.put('savedStyles', savedStylesToRaw(this.savedStyles));
      await p.flush();
    } catch (err) {
      Logger.error(`WMSTYLE persist saved styles failed: ${JSON.stringify(err)}`);
    }
  }

  private async persistBuiltinFavs(): Promise<void> {
    try {
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      const p: preferences.Preferences = await preferences.getPreferences(context, 'app_settings');
      await p.put('builtinFavs', builtinFavsToRaw(this.presets));
      await p.flush();
    } catch (err) {
      Logger.error(`WMSTYLE persist builtin favs failed: ${JSON.stringify(err)}`);
    }
  }

  private styleDateStr(ts: number): string {
    const d: Date = new Date(ts);
    const m: number = d.getMonth() + 1;
    const day: number = d.getDate();
    const mm: string = m < 10 ? `0${m}` : `${m}`;
    const dd: string = day < 10 ? `0${day}` : `${day}`;
    return `${d.getFullYear()}-${mm}-${dd}`;
  }

  private nextStyleName(): string {
    let n: number = this.savedStyles.length + 1;
    while (n < 1000) {
      const name: string = `我的样式 ${n}`;
      let used: boolean = false;
      for (const p of this.savedStyles) {
        if (p.name === name) {
          used = true;
          break;
        }
      }
      if (!used) {
        return name;
      }
      n++;
    }
    return `我的样式 ${Date.now()}`;
  }

  // 把当前样式（含预览缩略图）保存为个人样式
  private async saveCurrentStyle(): Promise<void> {
    if (this.pixelMap === undefined) {
      this.toast('请先选择一张图片，再保存样式');
      return;
    }
    if (this.styleDir === '') {
      this.toast('样式保存失败，请重试');
      return;
    }
    await this.ensureDecoded();
    const lay: FrameLayout = this.layoutPx();
    if (lay.outW <= 0 || lay.outH <= 0) {
      this.toast('样式保存失败，请重试');
      return;
    }
    this.canvasC = scaleLayout(lay, 1 / this.density);
    let pm: image.PixelMap | undefined = undefined;
    try {
      pm = await this.getUIContext().getComponentSnapshot().createFromBuilder(
        (): void => {
          this.watermarkCanvas();
        },
        300,
        true,
        { scale: Math.min(0.5, 520 / lay.outW), waitUntilRenderFinished: true }
      );
    } catch (err) {
      Logger.error(`WMSTYLE snapshot failed: ${JSON.stringify(err)}`);
      pm = undefined;
    }
    this.refreshLayouts();
    if (pm === undefined) {
      this.toast('样式保存失败，请重试');
      return;
    }
    const id: string = `cs-${Date.now()}`;
    const thumbPath: string = `${this.styleDir}/style-${id}.jpg`;
    let aspect: number = 1.4;
    try {
      const info: image.ImageInfo = await pm.getImageInfo();
      if (info.size.width > 0 && info.size.height > 0) {
        aspect = info.size.width / info.size.height;
      }
    } catch (err) {
      Logger.error(`WMSTYLE thumb info failed: ${JSON.stringify(err)}`);
    }
    const saved: boolean = await ImageTools.saveJpegFile(pm, thumbPath, 82);
    pm.release();
    if (!saved) {
      this.toast('样式保存失败，请重试');
      return;
    }
    const p: StylePreset = new StylePreset();
    p.id = id;
    p.name = this.nextStyleName();
    p.custom = true;
    p.createdAt = Date.now();
    p.frameMode = this.frameMode;
    p.layoutKind = this.layoutKind;
    p.directPos = this.directPos;
    p.frameColor = this.frameColor;
    p.textColor = this.textColor;
    p.keylineOn = this.keylineOn;
    p.keylineColor = this.keylineColor;
    p.barLayout = this.barLayout;
    p.alignMode = this.alignMode;
    p.frameMarginPct = this.frameMarginPct;
    p.sizeScalePct = this.sizeScalePct;
    p.blurPct = this.blurPct;
    p.showMask = this.showMask;
    p.shadowMode = this.shadowMode;
    p.filmStyle = this.filmStyle;
    p.parTags = this.parTags;
    p.refFile = thumbPath;
    p.refAspect = aspect;
    p.desc = `${this.styleDateStr(p.createdAt)} 保存`;
    this.savedStyles.push(p);
    await this.persistSavedStyles();
    this.rebuildStyleList();
    this.activePreset = p.id;
    this.toast(`已保存「${p.name}」，长按卡片可收藏`);
  }

  private confirmDeleteStyle(p: StylePreset): void {
    this.getUIContext().showAlertDialog({
      title: '删除样式',
      message: `确定删除「${p.name}」吗？`,
      alignment: DialogAlignment.Bottom,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        action: () => {
          this.deleteStyle(p);
        }
      }
    });
  }

  private async deleteStyle(p: StylePreset): Promise<void> {
    const idx: number = this.savedStyles.indexOf(p);
    if (idx < 0) {
      return;
    }
    this.savedStyles.splice(idx, 1);
    try {
      if (fileIo.accessSync(p.refFile)) {
        fileIo.unlinkSync(p.refFile);
      }
    } catch (err) {
      Logger.error(`WMSTYLE thumb unlink failed: ${JSON.stringify(err)}`);
    }
    if (this.activePreset === p.id) {
      this.activePreset = '';
    }
    await this.persistSavedStyles();
    this.rebuildStyleList();
    this.toast('样式已删除');
  }

  // 长按收藏 / 取消收藏：红心由底部慢慢填满（取消时反向退去），完成后置顶排序
  private onCardLongPress(p: StylePreset): void {
    if (this.heartAnimId !== '') {
      return;
    }
    this.lastLongPressAt = Date.now();
    const fav: boolean = !p.favorite;
    this.heartAnimId = p.id;
    if (fav) {
      this.heartFill = 0;
      this.heartPop = 0.4;
      this.heartAlpha = 1;
      this.getUIContext().animateTo({ duration: 500, curve: Curve.EaseInOut }, () => {
        this.heartFill = 1;
        this.heartPop = 1.18;
      });
      setTimeout(() => {
        this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseOut }, () => {
          this.heartPop = 1;
        });
      }, 510);
      setTimeout(() => {
        this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
          this.heartAlpha = 0;
        });
      }, 690);
      setTimeout(() => {
        this.commitFavorite(p, true);
      }, 900);
    } else {
      this.heartFill = 1;
      this.heartPop = 1;
      this.heartAlpha = 1;
      this.getUIContext().animateTo({ duration: 380, curve: Curve.EaseInOut }, () => {
        this.heartFill = 0;
      });
      setTimeout(() => {
        this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
          this.heartAlpha = 0;
        });
      }, 400);
      setTimeout(() => {
        this.commitFavorite(p, false);
      }, 600);
    }
  }

  private commitFavorite(p: StylePreset, fav: boolean): void {
    p.favorite = fav;
    this.heartAnimId = '';
    this.heartFill = 0;
    this.heartPop = 1;
    this.heartAlpha = 0;
    if (p.custom) {
      this.persistSavedStyles();
    } else {
      this.persistBuiltinFavs();
    }
    this.rebuildStyleList();
    this.toast(fav ? '已收藏，将置顶显示' : '已取消收藏');
  }

  private isDarkColor(c: string): boolean {
    const s: string = c.replace('#', '');
    if (s.length !== 6) {
      return false;
    }
    const r: number = parseInt(s.substring(0, 2), 16);
    const g: number = parseInt(s.substring(2, 4), 16);
    const b: number = parseInt(s.substring(4, 6), 16);
    return 0.299 * r + 0.587 * g + 0.114 * b < 140;
  }

  private adjustTextToFrame(): void {
    const darkFrame: boolean = this.isDarkColor(this.frameColor);
    if (darkFrame && this.textColor === '#222222') {
      this.textColor = '#FFFFFF';
    }
    if (!darkFrame && this.textColor === '#FFFFFF') {
      this.textColor = '#222222';
    }
  }

  private onFrameModePick(v: number): void {
    this.frameMode = v;
    this.filmStyle = false;
    if (v === 1) {
      this.adjustTextToFrame();
    } else if (this.textColor === '#222222') {
      this.textColor = '#FFFFFF';
    }
    if (v === 2 && this.bgMap === undefined) {
      this.refreshBlurredBg();
    }
    this.refreshLayouts();
  }

  private onFrameColorPick(c: string): void {
    this.frameColor = c;
    this.adjustTextToFrame();
  }

  private async onExportRatioPick(v: number): Promise<void> {
    this.exportRatio = v;
    if (this.pixelMap !== undefined) {
      await this.ensureDecoded();
      this.scheduleBarLumaCheck(true, false);
    }
  }

  private resetStyle(): void {
    this.showMask = DEFAULT_MASK;
    this.alignMode = 1;
    this.textColor = '#222222';
    this.sizeScalePct = 100;
    this.frameMode = 1;
    this.layoutKind = 0;
    this.directPos = 0;
    this.keylineOn = false;
    this.keylineColor = '#222222';
    this.barLayout = 0;
    this.parTags = false;
    this.blurPct = 12;
    this.filmStyle = false;
    this.frameMarginPct = 6;
    this.frameColor = '#FFFFFF';
    this.exportPng = false;
    this.activePreset = '';
    this.logoOn = true;
    this.brandPick = '';
    this.refreshLayouts();
    const old: image.PixelMap | undefined = this.bgMap;
    this.bgMap = undefined;
    if (old !== undefined) {
      old.release();
    }
  }

  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000, bottom: '35%' });
  }

  private exifHint(): string {
    if (this.pixelMap === undefined) {
      return '选择图片后将自动读取拍摄参数（EXIF）';
    }
    if (!this.exif.hasAny()) {
      return '未读取到 EXIF 参数，可手动填写下方内容';
    }
    return '参数已从照片读取，勾选控制该项是否加入水印';
  }

  private outputInfoText(): string {
    if (this.pixelMap === undefined) {
      return '请先选择图片';
    }
    const lay: FrameLayout = this.layoutPx();
    return `输出尺寸 ${Math.round(lay.outW)} × ${Math.round(lay.outH)} px`;
  }

  private sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: (v: void) => void) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }

  private async exportCurrent(): Promise<boolean> {
    await this.ensureDecoded();
    if (this.pixelMap === undefined) {
      return false;
    }
    const lay: FrameLayout = this.layoutPx();
    this.canvasC = scaleLayout(lay, 1 / this.density);
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    let pm: image.PixelMap | undefined = undefined;
    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        pm = await this.getUIContext().getComponentSnapshot().createFromBuilder(
          (): void => {
            this.watermarkCanvas();
          },
          300,
          true,
          { scale: 1, waitUntilRenderFinished: true }
        );
        break;
      } catch (err) {
        Logger.error(`exportCurrent snapshot attempt ${attempt} failed: ${JSON.stringify(err)}`);
        pm = undefined;
        await this.sleep(200 + attempt * 300);
      }
    }
    if (pm === undefined) {
      return false;
    }
    let ok: boolean = false;
    let hdrParts: HdrJpegParts | undefined = undefined;
    if (!this.exportPng) {
      hdrParts = await ImageTools.readHdrJpegParts(this.sourceUri);
    }
    // 导出 JPEG 继承原片拍摄参数：提取原片 EXIF APP1 段并按输出尺寸修正方向与像素尺寸
    let exifSeg: Uint8Array | undefined = undefined;
    if (!this.exportPng) {
      exifSeg = ImageTools.extractExifSegment(this.sourceUri);
      if (exifSeg !== undefined) {
        const pmInfo: image.ImageInfo = await pm.getImageInfo();
        ImageTools.patchExifSegment(exifSeg, pmInfo.size.width, pmInfo.size.height);
      } else {
        Logger.info('WMEXIF inherit: source has no EXIF, skip');
      }
    }
    try {
      if (hdrParts !== undefined) {
        if (lay.mode !== 0) {
          // 带框版式：增益图需按照片在输出中的矩形重合成，白框/参数条区域零增益
          const pmInfo: image.ImageInfo = await pm.getImageInfo();
          const kx: number = pmInfo.size.width / lay.outW;
          const ky: number = pmInfo.size.height / lay.outH;
          const done: boolean = await ImageTools.recomposeGainmap(hdrParts, pmInfo.size.width, pmInfo.size.height,
            lay.pad * kx, lay.pad * ky, lay.photoW * kx, lay.photoH * ky);
          Logger.info(`WMHDR recompose done=${done}`);
        }
        ok = await ImageTools.saveHdrToGallery(context, pm, hdrParts, exifSeg);
        Logger.info(`WMHDR graft export ok=${ok}`);
      } else {
        ok = await ImageTools.saveToGallery(context, pm, this.exportPng, exifSeg);
      }
    } finally {
      pm.release();
    }
    if (ok) {
      await this.recordProfileExport();
    }
    return ok;
  }

  private currentRatioLabel(): string {
    for (const it of this.exportRatioItems) {
      if (Math.abs(it.value - this.exportRatio) < 0.0001) {
        return it.label;
      }
    }
    return '原图';
  }

  // 导出成功后写档案记录：只读 item.nativeExif（EXIF 解析器原生输出），手动输入不参与成就判定
  private async recordProfileExport(): Promise<void> {
    try {
      const item: PhotoItem | undefined = this.photoItems[this.currentIdx];
      if (item === undefined) {
        return;
      }
      const now: number = Date.now();
      const rec: ExportRecord = buildExportRecord(item.nativeExif, this.currentRatioLabel(), now);
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      const newly: AchievementDef[] = await ProfileStore.recordExport(context, this.profileStats, rec);
      this.profileStats = this.profileStats;
      if (newly.length > 0) {
        this.enqueueAchievementCard(newly);
      }
    } catch (err) {
      Logger.error(`profile record failed: ${JSON.stringify(err)}`);
    }
  }

  // ===== 成就解锁弹窗队列（右上角滑入，每日最多 3 次，批量合并一张卡）=====

  private enqueueAchievementCard(defs: AchievementDef[]): void {
    this.achQueue.push(defs);
    this.pumpAchQueue();
  }

  private pumpAchQueue(): void {
    if (this.achToastShow || this.achQueue.length === 0) {
      return;
    }
    const defs: AchievementDef[] = this.achQueue.shift() ?? [];
    if (defs.length === 0) {
      this.pumpAchQueue();
      return;
    }
    if (!this.tryConsumeAchPopup()) {
      this.pumpAchQueue();
      return;
    }
    this.achToastDefs = defs;
    setTimeout(() => {
      this.achToastShow = true;
      this.scheduleAchToastHide();
    }, 500);
  }

  private tryConsumeAchPopup(): boolean {
    const s: ProfileStats = this.profileStats;
    const today: number = dayStartTs(Date.now());
    if (s.popupDayTs !== today) {
      s.popupDayTs = today;
      s.popupCountToday = 0;
    }
    if (s.popupCountToday >= 3) {
      return false;
    }
    s.popupCountToday++;
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    ProfileStore.save(context, s);
    return true;
  }

  private scheduleAchToastHide(): void {
    if (this.achToastTimer >= 0) {
      clearTimeout(this.achToastTimer);
    }
    this.achToastTimer = setTimeout(() => {
      this.dismissAchToast();
    }, 3000);
  }

  private dismissAchToast(): void {
    this.achToastShow = false;
    if (this.achToastTimer >= 0) {
      clearTimeout(this.achToastTimer);
      this.achToastTimer = -1;
    }
    setTimeout(() => {
      this.pumpAchQueue();
    }, 350);
  }

  private async doSave(): Promise<void> {
    if (this.saving || this.batchRunning) {
      return;
    }
    if (this.pixelMap === undefined) {
      this.toast('请先选择图片');
      return;
    }
    this.saving = true;
    try {
      const ok: boolean = await this.exportCurrent();
      if (ok) {
        this.toast('已保存到图库');
      } else {
        this.toast('保存失败，请重试');
      }
    } catch (err) {
      Logger.error(`doSave failed: ${JSON.stringify(err)}`);
      this.toast('保存失败，请重试');
    } finally {
      this.saving = false;
      this.refreshLayouts();
    }
  }

  private async doSaveAll(): Promise<void> {
    if (this.batchRunning || this.saving) {
      return;
    }
    const total: number = this.photoItems.length;
    if (total === 0) {
      this.toast('请先选择图片');
      return;
    }
    this.batchRunning = true;
    this.batchStatus = '正在准备...';
    const backIdx: number = this.currentIdx;
    let okCount: number = 0;
    let failCount: number = 0;
    try {
      for (let i = 0; i < total; i++) {
        this.batchStatus = `正在处理 ${i + 1}/${total}`;
        let loaded: boolean = true;
        if (i !== this.currentIdx) {
          this.currentIdx = i;
          loaded = await this.loadCurrentPhoto();
        }
        if (!loaded) {
          failCount++;
          continue;
        }
        const ok: boolean = await this.exportCurrent();
        if (ok) {
          okCount++;
        } else {
          failCount++;
        }
      }
      if (failCount === 0) {
        this.toast(`批量保存完成：共 ${okCount} 张`);
      } else {
        this.toast(`批量保存完成：成功 ${okCount} 张，失败 ${failCount} 张`);
      }
    } catch (err) {
      Logger.error(`doSaveAll failed: ${JSON.stringify(err)}`);
      this.toast('批量保存中断，请重试');
    } finally {
      this.batchRunning = false;
      this.currentIdx = backIdx;
      await this.loadCurrentPhoto();
    }
  }

  @Builder
  camTitle() {
    if (this.camLine() !== '') {
      Text() {
        if (this.titleLogoFile() !== '') {
          if (this.personalLogoActive()) {
            ImageSpan(`file://${this.titleLogoFile()}`)
              .width(this.logoW())
              .height(this.logoH())
              .verticalAlign(ImageSpanAlignment.BASELINE)
          } else {
            ImageSpan($rawfile(this.titleLogoFile()))
              .width(this.logoW())
              .height(this.logoH())
              .verticalAlign(ImageSpanAlignment.BASELINE)
          }
        }
        if (this.camMakeText() !== '') {
          Span(this.titleLogoFile() !== '' ? ` ${this.camMakeText()}` : this.camMakeText())
            .fontSize(this.titleFont())
            .fontWeight(FontWeight.Bold)
            .fontColor(this.textColor)
        }
        if ((this.showMask & BIT_MODEL) !== 0 && this.camModelText() !== '') {
          Span(this.camMakeText() !== '' || this.titleLogoFile() !== '' ? ` ${this.camModelText()}` : this.camModelText())
            .fontSize(this.titleFont())
            .fontWeight(FontWeight.Medium)
            .fontColor(this.textColor)
        }
      }
      .fontSize(this.titleFont())
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .textAlign(this.barLayout === 1 ? TextAlign.Start : this.barTextAlign())
      .width('100%')
      .textShadow(this.frameMode === 0
        ? { radius: this.canvasC.f1 * 0.5, color: '#99000000', offsetY: this.canvasC.f1 * 0.15 }
        : { radius: 0, color: '#00000000', offsetY: 0 })
    }
  }

  // 胶囊标签单元：细描边圆角胶囊，内嵌单段参数
  @Builder
  parTagPill(s: string) {
    Text(s)
      .fontSize(this.canvasC.f2 * PAR_TAG_FACTOR)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.textColor)
      .maxLines(1)
      .padding({
        left: this.canvasC.f2 * 0.5,
        right: this.canvasC.f2 * 0.5,
        top: this.canvasC.f2 * 0.16,
        bottom: this.canvasC.f2 * 0.16
      })
      .borderRadius(this.canvasC.f2 * 0.75)
      .border({ width: Math.max(1, this.canvasC.f2 * 0.06), color: this.textColor })
      .textShadow(this.frameMode === 0
        ? { radius: this.canvasC.f2 * 0.5, color: '#99000000', offsetY: this.canvasC.f2 * 0.15 }
        : { radius: 0, color: '#00000000', offsetY: 0 })
  }

  @Builder
  parText() {
    if (this.parLine() !== '') {
      if (this.parTags) {
        if (this.barLayout === 1) {
          Row({ space: this.canvasC.f2 * 0.32 }) {
            ForEach(this.parSegs(), (s: string) => {
              this.parTagPill(s)
            }, (s: string) => s)
          }
        } else {
          Row({ space: this.canvasC.f2 * 0.32 }) {
            ForEach(this.parSegs(), (s: string) => {
              this.parTagPill(s)
            }, (s: string) => s)
          }
          .justifyContent(this.alignMode === 2 ? FlexAlign.End :
            (this.alignMode === 1 ? FlexAlign.Center : FlexAlign.Start))
          .width('100%')
        }
      } else if (this.barLayout === 1) {
        Text(this.parLine())
          .fontSize(this.canvasC.f2)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.textColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textShadow(this.frameMode === 0
            ? { radius: this.canvasC.f2 * 0.5, color: '#99000000', offsetY: this.canvasC.f2 * 0.15 }
            : { radius: 0, color: '#00000000', offsetY: 0 })
      } else {
        Text(this.parLine())
          .fontSize(this.canvasC.f2)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.textColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(this.barTextAlign())
          .width('100%')
          .textShadow(this.frameMode === 0
            ? { radius: this.canvasC.f2 * 0.5, color: '#99000000', offsetY: this.canvasC.f2 * 0.15 }
            : { radius: 0, color: '#00000000', offsetY: 0 })
      }
    }
  }

  @Builder
  lensText() {
    if (this.lensLine() !== '') {
      Text(this.lensLine())
        .fontSize(this.canvasC.f2)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.textColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(this.barLayout === 1 ? TextAlign.Start : this.barTextAlign())
        .width('100%')
        .textShadow(this.frameMode === 0
          ? { radius: this.canvasC.f2 * 0.5, color: '#99000000', offsetY: this.canvasC.f2 * 0.15 }
          : { radius: 0, color: '#00000000', offsetY: 0 })
    }
  }

  @Builder
  datSpans() {
    if (this.datDateStr() !== '') {
      Span(this.datDateStr())
    }
    if (this.barLayout !== 1) {
      if (this.signSlotLogo() !== '') {
        if (this.datDateStr() !== '') {
          Span('  ')
        }
        ImageSpan(`file://${this.signSlotLogo()}`)
          .width(this.signLogoW())
          .height(this.signLogoH())
          .verticalAlign(ImageSpanAlignment.BASELINE)
      } else if (this.signSlotText() !== '') {
        if (this.datDateStr() !== '') {
          Span(' ')
        }
        Span(this.signSlotText())
      }
    }
    if (this.datProgramStr() !== '') {
      if (this.datProgramNeedsSeparator()) {
        Span(` · ${this.datProgramStr()}`)
      } else {
        Span(this.datProgramStr())
      }
    }
  }

  @Builder
  datText() {
    if (this.datHasContent()) {
      if (this.barLayout === 1) {
        Text() {
          this.datSpans()
        }
        .fontSize(this.canvasC.f2 * DATE_SPLIT_FACTOR)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.textColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textShadow(this.frameMode === 0
          ? { radius: this.canvasC.f2 * 0.5, color: '#99000000', offsetY: this.canvasC.f2 * 0.15 }
          : { radius: 0, color: '#00000000', offsetY: 0 })
      } else {
        Text() {
          this.datSpans()
        }
        .fontSize(this.canvasC.f2)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.textColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(this.barTextAlign())
        .width('100%')
        .textShadow(this.frameMode === 0
          ? { radius: this.canvasC.f2 * 0.5, color: '#99000000', offsetY: this.canvasC.f2 * 0.15 }
          : { radius: 0, color: '#00000000', offsetY: 0 })
      }
    }
  }

  @Builder
  signText() {
    if (this.signLine() !== '') {
      Text(this.signLine())
        .fontSize(this.canvasC.f2)
        .fontWeight(FontWeight.Medium)
        .fontStyle(FontStyle.Italic)
        .fontColor(this.textColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(this.barLayout === 1 ? TextAlign.Start : this.barTextAlign())
        .width('100%')
        .textShadow(this.frameMode === 0
          ? { radius: this.canvasC.f2 * 0.5, color: '#99000000', offsetY: this.canvasC.f2 * 0.15 }
          : { radius: 0, color: '#00000000', offsetY: 0 })
    }
  }

  // 分栏署名行：位于日期下方，与参数/日期列左对齐
  @Builder
  signRow() {
    if (this.signSlotLogo() !== '') {
      Image(`file://${this.signSlotLogo()}`)
        .width(this.signLogoW())
        .height(this.signLogoH())
        .objectFit(ImageFit.Contain)
    } else if (this.signSlotText() !== '') {
      Text(this.signSlotText())
        .fontSize(this.canvasC.f2 * DATE_SPLIT_FACTOR)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.textColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textShadow(this.frameMode === 0
          ? { radius: this.canvasC.f2 * 0.5, color: '#99000000', offsetY: this.canvasC.f2 * 0.15 }
          : { radius: 0, color: '#00000000', offsetY: 0 })
    }
  }

  @Builder
  rightCluster() {
    Row() {
      if (this.imgLogoFile() !== '') {
        if (this.personalLogoActive()) {
          Image(`file://${this.imgLogoFile()}`)
            .height(this.imgLogoH())
            .width(this.imgLogoW())
            .objectFit(ImageFit.Contain)
            .margin({ right: this.canvasC.f2 * 0.8 })
        } else {
          Image($rawfile(this.imgLogoFile()))
            .height(this.imgLogoH())
            .width(this.imgLogoW())
            .objectFit(ImageFit.Contain)
            .margin({ right: this.canvasC.f2 * 0.8 })
        }
      }
      if (this.parLine() !== '' || this.splitDatLine() !== '' || this.signRowOn()) {
        Divider()
          .vertical(true)
          .strokeWidth(Math.max(0.5, this.canvasC.f2 * 0.03))
          .color(this.textColor)
          .opacity(0.65)
          .height(this.dividerH())
      }
      Column({ space: this.canvasC.f2 * 0.45 }) {
        this.parText()
        this.datText()
        this.signRow()
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: this.canvasC.f2 * 0.8 })
    }
    .alignItems(VerticalAlign.Center)
  }

  // 台历信息栏：左下大字日号，右侧从上到下为年月/相机型号/曝光参数，右下角署名
  @Builder
  calBar() {
    Row() {
      if (this.calDayStr() !== '') {
        Text(this.calDayStr())
          .fontSize(this.canvasC.f2 * CAL_DAY_FACTOR)
          .lineHeight(this.canvasC.f2 * CAL_DAY_FACTOR * CAL_DAY_LH)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.textColor)
          .maxLines(1)
          .textShadow(this.frameMode === 0
            ? { radius: this.canvasC.f2 * 0.5, color: '#99000000', offsetY: this.canvasC.f2 * 0.15 }
            : { radius: 0, color: '#00000000', offsetY: 0 })
      }
      Column({ space: this.canvasC.f2 * 0.45 }) {
        if (this.calYearMonth() !== '') {
          Text(this.calYearMonth())
            .fontSize(this.canvasC.f2 * DATE_SPLIT_FACTOR)
            .lineHeight(this.canvasC.f2 * DATE_SPLIT_FACTOR * CAL_BOX_LH)
            .fontWeight(FontWeight.Bold)
            .fontColor(CAL_YM_COLOR)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textShadow(this.frameMode === 0
              ? { radius: this.canvasC.f2 * 0.5, color: '#99000000', offsetY: this.canvasC.f2 * 0.15 }
              : { radius: 0, color: '#00000000', offsetY: 0 })
        }
        if (this.camLine() !== '') {
          Text(this.camLine())
            .fontSize(this.canvasC.f2)
            .lineHeight(this.canvasC.f2 * CAL_BOX_LH)
            .fontWeight(FontWeight.Normal)
            .fontColor(this.textColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textShadow(this.frameMode === 0
              ? { radius: this.canvasC.f2 * 0.5, color: '#99000000', offsetY: this.canvasC.f2 * 0.15 }
              : { radius: 0, color: '#00000000', offsetY: 0 })
        }
        if (this.parLine() !== '') {
          Text(this.parLine())
            .fontSize(this.canvasC.f2 * DATE_SPLIT_FACTOR)
            .lineHeight(this.canvasC.f2 * DATE_SPLIT_FACTOR * CAL_BOX_LH)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.textColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textShadow(this.frameMode === 0
              ? { radius: this.canvasC.f2 * 0.5, color: '#99000000', offsetY: this.canvasC.f2 * 0.15 }
              : { radius: 0, color: '#00000000', offsetY: 0 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({
        left: this.calDayStr() !== '' ? this.canvasC.f2 * 0.5 : 0,
        bottom: this.calLiftMargin()
      })

      this.signRow()
    }
    .width('100%')
    .alignItems(VerticalAlign.Bottom)
  }

  // 会展：白框左下从上到下——署名 / 相机型号 / 曝光参数·拍摄时间（行盒高度=公式值）
  @Builder
  expoBar() {
    Column({ space: this.canvasC.f2 * EXPO_GAP }) {
      if (this.expoHeadHas()) {
        Text() {
          this.expoSignSpans()
        }
          .fontSize(this.canvasC.f2)
          .lineHeight(this.canvasC.f2 * EXPO_HEAD_LH)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.textColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textShadow(this.frameMode === 0
            ? { radius: this.canvasC.f2 * 0.5, color: '#99000000', offsetY: this.canvasC.f2 * 0.15 }
            : { radius: 0, color: '#00000000', offsetY: 0 })
      }
      if (this.camLine() !== '') {
        Text(this.camLine())
          .fontSize(this.canvasC.f2 * 0.85)
          .lineHeight(this.canvasC.f2 * EXPO_SUB_LH)
          .fontColor(this.textColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textShadow(this.frameMode === 0
            ? { radius: this.canvasC.f2 * 0.5, color: '#99000000', offsetY: this.canvasC.f2 * 0.15 }
            : { radius: 0, color: '#00000000', offsetY: 0 })
      }
      if (this.expoParDate() !== '') {
        Text(this.expoParDate())
          .fontSize(this.canvasC.f2 * 0.85)
          .lineHeight(this.canvasC.f2 * EXPO_SUB_LH)
          .fontColor(this.textColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textShadow(this.frameMode === 0
            ? { radius: this.canvasC.f2 * 0.5, color: '#99000000', offsetY: this.canvasC.f2 * 0.15 }
            : { radius: 0, color: '#00000000', offsetY: 0 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  barArea() {
    if (this.barLayout === 1) {
      Row({ space: this.canvasC.f2 }) {
        Column({ space: this.canvasC.f2 * 0.45 }) {
          this.camTitle()
          this.lensText()
          this.signText()
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        this.rightCluster()
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
    } else if (this.barLayout === 2) {
      this.calBar()
    } else if (this.barLayout === 3) {
      this.expoBar()
    } else {
      Column({ space: this.canvasC.f2 * BAR_GAP }) {
        this.camTitle()
        this.parText()
        this.lensText()
        this.datText()
        this.signText()
      }
      .width('100%')
    }
  }

  @Builder
  directCornerBlock() {
    Column({ space: this.canvasC.f2 * BAR_GAP }) {
      this.camTitle()
      this.parText()
      this.lensText()
      this.datText()
      this.signText()
    }
    .width(this.canvasC.outW * 0.7)
  }

  private filmMachText(): string {
    if ((this.showMask & BIT_MODEL) === 0) {
      return '';
    }
    const mm: string[] = [];
    if (this.exif.make !== '') {
      mm.push(cleanMakeText(this.exif.make));
    }
    if (this.camModelText() !== '') {
      mm.push(this.camModelText());
    }
    return mm.join(' ');
  }

  private filmMainHas(): boolean {
    return this.filmMachText() !== '' || this.datDateStr() !== '' ||
      this.signSlotLogo() !== '' || this.signSlotText() !== '';
  }

  private filmShadow(): ShadowOptions {
    return {
      radius: this.canvasC.f2 * 0.4,
      color: '#73000000',
      offsetX: 0,
      offsetY: this.canvasC.f2 * 0.12
    };
  }

  // 胶片主行内容：品牌 · 日期 + 署名（Logo 或 ©文字）
  @Builder
  filmMainSpans() {
    if (this.filmMachText() !== '') {
      Span(this.filmMachText())
    }
    if (this.datDateStr() !== '') {
      if (this.filmMachText() !== '') {
        Span(` · ${this.datDateStr()}`)
      } else {
        Span(this.datDateStr())
      }
    }
    if (this.signSlotLogo() !== '') {
      if (this.filmMachText() !== '' || this.datDateStr() !== '') {
        Span('  ')
      }
      ImageSpan(`file://${this.signSlotLogo()}`)
        .width(this.signLogoW())
        .height(this.signLogoH())
        .verticalAlign(ImageSpanAlignment.BASELINE)
    } else if (this.signSlotText() !== '') {
      if (this.filmMachText() !== '' || this.datDateStr() !== '') {
        Span(` · ${this.signSlotText()}`)
      } else {
        Span(this.signSlotText())
      }
    }
  }

  @Builder
  filmCornerBlock() {
    Column({ space: this.canvasC.f2 * 0.5 }) {
      if (this.filmMainHas()) {
        Text() {
          this.filmMainSpans()
        }
          .fontSize(this.canvasC.f2)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.textColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textShadow(this.filmShadow())
      }
      if (this.parLine() !== '') {
        Text(this.parLine())
          .fontSize(this.canvasC.f2 * 0.85)
          .fontColor(this.textColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textShadow(this.filmShadow())
      }
      if (this.lensLine() !== '') {
        Text(this.lensLine())
          .fontSize(this.canvasC.f2 * 0.85)
          .fontColor(this.textColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textShadow(this.filmShadow())
      }
      if ((this.showMask & BIT_PROGRAM) !== 0 && this.exif.program !== '') {
        Text(this.exif.program)
          .fontSize(this.canvasC.f2 * 0.85)
          .fontColor(this.textColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textShadow(this.filmShadow())
      }
    }
    .alignItems(HorizontalAlign.End)
    .constraintSize({ maxWidth: this.canvasC.outW * 0.85 })
  }

  // 会展：署名行是否有内容（Logo 或 ©署名）
  private expoHeadHas(): boolean {
    return this.signSlotLogo() !== '' || this.signSlotText() !== '';
  }

  // 会展：曝光参数 · 拍摄时间
  private expoParDate(): string {
    const par: string = this.parLine();
    const date: string = this.datDateStr();
    if (par !== '' && date !== '') {
      return `${par} · ${date}`;
    }
    return par !== '' ? par : date;
  }

  // 会展：署名行内容（Logo 或 ©文字）
  @Builder
  expoSignSpans() {
    if (this.signSlotLogo() !== '') {
      ImageSpan(`file://${this.signSlotLogo()}`)
        .width(this.signLogoW())
        .height(this.signLogoH())
        .verticalAlign(ImageSpanAlignment.BASELINE)
    } else if (this.signSlotText() !== '') {
      Span(this.signSlotText())
    }
  }

  // 会展：左下角从上到下——署名 / 相机型号 / 曝光参数·拍摄时间（直印模式）
  @Builder
  expoCornerBlock() {
    Column({ space: this.canvasC.f2 * 0.5 }) {
      if (this.expoHeadHas()) {
        Text() {
          this.expoSignSpans()
        }
          .fontSize(this.canvasC.f2)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.textColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textShadow(this.filmShadow())
      }
      if (this.camLine() !== '') {
        Text(this.camLine())
          .fontSize(this.canvasC.f2 * 0.85)
          .fontColor(this.textColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textShadow(this.filmShadow())
      }
      if (this.expoParDate() !== '') {
        Text(this.expoParDate())
          .fontSize(this.canvasC.f2 * 0.85)
          .fontColor(this.textColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textShadow(this.filmShadow())
      }
    }
    .alignItems(HorizontalAlign.Start)
    .constraintSize({ maxWidth: this.canvasC.outW * 0.85 })
  }

  @Builder
  cornerContent() {
    if (this.barLayout === 3) {
      this.expoCornerBlock()
    } else if (this.filmStyle) {
      this.filmCornerBlock()
    } else {
      this.directCornerBlock()
    }
  }

  private photoOuterShadow(): ShadowOptions {
    if (this.canvasC.mode === 0 || this.shadowMode === 2) {
      return { radius: 0, color: '#00000000' };
    }
    const blurBg: boolean = this.canvasC.mode === 2;
    if (this.shadowMode === 0) {
      return {
        radius: this.canvasC.f2 * (blurBg ? 1.8 : 1.3),
        color: blurBg ? '#C0000000' : '#80000000',
        offsetX: this.canvasC.f2 * (blurBg ? 1.1 : 0.9),
        offsetY: this.canvasC.f2 * (blurBg ? 1.1 : 0.9)
      };
    }
    return {
      radius: this.canvasC.f2 * (blurBg ? 3.2 : 2.6),
      color: blurBg ? '#B3000000' : '#7A000000',
      offsetX: 0,
      offsetY: 0
    };
  }

  @Builder
  insetShadowOverlay() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height(this.canvasC.f2 * 1.5)
        .linearGradient({ angle: 180, colors: [['#73000000', 0], ['#00000000', 1]] })
      Column()
        .width('100%')
        .height(this.canvasC.f2 * 1.5)
        .linearGradient({ angle: 0, colors: [['#73000000', 0], ['#00000000', 1]] })
        .position({ x: 0, y: this.canvasC.photoH - this.canvasC.f2 * 1.5 })
      Column()
        .height('100%')
        .width(this.canvasC.f2 * 1.5)
        .linearGradient({ angle: 90, colors: [['#73000000', 0], ['#00000000', 1]] })
      Column()
        .height('100%')
        .width(this.canvasC.f2 * 1.5)
        .linearGradient({ angle: 270, colors: [['#73000000', 0], ['#00000000', 1]] })
        .position({ x: this.canvasC.photoW - this.canvasC.f2 * 1.5, y: 0 })
    }
    .width(this.canvasC.photoW)
    .height(this.canvasC.photoH)
    .borderRadius(this.canvasC.photoRadius)
    .clip(true)
  }

  @Builder
  watermarkCanvas() {
    Stack() {
      if (this.canvasC.mode === 0) {
        if (this.pixelMap !== undefined) {
          Image(this.pixelMap)
            .objectFit(ImageFit.Fill)
            .width(this.canvasC.outW)
            .height(this.canvasC.outH)
        }
        if (this.hasBar()) {
          if (this.directPos === 0 && !this.filmStyle) {
            Column() {
              this.barArea()
            }
            .width(this.canvasC.outW - this.canvasC.f2 * 3)
            .height(this.canvasC.outH)
            .justifyContent(FlexAlign.End)
            .padding({ bottom: this.canvasC.barInset })
          } else if (this.directPos === 0) {
            Column() {
              Blank()
              Row() {
                Blank()
                this.filmCornerBlock()
              }
              .width('100%')
            }
            .width('100%')
            .height('100%')
            .padding(this.canvasC.f2 * 1.2)
          } else if (this.directPos === 1) {
            Column() {
              Blank()
              Row() {
                Blank()
                this.cornerContent()
              }
              .width('100%')
            }
            .width('100%')
            .height('100%')
            .padding(this.canvasC.f2 * 1.2)
          } else if (this.directPos === 2) {
            Column() {
              Blank()
              Row() {
                this.cornerContent()
                Blank()
              }
              .width('100%')
            }
            .width('100%')
            .height('100%')
            .padding(this.canvasC.f2 * 1.2)
          } else {
            Column() {
              Row() {
                this.cornerContent()
                Blank()
              }
              .width('100%')
              Blank()
            }
            .width('100%')
            .height('100%')
            .padding(this.canvasC.f2 * 1.2)
          }
        }
      } else {
        if (this.canvasC.mode === 2 && this.bgMap !== undefined) {
          Image(this.bgMap)
            .objectFit(ImageFit.Cover)
            .width(this.canvasC.outW)
            .height(this.canvasC.outH)
        }
        Column() {
          if (this.pixelMap !== undefined) {
            Stack() {
              Image(this.pixelMap)
                .objectFit(ImageFit.Fill)
                .width(this.canvasC.photoW)
                .height(this.canvasC.photoH)
                .borderRadius(this.canvasC.photoRadius)
                .clip(true)
                .border(this.canvasC.keylineW > 0
                  ? { width: this.canvasC.keylineW, color: this.keylineColor }
                  : { width: 0, color: '#00000000' })
                .shadow(this.photoOuterShadow())
              if (this.canvasC.mode !== 0 && this.shadowMode === 2) {
                this.insetShadowOverlay()
              }
            }
            .width(this.canvasC.photoW)
            .height(this.canvasC.photoH)
          }
          if (this.hasBar()) {
            if (this.canvasC.tailPad > 0) {
              Column() {
                this.barArea()
              }
              .width('100%')
              .margin({ top: this.canvasC.f2 })
            } else if (this.barLayout === 3) {
              // 会展：文字块贴底白边（底距=边框宽），与照片的间距固定为 gapAbove
              Column() {
                this.barArea()
              }
              .width('100%')
              .layoutWeight(1)
              .justifyContent(FlexAlign.End)
              .padding({ bottom: this.canvasC.pad })
            } else {
              Column() {
                this.barArea()
              }
              .width('100%')
              .layoutWeight(1)
              .justifyContent(FlexAlign.Center)
            }
          }
        }
        .width(this.canvasC.outW)
        .height(this.canvasC.outH)
        .padding({
          left: this.canvasC.pad,
          right: this.canvasC.pad,
          top: this.canvasC.pad,
          bottom: this.hasBar() && this.canvasC.tailPad <= 0
            ? 0 : this.canvasC.pad + this.canvasC.tailPad
        })
      }
    }
    .width(this.canvasC.outW)
    .height(this.canvasC.outH)
    .backgroundColor(this.canvasC.mode === 2 ? '#000000' : this.frameColor)
  }

  @Builder
  presetCard(p: StylePreset) {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.Center }) {
        Stack({ alignContent: Alignment.TopEnd }) {
          if (p.custom) {
            Image(`file://${p.refFile}`)
              .width('100%')
              .aspectRatio(p.refAspect)
              .objectFit(ImageFit.Cover)
              .borderRadius(6)
              .border({ width: 1, color: $r('app.color.ref_border') })
          } else {
            Image($rawfile(p.refFile))
              .width('100%')
              .aspectRatio(p.refAspect)
              .objectFit(ImageFit.Cover)
              .borderRadius(6)
              .border({ width: 1, color: $r('app.color.ref_border') })
          }
          if (this.favIds.includes(p.id)) {
            Image($r('app.media.heart_red'))
              .width(16)
              .height(16)
              .margin(6)
          }
          if (p.custom) {
            Text('✕')
              .fontSize(11)
              .fontColor('#FFFFFF')
              .fontWeight(FontWeight.Medium)
              .width(20)
              .height(20)
              .textAlign(TextAlign.Center)
              .borderRadius(10)
              .backgroundColor('#99000000')
              .position({ x: 5, y: 5 })
              .onClick(() => {
                this.confirmDeleteStyle(p);
              })
          }
        }
        .width('100%')

        if (this.heartAnimId === p.id) {
          Stack({ alignContent: Alignment.Bottom }) {
            Image($r('app.media.heart_outline'))
              .width(44)
              .height(44)
            Stack({ alignContent: Alignment.Bottom }) {
              Image($r('app.media.heart_red'))
                .width(44)
                .height(44)
            }
            .width(44)
            .height(44 * this.heartFill)
            .clip(true)
          }
          .width(44)
          .height(44)
          .scale({ x: this.heartPop, y: this.heartPop })
          .opacity(this.heartAlpha)
        }
      }
      .width('100%')

      Blank()

      Column({ space: 4 }) {
        Text(p.name)
          .fontSize(12)
          .fontColor($r('app.color.text_main'))
          .fontWeight(this.activePreset === p.id ? FontWeight.Medium : FontWeight.Normal)
          .width('100%')
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(p.desc)
          .fontSize(10)
          .fontColor($r('app.color.text_hint'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
    }
    .padding(8)
    .borderRadius(10)
    .backgroundColor($r('app.color.card_bg'))
    .border({ width: this.activePreset === p.id ? 1.5 : 1, color: this.activePreset === p.id ? $r('app.color.accent') : $r('app.color.border_preset') })
    .height(this.presetCardH(p))
    .onClick(() => {
      if (Date.now() - this.lastLongPressAt < 700) {
        return;
      }
      this.applyPreset(p);
    })
    .gesture(
      LongPressGesture({ duration: 400 })
        .onAction(() => {
          this.onCardLongPress(p);
        })
    )
  }

  private presetCardW(): number {
    if (this.presetSingleCol) {
      return this.presetGridW;
    }
    return (this.presetGridW - 10) / 2;
  }

  private presetImageH(p: StylePreset): number {
    const inner: number = this.presetCardW() - 16;
    if (inner <= 0) {
      return 0;
    }
    return inner / p.refAspect;
  }

  private presetCardH(p: StylePreset): number {
    const headroom: number = 70;
    const selfH: number = headroom + this.presetImageH(p);
    if (this.presetSingleCol) {
      return selfH;
    }
    const i: number = this.styleList.indexOf(p);
    if (i < 0) {
      return selfH;
    }
    const mateIdx: number = i % 2 === 0 ? i + 1 : i - 1;
    if (mateIdx < 0 || mateIdx >= this.styleList.length) {
      return selfH;
    }
    const mateH: number = headroom + this.presetImageH(this.styleList[mateIdx]);
    return Math.max(selfH, mateH);
  }

  @Builder
  presetsTab() {
    Column({ space: 10 }) {
      Text('选择一套样式，之后可在其他页签微调 · 长按卡片收藏置顶')
        .fontSize(12)
        .fontColor($r('app.color.text_hint'))
        .width('100%')
        .textAlign(TextAlign.Center)

      Text('＋ 保存当前样式为个人样式')
        .fontSize(13)
        .fontColor($r('app.color.text_sub'))
        .border({ width: 1.2, color: $r('app.color.border_soft') })
        .borderRadius(10)
        .height(40)
        .width('100%')
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.saveCurrentStyle();
        })

      Grid() {
        ForEach(this.styleList, (p: StylePreset) => {
          GridItem() {
            this.presetCard(p)
          }
        }, (p: StylePreset) => p.id)
      }
      .columnsTemplate(this.presetSingleCol ? '1fr' : '1fr 1fr')
      .columnsGap(10)
      .rowsGap(10)
      .width('100%')
      .onAreaChange((_o: Area, n: Area) => {
        const w: number = Number(n.width);
        if (w > 0) {
          this.presetGridW = w;
        }
      })
    }
    .width('100%')
  }

  @Builder
  paramsTab() {
    Column({ space: 12 }) {
      Text(this.exifHint())
        .fontSize(12)
        .fontColor($r('app.color.text_hint'))
        .width('100%')
        .textAlign(TextAlign.Center)

      FieldRow({
        label: '相机品牌', value: this.exif.make, hint: '如 HUAWEI',
        checked: (this.showMask & BIT_MAKE) !== 0,
        onChange: (v: string) => {
          this.updateExif(0, v);
        },
        onCheck: (on: boolean) => {
          this.toggleFieldBit(BIT_MAKE, on);
        }
      })
      FieldRow({
        label: '相机型号', value: this.exif.model, hint: '如 Pura 70',
        checked: (this.showMask & BIT_MODEL) !== 0,
        onChange: (v: string) => {
          this.updateExif(1, v);
        },
        onCheck: (on: boolean) => {
          this.toggleFieldBit(BIT_MODEL, on);
        }
      })
      FieldRow({
        label: '镜头型号', value: this.exif.lensModel, hint: '镜头名称',
        checked: (this.showMask & BIT_LENS) !== 0,
        onChange: (v: string) => {
          this.updateExif(2, v);
        },
        onCheck: (on: boolean) => {
          this.toggleFieldBit(BIT_LENS, on);
        }
      })
      Column({ space: 12 }) {
        Row({ space: 10 }) {
          Checkbox({ name: '曝光参数' })
            .select(this.expoGroupOn())
            .selectedColor($r('app.color.accent'))
            .width(20)
            .height(20)
            .onChange((on: boolean) => {
              this.toggleExpoGroup(on);
            })
          Text('曝光参数')
            .fontSize(14)
            .fontColor($r('app.color.text_main'))
            .layoutWeight(1)
        }
        .width('100%')

        Column({ space: 10 }) {
          FieldRow({
            label: '焦距', value: this.exif.focalLength, hint: 'mm', checkable: false,
            onChange: (v: string) => {
              this.updateExif(3, v);
            }
          })
          FieldRow({
            label: '等效焦距', value: this.exif.focal35, hint: 'mm', checkable: false,
            onChange: (v: string) => {
              this.updateExif(4, v);
            }
          })
          FieldRow({
            label: '光圈', value: this.exif.fNumber, hint: '如 1.8', checkable: false,
            onChange: (v: string) => {
              this.updateExif(5, v);
            }
          })
          FieldRow({
            label: '快门', value: this.exif.exposureTime, hint: '如 1/120', checkable: false,
            onChange: (v: string) => {
              this.updateExif(6, v);
            }
          })
          FieldRow({
            label: 'ISO', value: this.exif.iso, hint: '如 400', checkable: false,
            onChange: (v: string) => {
              this.updateExif(7, v);
            }
          })
        }
        .width('100%')
      }
      .width('100%')
      .padding(12)
      .borderRadius(12)
      .backgroundColor($r('app.color.card_bg'))
      .border({ width: 1, color: $r('app.color.border_preset') })
      FieldRow({
        label: '档位', value: this.exif.program, hint: '如 A 光圈优先',
        checked: (this.showMask & BIT_PROGRAM) !== 0,
        onChange: (v: string) => {
          this.updateExif(8, v);
        },
        onCheck: (on: boolean) => {
          this.toggleFieldBit(BIT_PROGRAM, on);
        }
      })
      FieldRow({
        label: '拍摄日期', value: this.exif.dateTime, hint: '如 2026.10.12 15:30',
        checked: (this.showMask & BIT_DATE) !== 0,
        onChange: (v: string) => {
          this.updateExif(9, v);
        },
        onCheck: (on: boolean) => {
          this.toggleFieldBit(BIT_DATE, on);
        }
      })
      FieldRow({
        label: '署名', value: this.exif.signature, hint: '如 ©印痕',
        checked: (this.showMask & BIT_SIGN) !== 0,
        onChange: (v: string) => {
          this.updateExif(10, v);
        },
        onCheck: (on: boolean) => {
          this.toggleFieldBit(BIT_SIGN, on);
        }
      })
    }
    .width('100%')
  }

  private brandSelectOptions(): SelectOption[] {
    const opts: SelectOption[] = [];
    opts.push({ value: '自动识别' });
    for (const b of BRAND_LOGOS) {
      opts.push({ value: b.name });
    }
    return opts;
  }

  private brandPickIndex(): number {
    if (this.brandPick === '') {
      return 0;
    }
    for (let i = 0; i < BRAND_LOGOS.length; i++) {
      if (BRAND_LOGOS[i].key === this.brandPick) {
        return i + 1;
      }
    }
    return 0;
  }

  private brandPickLabel(): string {
    if (this.brandPick === '') {
      return '自动识别';
    }
    const b: BrandLogo | undefined = brandByKey(this.brandPick);
    return b !== undefined ? b.name : '自动识别';
  }

  @Builder
  personalLogoSection() {
    Column({ space: 10 }) {
      Text('个人 Logo')
        .fontSize(14)
        .fontColor($r('app.color.text_sub'))
        .width('100%')
      if (this.personalLogoAspect > 0) {
        Row({ space: 12 }) {
          Row() {
            Image(`file://${this.personalPreviewFile()}`)
              .height(30)
              .width(Math.min(90, 30 * this.personalLogoAspect))
              .objectFit(ImageFit.Contain)
          }
          .height(48)
          .padding({ left: 12, right: 12 })
          .justifyContent(FlexAlign.Center)
          .borderRadius(10)
          .backgroundColor('#F0F0F3')
          .border({ width: 1, color: $r('app.color.border_soft') })
          Row({ space: 8 }) {
            Text('更换图片')
              .fontSize(13)
              .fontColor($r('app.color.text_sub'))
              .border({ width: 1.2, color: $r('app.color.border_soft') })
              .borderRadius(15)
              .padding({ left: 13, right: 13, top: 6, bottom: 6 })
              .onClick(() => {
                this.pickPersonalLogo(this.personalLogoMode === 0 ? 1 : this.personalLogoMode);
              })
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.End)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        SegmentedControl({
          items: this.personalModeItems,
          selected: this.personalLogoMode,
          even: true,
          onPick: (v: number) => {
            this.setPersonalLogoMode(v);
          }
        })
      } else {
        Text('＋ 添加个人 Logo（可替换品牌 Logo 或署名）')
          .fontSize(13)
          .fontColor($r('app.color.text_sub'))
          .border({ width: 1.2, color: $r('app.color.border_soft') })
          .borderRadius(15)
          .padding({ left: 13, right: 13, top: 6, bottom: 6 })
          .onClick(() => {
            this.pickPersonalLogo(1);
          })
      }
    }
    .width('100%')
  }

  @Builder
  styleTab() {
    Column({ space: 14 }) {
      LabeledSlider({
        label: '字号缩放',
        value: this.sizeScalePct,
        min: 60,
        max: 160,
        step: 5,
        unit: '%',
        onValue: (v: number) => {
          this.sizeScalePct = v;
          this.refreshLayouts();
        }
      })
      Text('信息栏布局')
        .fontSize(14)
        .fontColor($r('app.color.text_sub'))
        .width('100%')
      SegmentedControl({
        items: this.barLayoutItems,
        selected: this.barLayout,
        even: true,
        onPick: (v: number) => {
          this.barLayout = v;
          this.refreshLayouts();
        }
      })
      ToggleRow({
        label: '参数胶囊标签',
        isOn: this.parTags,
        onToggle: (on: boolean) => {
          this.parTags = on;
          this.refreshLayouts();
        }
      })
      ToggleRow({
        label: '品牌 Logo',
        isOn: this.logoOn,
        onToggle: (on: boolean) => {
          this.logoOn = on;
        }
      })
      if (this.logoOn) {
        Text('品牌选择（默认自动识别）')
          .fontSize(14)
          .fontColor($r('app.color.text_sub'))
          .width('100%')
        Select(this.brandSelectOptions())
          .selected(this.brandPickIndex())
          .value(this.brandPickLabel())
          .font({ size: 14 })
          .fontColor($r('app.color.text_main'))
          .selectedOptionFontColor($r('app.color.accent'))
          .optionFontColor($r('app.color.text_main'))
          .optionBgColor($r('app.color.card_bg'))
          .selectedOptionBgColor($r('app.color.chip_sel_bg'))
          .backgroundColor($r('app.color.chip_bg'))
          .borderRadius(10)
          .height(40)
          .width('100%')
          .onSelect((index: number, value: string) => {
            this.brandPick = index === 0 ? '' : BRAND_LOGOS[index - 1].key;
          })
      }
      this.personalLogoSection()
      ColorSwatches({
        label: '文字颜色',
        selected: this.textColor,
        colors: WM_TEXT_COLORS,
        onPick: (c: string) => {
          this.textColor = c;
        }
      })
      if (this.barLayout === 0) {
        Text('文字对齐')
          .fontSize(14)
          .fontColor($r('app.color.text_sub'))
          .width('100%')
        SegmentedControl({
          items: this.alignItems,
          selected: this.alignMode,
          even: true,
          onPick: (v: number) => {
            this.alignMode = v;
          }
        })
      }
    }
    .width('100%')
  }

  @Builder
  frameTab() {
    Column({ space: 14 }) {
      Text('边框样式')
        .fontSize(14)
        .fontColor($r('app.color.text_sub'))
        .width('100%')
      SegmentedControl({
        items: this.frameModeItems,
        selected: this.frameMode,
        even: true,
        onPick: (v: number) => {
          this.onFrameModePick(v);
        }
      })

      if (this.frameMode === 0) {
        Text('直印位置')
          .fontSize(14)
          .fontColor($r('app.color.text_sub'))
          .width('100%')
        SegmentedControl({
          items: this.directPosItems,
          selected: this.directPos,
          even: true,
          onPick: (v: number) => {
            this.directPos = v;
          }
        })
        Text('拍摄参数将直接印在照片上，不加边框')
          .fontSize(12)
          .fontColor($r('app.color.text_hint'))
          .width('100%')
      }
      if (this.frameMode !== 0) {
        Text('留白布局')
          .fontSize(14)
          .fontColor($r('app.color.text_sub'))
          .width('100%')
        SegmentedControl({
          items: this.layoutKindItems,
          selected: this.layoutKind,
          even: true,
          onPick: (v: number) => {
            this.layoutKind = v;
            this.refreshLayouts();
          }
        })
      }
      if (this.frameMode !== 0) {
        Text('照片阴影')
          .fontSize(14)
          .fontColor($r('app.color.text_sub'))
          .width('100%')
        SegmentedControl({
          items: this.shadowItems,
          selected: this.shadowMode,
          even: true,
          onPick: (v: number) => {
            this.shadowMode = v;
          }
        })
      }
      if (this.frameMode === 2) {
        LabeledSlider({
          label: '模糊强度',
          value: this.blurPct,
          min: 4,
          max: 30,
          step: 1,
          unit: '%',
          onValue: (v: number) => {
            this.blurPct = v;
            this.scheduleBgRefresh();
          }
        })
      }
      if (this.frameMode !== 0) {
        LabeledSlider({
          label: '边距宽度',
          value: this.frameMarginPct,
          min: 0,
          max: 20,
          step: 1,
          unit: '%',
          onValue: (v: number) => {
            this.frameMarginPct = v;
            this.refreshLayouts();
          }
        })
        ToggleRow({
          label: '照片描边',
          isOn: this.keylineOn,
          onToggle: (on: boolean) => {
            this.keylineOn = on;
            this.refreshLayouts();
          }
        })
        if (this.keylineOn) {
          ColorSwatches({
            label: '描边颜色',
            selected: this.keylineColor,
            colors: KEYLINE_COLORS,
            onPick: (c: string) => {
              this.keylineColor = c;
            }
          })
        }
      }
      if (this.frameMode === 1) {
        ColorSwatches({
          label: '印框颜色',
          selected: this.frameColor,
          colors: FRAME_COLORS,
          onPick: (c: string) => {
            this.onFrameColorPick(c);
          }
        })
      }
    }
    .width('100%')
  }

  @Builder
  exportTab() {
    Column({ space: 14 }) {
      Text('画幅比例')
        .fontSize(14)
        .fontColor($r('app.color.text_sub'))
        .width('100%')
      SegmentedControl({
        items: this.exportRatioItems,
        selected: this.exportRatio,
        even: true,
        onPick: (v: number) => {
          this.onExportRatioPick(v);
        }
      })

      Text('图片格式')
        .fontSize(14)
        .fontColor($r('app.color.text_sub'))
        .width('100%')
      SegmentedControl({
        items: this.formatItems,
        selected: this.exportPng ? 1 : 0,
        even: true,
        onPick: (v: number) => {
          this.exportPng = v === 1;
        }
      })

      Text(this.outputInfoText())
        .fontSize(12)
        .fontColor($r('app.color.text_hint'))
        .width('100%')
        .textAlign(TextAlign.Center)

      Row() {
        SaveButton({ icon: SaveIconStyle.FULL_FILLED, text: SaveDescription.SAVE_TO_GALLERY, buttonType: ButtonType.Capsule })
          .onClick((event: ClickEvent, result: SaveButtonOnClickResult) => {
            if (result === SaveButtonOnClickResult.SUCCESS) {
              this.doSave();
            }
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      if (this.photoItems.length > 1) {
        Divider()
          .color($r('app.color.border_soft'))
          .margin({ top: 4, bottom: 4 })
        Text(`批量导出（已选 ${this.photoItems.length} 张，每张使用各自参数）`)
          .fontSize(13)
          .fontColor($r('app.color.text_sub'))
          .width('100%')
          .textAlign(TextAlign.Center)
        Row() {
          SaveButton({ icon: SaveIconStyle.FULL_FILLED, text: SaveDescription.SAVE_TO_GALLERY, buttonType: ButtonType.Capsule })
            .onClick((event: ClickEvent, result: SaveButtonOnClickResult) => {
              if (result === SaveButtonOnClickResult.SUCCESS) {
                this.doSaveAll();
              }
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
  }

  // ===== 我的（摄影档案 + 成就墙 + 设置）=====

  @Builder
  mineTab() {
    Column({ space: 14 }) {
      // 我的页三段切换（页签级下划线式）：统计 | 成就墙 | 设置
      SectionTabs({
        items: this.mineSectionItems,
        selected: this.mineSection,
        onPick: (v: number) => {
          this.mineSection = v;
          if (v === 2) {
            this.refreshCacheSize();
          }
        }
      })
      if (this.mineSection === 2) {
        this.settingsTab()
      } else if (this.profileStats.totalExports === 0) {
        Column({ space: 16 }) {
          Text('📷')
            .fontSize(44)
          Text('还没有记录——去导出第一张照片，你的摄影档案会从这里开始。')
            .fontSize(14)
            .fontColor($r('app.color.text_sub'))
            .textAlign(TextAlign.Center)
            .lineHeight(22)
          Text('去导出')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.accent'))
            .borderRadius(20)
            .padding({ left: 28, right: 28, top: 10, bottom: 10 })
            .onClick(() => {
              this.activeTab = 3;
            })
        }
        .width('100%')
        .padding({ top: 48, bottom: 48, left: 24, right: 24 })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        this.profileHeaderCard()
        if (this.mineSection === 0) {
          // 维度数据看板：焦段/光圈/快门/ISO/时段/画幅（进入时算一次，Tab 切换只重绘）
          StatsDashboard({ stats: this.profileStats })
          this.profileGearCards()
        } else {
          this.achievementWall()
        }
      }
    }
    .width('100%')
  }

  // ===== 版式（排版 + 边框）=====

  @Builder
  layoutTab() {
    Column({ space: 14 }) {
      // 版式页两段切换（页签级下划线式）：排版 | 边框
      SectionTabs({
        items: this.layoutSectionItems,
        selected: this.layoutSection,
        onPick: (v: number) => {
          this.layoutSection = v;
        }
      })
      if (this.layoutSection === 0) {
        this.styleTab()
      } else {
        this.frameTab()
      }
    }
    .width('100%')
  }

  private profileStartDate(): string {
    const d: Date = new Date(this.profileStats.firstExportTs);
    return `${d.getMonth() + 1}月${d.getDate()}日`;
  }

  @Builder
  profileHeaderCard() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text('我的摄影档案')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_main'))
        Blank()
        Text(`已解锁 ${unlockedCount(this.profileStats)}/${ACHIEVEMENTS.length}`)
          .fontSize(12)
          .fontColor($r('app.color.accent'))
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .backgroundColor($r('app.color.chip_bg'))
          .borderRadius(12)
          .onClick(() => {
            this.mineSection = 1;
          })
      }
      .width('100%')
      Text(`累计 ${this.profileStats.totalExports} 张 · 从 ${this.profileStartDate()} 开始`)
        .fontSize(12)
        .fontColor($r('app.color.text_hint'))
      Text(`连续记录 ${this.profileStats.streakDays} 天`)
        .fontSize(12)
        .fontColor($r('app.color.text_sub'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  profileGearCards() {
    Column({ space: 12 }) {
      Column({ space: 10 }) {
        Text('相机 TOP3')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_main'))
          .width('100%')
        this.profileTopList(topEntries(this.profileStats.cameraCounts, 3))
      }
      .width('100%')
      .padding(14)
      .borderRadius(12)
      .backgroundColor($r('app.color.field_bg'))

      Column({ space: 10 }) {
        Text('镜头 TOP3')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_main'))
          .width('100%')
        this.profileTopList(topEntries(this.profileStats.lensCounts, 3))
      }
      .width('100%')
      .padding(14)
      .borderRadius(12)
      .backgroundColor($r('app.color.field_bg'))
    }
    .width('100%')
  }

  @Builder
  profileTopList(entries: NameCount[]) {
    Column({ space: 8 }) {
      if (entries.length === 0) {
        Text('暂无数据')
          .fontSize(12)
          .fontColor($r('app.color.text_hint'))
          .width('100%')
      }
      ForEach(entries, (e: NameCount, idx: number) => {
        Row({ space: 8 }) {
          Text(`${idx + 1}`)
            .fontSize(11)
            .fontColor($r('app.color.text_hint'))
            .width(14)
          Text(e.name)
            .fontSize(13)
            .fontColor($r('app.color.text_sub'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(`${e.count} 次`)
            .fontSize(12)
            .fontColor($r('app.color.accent'))
        }
        .width('100%')
      }, (e: NameCount) => `${e.name}-${e.count}`)
    }
    .width('100%')
  }

  private achGroups(): AchGroup[] {
    const order: string[] = ['legend', 'gold', 'silver', 'bronze'];
    const titles: Record<string, string> = {
      'legend': '✦ 彩蛋成就', 'gold': '★ 金色成就', 'silver': '🥈 银色成就', 'bronze': '🥉 铜色成就'
    };
    const groups: AchGroup[] = [];
    for (const rarity of order) {
      const defs: AchievementDef[] = [];
      let unlocked: number = 0;
      for (const d of ACHIEVEMENTS) {
        if (d.rarity !== rarity) {
          continue;
        }
        defs.push(d);
        if (isUnlocked(this.profileStats, d.key)) {
          unlocked++;
        }
      }
      if (defs.length > 0) {
        const g: AchGroup = new AchGroup();
        g.title = titles[rarity];
        g.defs = defs;
        g.unlocked = unlocked;
        groups.push(g);
      }
    }
    return groups;
  }

  @Builder
  achievementWall() {
    Column({ space: 12 }) {
      ForEach(this.achGroups(), (g: AchGroup) => {
        Column({ space: 10 }) {
          Row({ space: 6 }) {
            Text(g.title)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_sub'))
            Text(`${g.unlocked}/${g.defs.length}`)
              .fontSize(11)
              .fontColor($r('app.color.text_hint'))
          }
          .width('100%')
          Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            ForEach(g.defs, (d: AchievementDef) => {
              this.achievementBadge(d)
            }, (d: AchievementDef) => `${d.key}-${this.isAchUnlocked(d) ? 'on' : 'off'}`)
          }
          .width('100%')
        }
        .width('100%')
      }, (g: AchGroup) => `${g.title}-${g.unlocked}`)
    }
    .width('100%')
  }

  private isAchUnlocked(d: AchievementDef): boolean {
    return isUnlocked(this.profileStats, d.key);
  }

  private achBadgeHint(d: AchievementDef): string {
    if (this.isAchUnlocked(d)) {
      return '已解锁';
    }
    if (d.hidden) {
      return '';
    }
    return d.progress(this.profileStats);
  }

  @Builder
  achievementBadge(d: AchievementDef) {
    Column({ space: 5 }) {
      if (this.isAchUnlocked(d)) {
        Image(achBadgeOf(d.key))
          .width(46)
          .height(46)
      } else if (d.hidden) {
        Image($r('app.media.badge_hidden'))
          .width(46)
          .height(46)
      } else {
        Image(achBadgeOf(d.key))
          .width(46)
          .height(46)
          .opacity(0.3)
      }
      Text(this.isAchUnlocked(d) || !d.hidden ? d.name : '???')
        .fontSize(11)
        .fontColor(this.isAchUnlocked(d) ? $r('app.color.text_main') : $r('app.color.text_hint'))
        .maxLines(1)
      Text(this.achBadgeHint(d))
        .fontSize(9)
        .fontColor($r('app.color.text_hint'))
        .maxLines(1)
    }
    .width('31%')
    .margin({ bottom: 8 })
    .onClick(() => {
      this.openAchDetail(d);
    })
  }

  private formatAchTime(ts: number): string {
    const d: Date = new Date(ts);
    const hh: string = d.getHours() < 10 ? `0${d.getHours()}` : `${d.getHours()}`;
    const mm: string = d.getMinutes() < 10 ? `0${d.getMinutes()}` : `${d.getMinutes()}`;
    return `${d.getFullYear()}.${d.getMonth() + 1}.${d.getDate()} ${hh}:${mm}`;
  }

  private achDetailDlg: CustomDialogController | undefined = undefined;

  private openAchDetail(d: AchievementDef): void {
    const s: ProfileStats = this.profileStats;
    const unlocked: boolean = isUnlocked(s, d.key);
    this.achDetailDlg = new CustomDialogController({
      builder: AchievementDetailDialog({
        def: d,
        unlocked: unlocked,
        unlockTime: unlocked ? this.formatAchTime(unlockTs(s, d.key)) : '',
        progressText: d.hidden ? '' : d.progress(s)
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true
    });
    this.achDetailDlg.open();
  }

  // ===== 成就解锁居中弹窗 =====

  private achRarityRank(r: string): number {
    if (r === 'legend') {
      return 3;
    }
    if (r === 'gold') {
      return 2;
    }
    if (r === 'silver') {
      return 1;
    }
    return 0;
  }

  // 多成就合并展示时挑稀有度最高的当主展示
  private achToastMain(): AchievementDef {
    if (this.achToastDefs.length === 0) {
      return new AchievementDef();
    }
    let main: AchievementDef = this.achToastDefs[0];
    for (const d of this.achToastDefs) {
      if (this.achRarityRank(d.rarity) > this.achRarityRank(main.rarity)) {
        main = d;
      }
    }
    return main;
  }

  private achToastHasLegend(): boolean {
    for (const d of this.achToastDefs) {
      if (d.rarity === 'legend') {
        return true;
      }
    }
    return false;
  }

  private achToastHasGold(): boolean {
    for (const d of this.achToastDefs) {
      if (d.rarity === 'gold' || d.rarity === 'legend') {
        return true;
      }
    }
    return false;
  }

  private achToastTitle(): string {
    const main: AchievementDef = this.achToastMain();
    if (this.achToastDefs.length > 1) {
      return `${main.name} 等 ${this.achToastDefs.length} 个成就`;
    }
    return main.name;
  }

  private achToastSubtitle(): string {
    if (this.achToastDefs.length > 1) {
      return `本次共解锁 ${this.achToastDefs.length} 个成就`;
    }
    return this.achToastMain().desc;
  }

  @Builder
  achievementToastCard() {
    // 外层渐变只作 1.5vp 描边光环；竖排布局类似「关于」弹窗，不使用百分比高度
    Column() {
      Column({ space: 14 }) {
        // 主徽章：稀有度渐变描环
        Stack() {
          Column()
            .width(64)
            .height(64)
            .borderRadius(32)
            .linearGradient(this.achToastHasLegend() ? {
              angle: 135,
              colors: [['#FF6B6B', 0], ['#FFD93D', 0.25], ['#6BCB77', 0.5], ['#4D96FF', 0.75], ['#B983FF', 1]]
            } : {
              angle: 135,
              colors: this.achToastHasGold() ? [['#FFE9A8', 0], ['#E0A93A', 1]] :
              [['#DDE2EC', 0], ['#C9D2E0', 1]]
            })
          Image(achBadgeOf(this.achToastMain().key))
            .width(64)
            .height(64)
        }
        .shadow(this.achToastHasLegend() ? { radius: 16, color: '#66B983FF', offsetX: 0, offsetY: 4 } :
          (this.achToastHasGold() ? { radius: 14, color: '#55D4A017', offsetX: 0, offsetY: 4 } :
          { radius: 8, color: '#1A000000', offsetX: 0, offsetY: 4 }))
        // 徽章在卡片弹起后弹跳浮现（更弹的弹簧，阻尼比约 0.55）
        .transition(TransitionEffect.asymmetric(
          TransitionEffect.scale({ x: 0.3, y: 0.3 })
            .combine(TransitionEffect.OPACITY)
            .animation({ delay: 120, duration: 420, curve: curves.springCurve(0, 1, 210, 16) }),
          TransitionEffect.IDENTITY
        ))

        Column({ space: 5 }) {
          Text('恭喜解锁成就')
            .fontSize(12)
            .fontColor($r('app.color.text_hint'))
          Text(this.achToastTitle())
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_main'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.achToastSubtitle())
            .fontSize(13)
            .fontColor($r('app.color.text_sub'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Center)
            .lineHeight(19)
        }
        .alignItems(HorizontalAlign.Center)
        // 文案紧随徽章上浮淡入
        .transition(TransitionEffect.asymmetric(
          TransitionEffect.translate({ y: 14 })
            .combine(TransitionEffect.OPACITY)
            .animation({ delay: 170, duration: 300, curve: Curve.FastOutSlowIn }),
          TransitionEffect.IDENTITY
        ))

        Text(this.achToastDefs.length > 1 ? '查看全部成就' : '查看档案')
          .fontSize(14)
          .fontColor($r('app.color.accent'))
          .padding({ left: 28, right: 28, top: 10, bottom: 10 })
          .backgroundColor($r('app.color.chip_bg'))
          .borderRadius(18)
          .onClick(() => {
            this.activeTab = 4;
            // 多成就合并卡 → 成就墙；单成就「查看档案」→ 统计
            this.mineSection = this.achToastDefs.length > 1 ? 1 : 0;
            this.dismissAchToast();
          })
          // 主按钮在文案之后浮起
          .transition(TransitionEffect.asymmetric(
            TransitionEffect.translate({ y: 12 })
              .combine(TransitionEffect.OPACITY)
              .animation({ delay: 230, duration: 280, curve: Curve.FastOutSlowIn }),
            TransitionEffect.IDENTITY
          ))

        Text('关闭')
          .fontSize(14)
          .fontColor($r('app.color.text_sub'))
          .padding({ top: 2, bottom: 2 })
          .onClick(() => {
            this.dismissAchToast();
          })
          .transition(TransitionEffect.asymmetric(
            TransitionEffect.translate({ y: 10 })
              .combine(TransitionEffect.OPACITY)
              .animation({ delay: 290, duration: 260, curve: Curve.FastOutSlowIn }),
            TransitionEffect.IDENTITY
          ))
      }
      .width('100%')
      .padding({ top: 24, bottom: 16, left: 24, right: 24 })
      .borderRadius(19)
      .backgroundColor($r('app.color.card_bg'))
      .alignItems(HorizontalAlign.Center)
    }
    .width(280)
    .padding(1.5)
    .borderRadius(21)
    .linearGradient(this.achToastHasLegend() ? {
      angle: 135,
      colors: [['#FF6B6B', 0], ['#FFD93D', 0.25], ['#6BCB77', 0.5], ['#4D96FF', 0.75], ['#B983FF', 1]]
    } : {
      angle: 135,
      colors: this.achToastHasGold() ? [['#FFE9A8', 0], ['#D4A017', 1]] :
      [['#EDF0F6', 0], ['#C9D2E0', 1]]
    })
    .shadow(this.achToastHasLegend() ? { radius: 30, color: '#80B983FF', offsetX: 0, offsetY: 8 } :
      (this.achToastHasGold() ? { radius: 24, color: '#66D4A017', offsetX: 0, offsetY: 6 } :
      { radius: 20, color: '#26000000', offsetX: 0, offsetY: 8 }))
    .onClick(() => {
      this.dismissAchToast();
    })
    .transition(TransitionEffect.asymmetric(
      // 入场：小尺寸弹起 + 上浮 + 淡入，弹簧曲线带轻微回弹（阻尼比约 0.73）
      TransitionEffect.scale({ x: 0.5, y: 0.5 })
        .combine(TransitionEffect.translate({ y: 30 }))
        .combine(TransitionEffect.OPACITY)
        .animation({ duration: 500, curve: curves.springCurve(0, 1, 170, 19) }),
      // 收起：轻微缩小下沉 + 淡出，轻快不拖沓
      TransitionEffect.scale({ x: 0.86, y: 0.86 })
        .combine(TransitionEffect.translate({ y: 10 }))
        .combine(TransitionEffect.OPACITY)
        .animation({ duration: 200, curve: Curve.EaseOut })
    ))
  }

  @Builder
  settingsTab() {
    Column({ space: 14 }) {
      Row({ space: 14 }) {
        Image($r('app.media.foreground'))
          .width(56)
          .height(56)
          .borderRadius(14)
        Column({ space: 4 }) {
          Text('印痕')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_main'))
          Text('让每一张照片，都留下相机的印记')
            .fontSize(12)
            .fontColor($r('app.color.text_hint'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding(14)
      .borderRadius(12)
      .backgroundColor($r('app.color.card_bg'))
      .border({ width: 1, color: $r('app.color.border_preset') })

      Text('皮肤')
        .fontSize(14)
        .fontColor($r('app.color.text_sub'))
        .width('100%')
      SegmentedControl({
        items: this.skinItems,
        selected: this.skinMode,
        even: true,
        onPick: (v: number) => {
          this.onSkinPick(v);
        }
      })

      Column({ space: 10 }) {
        Text('联系我们')
          .fontSize(14)
          .fontColor($r('app.color.text_sub'))
          .width('100%')
        Row() {
          Text(CONTACT_EMAIL)
            .fontSize(14)
            .fontColor($r('app.color.text_main'))
            .layoutWeight(1)
          Text('复制')
            .fontSize(13)
            .fontColor($r('app.color.accent'))
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            .backgroundColor($r('app.color.chip_bg'))
            .borderRadius(14)
            .onClick(() => {
              this.copyEmail();
            })
        }
        .width('100%')
      }
      .width('100%')
      .padding(14)
      .borderRadius(12)
      .backgroundColor($r('app.color.card_bg'))
      .border({ width: 1, color: $r('app.color.border_preset') })

      Row({ space: 10 }) {
        Text('运行日志')
          .fontSize(14)
          .fontColor($r('app.color.accent'))
          .padding({ top: 12, bottom: 12, left: 8, right: 8 })
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .borderRadius(12)
          .backgroundColor($r('app.color.card_bg'))
          .border({ width: 1, color: $r('app.color.border_preset') })
          .onClick(() => {
            router.pushUrl({ url: 'pages/LogViewer' });
          })

        Text(`清理缓存（${this.cacheText}）`)
          .fontSize(14)
          .fontColor($r('app.color.accent'))
          .padding({ top: 12, bottom: 12, left: 8, right: 8 })
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .borderRadius(12)
          .backgroundColor($r('app.color.card_bg'))
          .border({ width: 1, color: $r('app.color.border_preset') })
          .onClick(() => {
            this.cleanCache();
          })
      }
      .width('100%')

      Text('关于软件')
        .fontSize(14)
        .fontColor($r('app.color.accent'))
        .padding({ top: 12, bottom: 12 })
        .width('100%')
        .textAlign(TextAlign.Center)
        .borderRadius(12)
        .backgroundColor($r('app.color.card_bg'))
        .border({ width: 1, color: $r('app.color.border_preset') })
        .onClick(() => {
          this.aboutCtl.open();
        })
    }
    .width('100%')
  }

  @Builder
  headerBar() {
    Row() {
      Text('印痕')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_main'))
      Blank()
      Text('更换照片')
        .fontSize(14)
        .fontColor($r('app.color.accent'))
        .padding({ left: 14, right: 14, top: 6, bottom: 6 })
        .backgroundColor($r('app.color.chip_bg'))
        .borderRadius(14)
        .margin({ right: 8 })
        .onClick(() => {
          this.pickImage();
        })
      Text('重置')
        .fontSize(14)
        .fontColor($r('app.color.accent'))
        .padding({ left: 14, right: 14, top: 6, bottom: 6 })
        .backgroundColor($r('app.color.chip_bg'))
        .borderRadius(14)
        .onClick(() => {
          this.resetStyle();
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 6 })
    .geometryTransition('gt_header')
    .transition(TransitionEffect.OPACITY)
  }

  @Builder
  photoStrip() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.photoItems, (it: PhotoItem, idx: number) => {
          Stack({ alignContent: Alignment.TopEnd }) {
            Image(it.uri)
              .width(52)
              .height(52)
              .objectFit(ImageFit.Cover)
              .borderRadius(9)
              .border({
                width: idx === this.currentIdx ? 2 : 1,
                color: idx === this.currentIdx ? $r('app.color.accent') : $r('app.color.border_soft')
              })
              .autoResize(true)
              .interpolation(ImageInterpolation.Low)
            Text(`${idx + 1}`)
              .fontSize(10)
              .fontColor('#FFFFFF')
              .backgroundColor('#99000000')
              .borderRadius(8)
              .padding({ left: 4, right: 4, top: 1, bottom: 1 })
              .margin(3)
          }
          .width(52)
          .height(52)
          .onClick(() => {
            this.switchPhoto(idx);
          })
        }, (it: PhotoItem) => it.uri)
      }
      .padding({ left: 2, right: 2 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .margin({ top: 8, bottom: 12 })
  }

  @Builder
  previewArea() {
    Column() {
      if (this.pixelMap === undefined) {
        Column({ space: 10 }) {
          Text('＋')
            .fontSize(34)
            .fontColor($r('app.color.accent'))
            .fontWeight(FontWeight.Bold)
          Text('点击选择图片（支持多选）')
            .fontSize(16)
            .fontColor($r('app.color.accent'))
            .fontWeight(FontWeight.Medium)
          Text('自动读取相机参数，生成拍摄信息水印')
            .fontSize(12)
            .fontColor($r('app.color.text_hint'))
        }
        .width('100%')
        .height(this.hoverMode ? (this.hoverVertical ? this.winHVp * 0.5 : this.hoverCreaseTopVp * 0.5) :
          (this.isWide ? this.winHVp * 0.5 : this.screenHVp * 0.36))
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .borderRadius(16)
        .backgroundColor($r('app.color.card_bg'))
        .border({ width: 1.5, color: $r('app.color.divider_strong'), style: BorderStyle.Dashed })
        .onClick(() => {
          this.pickImage();
        })
      } else {
        Column() {
          if (this.saving || this.batchRunning) {
            Column({ space: 12 }) {
              LoadingProgress()
                .width(42)
                .height(42)
                .color($r('app.color.accent'))
              Text(this.batchRunning ? this.batchStatus : '正在导出...')
                .fontSize(14)
                .fontColor($r('app.color.text_hint'))
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else {
            Stack() {
            Column() {
              Column() {
                this.watermarkCanvas()
              }
              .shadow({ radius: 20, color: '#26000000', offsetY: 8 })
              .scale({ x: this.zoomScale, y: this.zoomScale })
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .translate({ x: this.zoomX, y: this.zoomY })
          }
          .width('100%')
          .layoutWeight(1)
          .clip(true)
          .onAreaChange((_o: Area, n: Area) => {
            const nw: number = Number(n.width);
            const nh: number = Number(n.height);
            if (Math.abs(nw - this.previewAreaW) > 0.5 || Math.abs(nh - this.previewAreaH) > 0.5) {
              this.previewAreaW = nw;
              this.previewAreaH = nh;
              this.resetZoom();
              this.refreshLayouts();
            }
          })
          .gesture(GestureGroup(GestureMode.Exclusive,
            PinchGesture({ fingers: 2 })
              .onActionStart(() => {
                this.pinchStartScale = this.zoomScale;
                this.pinchStartX = this.zoomX;
                this.pinchStartY = this.zoomY;
              })
              .onActionUpdate((e: GestureEvent) => {
                const ns: number = Math.min(Math.max(this.pinchStartScale * e.scale, 1), 5);
                this.zoomScale = ns;
                this.zoomX = this.clampZoomX(this.pinchStartX * (ns / this.pinchStartScale), ns);
                this.zoomY = this.clampZoomY(this.pinchStartY * (ns / this.pinchStartScale), ns);
              }),
            TapGesture({ count: 2 })
              .onAction((e: GestureEvent) => {
                if (this.zoomScale > 1) {
                  this.resetZoom();
                } else if (e.fingerList.length > 0) {
                  const ns: number = 2.5;
                  const fx: number = e.fingerList[0].localX;
                  const fy: number = e.fingerList[0].localY;
                  this.zoomX = this.clampZoomX((fx - this.previewAreaW / 2) * (1 - ns), ns);
                  this.zoomY = this.clampZoomY((fy - this.previewAreaH / 2) * (1 - ns), ns);
                  this.zoomScale = ns;
                }
              }),
            PanGesture({ fingers: 1, distance: 5 })
              .onActionStart(() => {
                this.panStartX = this.zoomX;
                this.panStartY = this.zoomY;
              })
              .onActionUpdate((e: GestureEvent) => {
                this.zoomX = this.clampZoomX(this.panStartX + e.offsetX, this.zoomScale);
                this.zoomY = this.clampZoomY(this.panStartY + e.offsetY, this.zoomScale);
              })
            ))
          }
          if (this.photoItems.length > 1) {
            this.photoStrip()
          }
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 16, right: 16 })
    .geometryTransition('gt_preview')
    .transition(TransitionEffect.OPACITY)
  }

  @Builder
  floatTabItem(idx: number) {
    Column() {
      Text(this.tabItems[idx].label)
        .fontSize(13)
        .fontWeight(this.activeTab === idx ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.activeTab === idx
          ? (this.barOverDark ? Color.White : Color.Black)
          : (this.barOverDark ? '#B3FFFFFF' : '#B3000000'))
    }
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .constraintSize({ minWidth: this.navStripNarrow() ? 56 : 0 })
  }

  @Builder
  tabBody(idx: number) {
    Column({ space: 14 }) {
      if (idx === 0) {
        this.presetsTab()
      } else if (idx === 1) {
        this.paramsTab()
      } else if (idx === 2) {
        this.layoutTab()
      } else if (idx === 3) {
        this.exportTab()
      } else {
        this.mineTab()
      }
    }
    .width('100%')
    .padding({ top: 16, bottom: 96, left: 16, right: 16 })
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.OPACITY
        .combine(TransitionEffect.scale({
          x: 0.68,
          y: 0.4,
          centerX: this.tabClickXPct,
          centerY: '100%'
        }))
        .animation({ duration: 300, curve: Curve.Friction }),
      TransitionEffect.OPACITY.animation({ duration: 120 })
    ))
  }

  @Builder
  panelHost(wide: boolean) {
    Scroll(this.panelScroller) {
      if (this.activeTab === 0) {
        this.tabBody(0)
      } else if (this.activeTab === 1) {
        this.tabBody(1)
      } else if (this.activeTab === 2) {
        this.tabBody(2)
      } else if (this.activeTab === 3) {
        this.tabBody(3)
      } else {
        this.tabBody(4)
      }
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .backgroundColor($r('app.color.card_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .shadow(wide ? { radius: 0, color: '#00000000', offsetY: 0 } :
      { radius: 24, color: '#14000000', offsetY: -6 })
    .id('panelScroll')
    .onAreaChange((_o: Area, n: Area) => {
      // 面板底=物理屏底（expandSafeArea），实际渲染高=窗口高-顶部位置，避免 area 是否含安全区扩展的歧义
      const gp: Position | undefined = n.globalPosition;
      const gy: number = gp !== undefined && gp.y !== undefined ? this.lenToVp(gp.y) : 0;
      this.panelScrollHVp = this.winHVp - gy;
    })
    // 导出页禁用底部渐变模糊：保存按钮是系统安全控件，祖先挂模糊效果会被静默拒绝授权
    .linearGradientBlur(40, this.navBarHidden || this.activeTab === 3 ? undefined : this.panelBlurOptions())
    .onAppear(() => {
      setTimeout(() => this.scheduleBarLumaCheck(true, wide), 300);
    })
    .onScroll(() => {
      this.handlePanelScroll();
      this.scheduleBarLumaCheck(false, wide);
    })
    .onScrollStop(() => {
      this.scheduleBarLumaCheck(true, wide);
    })
    .geometryTransition('gt_panel')
    .transition(TransitionEffect.OPACITY)
  }

  @Builder
  capsuleStrip(wide: boolean) {
    Stack({ alignContent: Alignment.Bottom }) {
      Tabs({ barPosition: BarPosition.End, index: this.activeTab }) {
      TabContent() {
        Column() {
        }
        .width('100%')
        .height('100%')
      }
      .tabBar(this.floatTabItem(0))
      TabContent() {
        Column() {
        }
        .width('100%')
        .height('100%')
      }
      .tabBar(this.floatTabItem(1))
      TabContent() {
        Column() {
        }
        .width('100%')
        .height('100%')
      }
      .tabBar(this.floatTabItem(2))
      TabContent() {
        Column() {
        }
        .width('100%')
        .height('100%')
      }
      .tabBar(this.floatTabItem(3))
      TabContent() {
        Column() {
        }
        .width('100%')
        .height('100%')
      }
      .tabBar(this.floatTabItem(4))
    }
    .width(wide ? '100%' : this.portraitCapsuleW())
    // 容器高度必须=胶囊可视区（条高56+底距14），不能加 navBarH：下移入安全区由 translate 补偿，
    // Tabs 内部 Swiper 会消费整个容器区域的触摸，容器高出可见胶囊的部分会成为隐形死区，
    // 导致其上方按钮点击无效（保存至图库按钮授权失败）
    .height(70)
    .vertical(false)
    .barMode(this.navStripNarrow() ? BarMode.Scrollable : BarMode.Fixed)
    .barOverlap(true)
    .scrollable(false)
    .animationDuration(0)
    .id('capsuleTabs')
    .barFloatingStyle({
      barSideMargin: wide ? this.wideBarSideMargin() : 0,
      barBottomMargin: 14,
      maskColor: Color.Transparent,
      systemMaterial: this.floatBarMaterial
    })
    .onChange((i: number) => {
      if (i !== this.activeTab) {
        this.updateTabClickXPct(i, wide);
        this.getUIContext().animateTo({ duration: 300, curve: Curve.Friction }, () => {
          this.activeTab = i;
        });
        this.panelScroller.scrollEdge(Edge.Top);
        this.lastPanelScrollY = 0;
        this.setNavBarHidden(false);
        if (i === 4) {
          this.refreshCacheSize();
        }
        setTimeout(() => this.scheduleBarLumaCheck(true, false), 400);
      }
    })

      // 胶囊描边层：与系统胶囊同宽（floatBarWVp），Stack 底部对齐天然居中，边框贴合胶囊轮廓
      Row() {
      }
      .width(this.floatBarWVp(wide))
      .height(56)
      .borderRadius(28)
      .border({
        width: 1,
        color: this.barOverDark ? '#80FFFFFF' : '#33000000'
      })
      .margin({ bottom: 14 })
      .hitTestBehavior(HitTestMode.None)
    }
    .margin({ left: wide ? 0 : this.capsuleStripLeftMargin() })
    // 条整体下移入底部安全区（条底=物理屏底-14vp）；隐藏时继续下移完全出屏
    .translate({ y: this.navBarHidden ? this.canvasSafeDrop() + this.navBarH : this.navBarH })
    .opacity(this.navBarHidden ? 0 : 1)
    .hitTestBehavior(this.navBarHidden ? HitTestMode.None : HitTestMode.Default)
    .transition(TransitionEffect.OPACITY)
    .onAreaChange((_o: Area, n: Area) => {
      this.stripWVp = this.lenToVp(n.width);
    })
  }

  // 隐藏导航条时向下平移的距离：完整移出安全区底部
  private canvasSafeDrop(): number {
    return this.navBarH + 96;
  }

  @Builder
  menuPane() {
    Stack({ alignContent: Alignment.BottomStart }) {
      Column() {
        Column() {
          this.headerBar()
        }
        .width('100%')
        .padding({ top: this.statusBarH })
        this.panelHost(true)
      }
      .width('100%')
      .height('100%')
      this.capsuleStrip(true)
    }
    .width((this.paneRatio * 100).toFixed(1) + '%')
    .height('100%')
  }

  @Builder
  paneDivider() {
    Column() {
      Column()
        .width(4)
        .height(44)
        .borderRadius(2)
        .backgroundColor($r('app.color.divider_strong'))
    }
    .width(14)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .geometryTransition('gt_divider')
    .transition(TransitionEffect.OPACITY.animation({ duration: 300 }))
    .gesture(
      PanGesture({ fingers: 1, distance: 2 })
        .onActionStart(() => {
          this.paneDragStart = this.paneRatio;
        })
        .onActionUpdate((e: GestureEvent) => {
          const nr: number = this.paneDragStart + e.offsetX / this.winWVp;
          const minR: number = 260 / this.winWVp;
          const maxR: number = Math.min(350, this.winWVp * 0.62) / this.winWVp;
          this.paneRatio = Math.min(maxR, Math.max(minR, nr));
          const menuW: number = this.paneRatio * this.winWVp;
          this.presetSingleCol = this.isWide && menuW < 290;
        })
    )
  }

  @Builder
  hoverPickerBody() {
    PhotoPickerComponent({
      pickerOptions: this.hoverPickerOptions,
      pickerController: this.hoverPickerController,
      onSelect: (uri: string) => {
        this.hoverPickUris.push(uri);
        this.hoverPickCount = this.hoverPickUris.length;
      },
      onDeselect: (uri: string) => {
        const idx: number = this.hoverPickUris.indexOf(uri);
        if (idx >= 0) {
          this.hoverPickUris.splice(idx, 1);
        }
        this.hoverPickCount = this.hoverPickUris.length;
      }
    })
    .width('100%')
    .layoutWeight(1)

    Row() {
      Text(`已选 ${this.hoverPickCount} 张`)
        .fontSize(14)
        .fontColor($r('app.color.text_sub'))
      Blank()
      Text('完成')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.accent'))
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .backgroundColor($r('app.color.chip_bg'))
        .borderRadius(18)
        .onClick(() => {
          this.confirmHoverPick();
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
  }

  @Builder
  hoverPickerSheet() {
    Column() {
      this.hoverPickerBody()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  hoverPickerInline() {
    Column() {
      Row() {
        Text('选择图片')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_main'))
        Blank()
        Text('✕')
          .fontSize(16)
          .fontColor($r('app.color.text_sub'))
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .onClick(() => {
            this.hoverPickerInlineShow = false;
            this.hoverPickUris = [];
            this.hoverPickCount = 0;
          })
      }
      .width('100%')
      .padding({ left: 16, right: 8, top: this.statusBarH + 8, bottom: 4 })

      this.hoverPickerBody()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
  }

  private hoverMenuPaneW(): number {
    return this.hoverMenuLeft ? this.hoverCreaseLeftVp :
      this.winWVp - this.hoverCreaseLeftVp - this.hoverCreaseW;
  }

  @Builder
  hoverMenuPane() {
    Stack({ alignContent: Alignment.BottomStart }) {
      Column() {
        Column() {
          this.headerBar()
        }
        .width('100%')
        .padding({ top: this.statusBarH, bottom: 6 })
        this.panelHost(true)
      }
      .width('100%')
      .height('100%')

      this.capsuleStrip(true)

      if (this.hoverPickerInlineShow) {
        this.hoverPickerInline()
      }
    }
    .width(this.hoverMenuPaneW())
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
  }

  build() {
    Stack() {
      if (this.hoverMode && this.hoverVertical) {
        Row() {
          if (!this.hoverMenuLeft) {
            Column() {
              this.previewArea()
            }
            .layoutWeight(1)
            .height('100%')
            .margin({ right: this.hoverCreaseW })
            .padding({ top: this.statusBarH, bottom: 16 + this.navBarH })
            .backgroundColor($r('app.color.pane_bg'))

            this.hoverMenuPane()
          } else {
            this.hoverMenuPane()

            Column() {
              this.previewArea()
            }
            .layoutWeight(1)
            .height('100%')
            .margin({ left: this.hoverCreaseW })
            .padding({ top: this.statusBarH, bottom: 16 + this.navBarH })
            .backgroundColor($r('app.color.pane_bg'))
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.page_bg'))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      } else if (this.hoverMode) {
        Column() {
          Column() {
            this.previewArea()
          }
          .width('100%')
          .height(this.hoverCreaseTopVp)
          .padding({ top: this.statusBarH, bottom: 16 })
          .backgroundColor($r('app.color.pane_bg'))

          Stack({ alignContent: Alignment.BottomStart }) {
            Column() {
              Column() {
                this.headerBar()
              }
              .width('100%')
              .padding({ top: this.hoverCreaseH * 0.5 + 4, bottom: 6 })
              this.panelHost(true)
            }
            .width('100%')
            .height('100%')

            this.capsuleStrip(true)
          }
          .width('100%')
          .layoutWeight(1)
          .backgroundColor($r('app.color.page_bg'))
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.page_bg'))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      } else if (this.isWide) {
        Row() {
          this.menuPane()

          this.paneDivider()

          Column() {
            this.previewArea()
          }
          .layoutWeight(1)
          .height('100%')
          .padding({ top: this.statusBarH, bottom: 16 + this.navBarH })
          .backgroundColor($r('app.color.pane_bg'))
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.page_bg'))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      } else {
        Stack({ alignContent: Alignment.BottomStart }) {
          Column() {
            Column() {
              this.headerBar()
            }
            .width('100%')
            .padding({ top: this.statusBarH })

            Column() {
              this.previewArea()
            }
            .width('100%')
            .height(this.winHVp * 0.44)

            this.panelHost(false)
          }
          .width('100%')
          .height('100%')

          this.capsuleStrip(false)
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.page_bg'))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      }

      if (this.saving || this.batchRunning) {
        Column({ space: 12 }) {
          LoadingProgress()
            .width(40)
            .height(40)
            .color('#FFFFFF')
          Text(this.batchRunning ? this.batchStatus : '正在生成并保存...')
            .fontSize(14)
            .fontColor('#FFFFFF')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('#B3000000')
      }

      if (this.achToastShow) {
        Stack({ alignContent: Alignment.Center }) {
          this.achievementToastCard()
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .bindSheet($$this.hoverPickerShow, this.hoverPickerSheet(), {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      title: { title: '选择图片' },
      showClose: true,
      enableHoverMode: true,
      hoverModeArea: HoverModeAreaType.BOTTOM_SCREEN
    })
  }
}

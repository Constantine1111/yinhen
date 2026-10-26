import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { picker, fileIo } from '@kit.CoreFileKit';
import { Logger, LogEntry } from '../utils/Logger';

const LEVEL_LABELS: string[] = ['INFO', 'WARN', 'ERROR'];
const LEVEL_COLORS: ResourceColor[] = [
  $r('app.color.text_sub'),
  $r('app.color.accent'),
  Color.Red
];

@Entry
@Component
struct LogViewer {
  @State entries: LogEntry[] = [];
  @State toastText: string = '';
  @State toastVisible: boolean = false;

  aboutToAppear(): void {
    this.reload();
  }

  private reload(): void {
    const all: LogEntry[] = Logger.getEntries();
    const list: LogEntry[] = [];
    for (let i = all.length - 1; i >= 0; i--) {
      list.push(all[i]);
    }
    this.entries = list;
  }

  private toast(msg: string): void {
    this.toastText = msg;
    this.toastVisible = true;
  }

  private copyAll(): void {
    const all: LogEntry[] = Logger.getEntries();
    let text: string = '';
    for (let i = 0; i < all.length; i++) {
      const e: LogEntry = all[i];
      text += `${e.time} ${LEVEL_LABELS[e.level]} ${e.msg}\n`;
    }
    if (text.length === 0) {
      this.toast('暂无日志可复制');
      return;
    }
    const data: pasteboard.PasteData =
      pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      this.toast(`已复制 ${all.length} 条日志`);
    }).catch(() => {
      this.toast('复制失败，请重试');
    });
  }

  private clearLogs(): void {
    Logger.clear();
    this.reload();
    this.toast('日志已清空');
  }

  private async exportLogs(): Promise<void> {
    const all: LogEntry[] = Logger.getEntries();
    if (all.length === 0) {
      this.toast('暂无日志可导出');
      return;
    }
    let text: string = '';
    for (let i = 0; i < all.length; i++) {
      const e: LogEntry = all[i];
      text += `${e.time} ${LEVEL_LABELS[e.level]} ${e.msg}\n`;
    }
    try {
      const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const d: Date = new Date();
      const p2: (n: number) => string = (n: number): string => {
        return n < 10 ? `0${n}` : `${n}`;
      };
      const name: string = `yinhen-log-${d.getFullYear()}${p2(d.getMonth() + 1)}${p2(d.getDate())}` +
        `-${p2(d.getHours())}${p2(d.getMinutes())}${p2(d.getSeconds())}.txt`;
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx);
      const opts: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      opts.newFileNames = [name];
      const uris: string[] = await docPicker.save(opts);
      if (uris.length === 0) {
        this.toast('已取消导出');
        return;
      }
      const file: fileIo.File = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE);
      fileIo.writeSync(file.fd, text);
      fileIo.closeSync(file);
      this.toast(`已导出 ${all.length} 条日志`);
    } catch (err) {
      this.toast(`导出失败: ${JSON.stringify(err)}`);
    }
  }

  build() {
    Column() {
      Row() {
        Text('返回')
          .fontSize(16)
          .fontColor($r('app.color.accent'))
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .onClick(() => {
            router.back();
          })

        Text('运行日志')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_main'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Text('复制')
          .fontSize(16)
          .fontColor($r('app.color.accent'))
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .onClick(() => {
            this.copyAll();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column() {
          if (this.entries.length === 0) {
            Text('暂无日志')
              .fontSize(14)
              .fontColor($r('app.color.text_hint'))
              .margin({ top: 80 })
          } else {
            ForEach(this.entries, (e: LogEntry, idx: number) => {
              Row({ space: 6 }) {
                Text(e.time)
                  .fontSize(11)
                  .fontColor($r('app.color.text_hint'))
                  .fontFamily('monospace')
                Text(LEVEL_LABELS[e.level])
                  .fontSize(10)
                  .fontColor(LEVEL_COLORS[e.level])
                  .fontFamily('monospace')
                  .constraintSize({ minWidth: 40 })
                Text(e.msg)
                  .fontSize(11)
                  .fontColor(e.level === 2 ? Color.Red : $r('app.color.text_main'))
                  .fontFamily('monospace')
                  .layoutWeight(1)
                  .lineHeight(16)
              }
              .alignItems(VerticalAlign.Top)
              .width('100%')
              .padding({ left: 12, right: 12, top: 5, bottom: 5 })
            }, (e: LogEntry, idx: number) => `${idx}-${e.time}-${e.msg.length}`)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Auto)

      Row({ space: 10 }) {
        Text('导出')
          .fontSize(14)
          .fontColor($r('app.color.accent'))
          .padding({ top: 10, bottom: 10, left: 8, right: 8 })
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .borderRadius(12)
          .backgroundColor($r('app.color.card_bg'))
          .border({ width: 1, color: $r('app.color.border_preset') })
          .onClick(() => {
            this.exportLogs();
          })

        Text('刷新')
          .fontSize(14)
          .fontColor($r('app.color.accent'))
          .padding({ top: 10, bottom: 10, left: 8, right: 8 })
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .borderRadius(12)
          .backgroundColor($r('app.color.card_bg'))
          .border({ width: 1, color: $r('app.color.border_preset') })
          .onClick(() => {
            this.reload();
            this.toast('已刷新');
          })

        Text('清空日志')
          .fontSize(14)
          .fontColor($r('app.color.accent'))
          .padding({ top: 10, bottom: 10, left: 8, right: 8 })
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .borderRadius(12)
          .backgroundColor($r('app.color.card_bg'))
          .border({ width: 1, color: $r('app.color.border_preset') })
          .onClick(() => {
            this.clearLogs();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 12 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .bindPopup(this.toastVisible, {
      message: this.toastText,
      placement: Placement.Top,
      onStateChange: (s: PopupStateChangeParam) => {
        if (!s.isVisible) {
          this.toastVisible = false;
        }
      }
    })
  }
}

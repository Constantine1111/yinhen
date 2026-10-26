import { webview } from '@kit.ArkWeb';
import { router } from '@kit.ArkUI';

const PRIVACY_URL: string =
  'https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=2060333221651995328';

@Entry
@Component
struct WebViewer {
  controller: webview.WebviewController = new webview.WebviewController();

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

        Text('隐私协议')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_main'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Row()
          .width(64)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Web({ src: PRIVACY_URL, controller: this.controller })
        .width('100%')
        .layoutWeight(1)
        .backgroundColor($r('app.color.pane_bg'))
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
  }
}

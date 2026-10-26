export class SegmentItem {
  label: string = '';
  value: number = 0;

  constructor(label: string, value: number) {
    this.label = label;
    this.value = value;
  }
}


@Component
export struct SegmentedControl {
  items: SegmentItem[] = [];
  @Prop selected: number = 0;
  even: boolean = false;
  bgTransparent: boolean = false;
  onPick: (v: number) => void = () => {
  };

  build() {
    Scroll() {
      Row({ space: this.even ? 8 : 4 }) {
        ForEach(this.items, (item: SegmentItem) => {
          Text(item.label)
            .fontSize(13)
            .fontColor(this.selected === item.value ? '#FFFFFF' : $r('app.color.text_sub'))
            .fontWeight(this.selected === item.value ? FontWeight.Medium : FontWeight.Normal)
            .backgroundColor(this.selected === item.value ? $r('app.color.accent') :
              (this.bgTransparent ? Color.Transparent : $r('app.color.chip_bg')))
            .borderRadius(15)
            .padding({ left: this.even ? 0 : 14, right: this.even ? 0 : 14, top: 7, bottom: 7 })
            .layoutWeight(this.even ? 1 : 0)
            .textAlign(TextAlign.Center)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .onClick(() => {
              this.onPick(item.value);
            })
        }, (item: SegmentItem) => `${item.label}-${item.value}`)
      }
      .width(this.even ? '100%' : 'auto')
      .padding(4)
      .constraintSize({ minWidth: '100%' })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .backgroundColor(this.bgTransparent ? Color.Transparent : $r('app.color.chip_bg'))
    .borderRadius(19)
  }
}

@Component
export struct LabeledSlider {
  label: string = '';
  @Prop value: number = 0;
  min: number = 0;
  max: number = 100;
  step: number = 1;
  unit: string = '';
  onValue: (v: number) => void = () => {
  };

  build() {
    Column({ space: 2 }) {
      Row() {
        Text(this.label)
          .fontSize(14)
          .fontColor($r('app.color.text_sub'))
        Blank()
        Text(`${Math.round(this.value)}${this.unit}`)
          .fontSize(13)
          .fontColor($r('app.color.accent'))
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')

      Slider({ value: this.value, min: this.min, max: this.max, step: this.step })
        .width('100%')
        .selectedColor($r('app.color.accent'))
        .trackColor($r('app.color.seg_track'))
        .blockColor($r('app.color.accent'))
        .onChange((value: number, mode: SliderChangeMode) => {
          this.onValue(value);
        })
    }
    .width('100%')
  }
}

@Component
export struct ColorSwatches {
  label: string = '';
  @Prop selected: string = '';
  colors: string[] = [];
  onPick: (c: string) => void = () => {
  };

  build() {
    Column({ space: 8 }) {
      Text(this.label)
        .fontSize(14)
        .fontColor($r('app.color.text_sub'))
        .width('100%')

      Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(this.colors, (c: string) => {
          Stack() {
            Circle({ width: 28, height: 28 })
              .fill(c)
              .stroke($r('app.color.border_soft'))
              .strokeWidth(1)
            if (this.selected === c) {
              Circle({ width: 34, height: 34 }).fill(Color.Transparent).stroke($r('app.color.accent')).strokeWidth(2.5)
            }
          }
          .width(40)
          .height(40)
          .margin({ right: 6, bottom: 4 })
          .onClick(() => {
            this.onPick(c);
          })
        }, (c: string) => c)
      }
      .width('100%')
    }
    .width('100%')
  }
}

@Component
export struct Grid9Picker {
  @Prop selected: number = 4;
  onPick: (pos: number) => void = () => {
  };

  build() {
    Grid() {
      ForEach([0, 1, 2, 3, 4, 5, 6, 7, 8], (pos: number) => {
        GridItem() {
          Column() {
            Column()
              .width(18)
              .height(18)
              .borderRadius(5)
              .backgroundColor(this.selected === pos ? $r('app.color.accent') : $r('app.color.seg_item'))
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .onClick(() => {
            this.onPick(pos);
          })
        }
      }, (pos: number) => `pos-${pos}`)
    }
    .columnsTemplate('1fr 1fr 1fr')
    .rowsTemplate('1fr 1fr 1fr')
    .width(126)
    .height(126)
    .backgroundColor($r('app.color.field_bg'))
    .borderRadius(12)
    .padding(8)
  }
}

@Component
export struct ToggleRow {
  label: string = '';
  @Prop isOn: boolean = false;
  onToggle: (on: boolean) => void = () => {
  };

  build() {
    Row() {
      Text(this.label)
        .fontSize(14)
        .fontColor($r('app.color.text_main'))
      Blank()
      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .selectedColor($r('app.color.accent'))
        .onChange((isOn: boolean) => {
          this.onToggle(isOn);
        })
    }
    .width('100%')
  }
}

@Component
export struct FieldRow {
  label: string = '';
  @Prop value: string = '';
  hint: string = '';
  @Prop checked: boolean = true;
  checkable: boolean = true;
  onChange: (v: string) => void = () => {
  };
  onCheck: (on: boolean) => void = () => {
  };

  build() {
    Row({ space: 10 }) {
      if (this.checkable) {
        Checkbox({ name: this.label })
          .select(this.checked)
          .selectedColor($r('app.color.accent'))
          .width(20)
          .height(20)
          .onChange((on: boolean) => {
            this.onCheck(on);
          })
      }
      Text(this.label)
        .fontSize(13)
        .fontColor($r('app.color.text_sub'))
        .width(72)
      TextInput({ text: this.value, placeholder: this.hint })
        .fontSize(14)
        .fontColor($r('app.color.text_main'))
        .placeholderColor($r('app.color.placeholder'))
        .placeholderFont({ size: 13 })
        .backgroundColor($r('app.color.field_bg'))
        .borderRadius(10)
        .height(40)
        .padding({ left: 12, right: 12 })
        .layoutWeight(1)
        .maxLength(40)
        .onChange((v: string) => {
          this.onChange(v);
        })
    }
    .width('100%')
    .opacity(!this.checkable || this.checked ? 1 : 0.5)
  }
}

@Component
export struct PickChips {
  items: SegmentItem[] = [];
  @Prop maskBits: number = 0;
  onToggle: (bit: number, on: boolean) => void = () => {
  };

  build() {
    Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
      ForEach(this.items, (it: SegmentItem) => {
        Text(it.label)
          .fontSize(13)
          .fontColor((this.maskBits & it.value) !== 0 ? $r('app.color.accent') : $r('app.color.text_sub'))
          .fontWeight((this.maskBits & it.value) !== 0 ? FontWeight.Medium : FontWeight.Normal)
          .border({ width: 1.2, color: (this.maskBits & it.value) !== 0 ? $r('app.color.accent') : $r('app.color.border_soft') })
          .backgroundColor((this.maskBits & it.value) !== 0 ? $r('app.color.chip_sel_bg') : '#00000000')
          .borderRadius(15)
          .padding({ left: 13, right: 13, top: 6, bottom: 6 })
          .margin({ right: 8, bottom: 8 })
          .onClick(() => {
            this.onToggle(it.value, (this.maskBits & it.value) === 0);
          })
      }, (it: SegmentItem) => `${it.label}-${it.value}`)
    }
    .width('100%')
  }
}

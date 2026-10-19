import { DeviceIcon, getIconText } from '../../mi/types';

@Entry
@Component
struct ElevatorWidget {
  @LocalStorageProp('isOn') isOn: boolean = false;
  @LocalStorageProp('isOffline') isOffline: boolean = false;
  @LocalStorageProp('did') did: string = '';
  @LocalStorageProp('siid') siid: number = 2;
  @LocalStorageProp('piid') piid: number = 1;
  @LocalStorageProp('deviceName') deviceName: string = '';
  @LocalStorageProp('iconType') iconType: number = DeviceIcon.Generic;
  @LocalStorageProp('statusText') statusText: string = '\u52A0\u8F7D\u4E2D...';
  @LocalStorageProp('dimension') dimension: string = '2*2';

  build() {
    Column() {
      if (this.dimension === '1*2') {
        this.buildSmallCard()
      } else if (this.dimension === '2*2') {
        this.buildMediumCard()
      } else if (this.dimension === '2*4') {
        this.buildWideCard()
      } else {
        this.buildLargeCard()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.getCardBgColor())
  }

  private isUnbound(): boolean {
    return this.did.length === 0;
  }

  private getCardBgColor(): string {
    if (this.isUnbound()) {
      return '#F5F5F5';
    }
    return this.getBgColor();
  }

  private getIconColor(): string {
    if (this.isOffline) {
      return '#E57373';
    }
    if (this.isUnbound()) {
      return '#9E9E9E';
    }
    return this.isOn ? '#2E7D32' : '#757575';
  }

  private getStatusColor(): string {
    if (this.isOffline) {
      return '#E57373';
    }
    if (this.isUnbound()) {
      return '#BDBDBD';
    }
    return this.isOn ? '#4CAF50' : '#9E9E9E';
  }

  private getBgColor(): string {
    if (this.isOffline) {
      return '#FFEBEE';
    }
    return this.isOn ? '#C8E6C9' : '#EEEEEE';
  }

  private getDisplayIcon(): string {
    if (this.isUnbound()) {
      return '+';
    }
    return getIconText(this.iconType);
  }

  private getDisplayName(): string {
    if (this.isUnbound()) {
      return '\u70B9\u51FB\u5173\u8054\u8BBE\u5907';
    }
    return this.deviceName;
  }

  private getDisplayStatus(): string {
    if (this.isUnbound()) {
      return '\u70B9\u51FB\u6DFB\u52A0\u8BBE\u5907';
    }
    return this.statusText;
  }

  @Builder
  buildSmallCard() {
    Row() {
      Text(this.getDisplayIcon())
        .fontSize(this.isUnbound() ? 30 : 24)
        .fontColor(this.getIconColor())
        .margin({ left: 12, right: 8 })
      Column() {
        Text(this.getDisplayName())
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.isUnbound() ? '#757575' : '#333333')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.getDisplayStatus())
          .fontSize(10)
          .fontColor(this.getStatusColor())
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .padding({ right: 8 })
    }
    .width('100%')
    .height('100%')
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.handleCardClick();
    })
  }

  @Builder
  buildMediumCard() {
    Column() {
      Text(this.getDisplayIcon())
        .fontSize(this.isUnbound() ? 38 : 32)
        .fontColor(this.getIconColor())
        .margin({ top: 12, bottom: 6 })

      Text(this.getDisplayName())
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.isUnbound() ? '#757575' : '#333333')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('85%')
        .textAlign(TextAlign.Center)

      Text(this.getDisplayStatus())
        .fontSize(11)
        .fontColor(this.getStatusColor())
        .margin({ top: 4, bottom: 10 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.handleCardClick();
    })
  }

  @Builder
  buildWideCard() {
    Row() {
      Text(this.getDisplayIcon())
        .fontSize(this.isUnbound() ? 44 : 36)
        .fontColor(this.getIconColor())
        .margin({ left: 16, right: 14 })

      Column() {
        Text(this.getDisplayName())
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.isUnbound() ? '#757575' : '#333333')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.getDisplayStatus())
          .fontSize(13)
          .fontColor(this.getStatusColor())
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .padding({ right: 16 })
    }
    .width('100%')
    .height('100%')
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.handleCardClick();
    })
  }

  @Builder
  buildLargeCard() {
    Column() {
      Text(this.getDisplayIcon())
        .fontSize(this.isUnbound() ? 56 : 48)
        .fontColor(this.getIconColor())
        .margin({ top: 20, bottom: 8 })

      Text(this.getDisplayName())
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.isUnbound() ? '#757575' : '#333333')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('80%')
        .textAlign(TextAlign.Center)

      Text(this.getDisplayStatus())
        .fontSize(14)
        .fontColor(this.getStatusColor())
        .margin({ top: 6, bottom: 16 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.handleCardClick();
    })
  }

  private handleCardClick(): void {
    if (this.isUnbound()) {
      postCardAction(this, {
        'action': 'router',
        'bundleName': 'com.miio.control',
        'moduleName': 'entry',
        'abilityName': 'WidgetEditAbility'
      });
      return;
    }
    this.sendToggleMessage();
  }

  private sendToggleMessage(): void {
    postCardAction(this, {
      'action': 'message',
      'params': {
        'method': 'toggle',
        'did': this.did,
        'siid': this.siid,
        'piid': this.piid
      }
    });
  }
}
import { DeviceIcon, getIconText } from '../../mi/types';
import { StatusTexts } from '../../common/StatusTexts';

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
  @LocalStorageProp('statusText') statusText: string = StatusTexts.loading;
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

  private getCardBgColor(): ResourceColor {
    if (this.isUnbound()) {
      return $r('app.color.unbound_bg');
    }
    return this.getBgColor();
  }

  private getIconColor(): ResourceColor {
    if (this.isOffline) {
      return $r('app.color.offline_red');
    }
    if (this.isUnbound()) {
      return $r('app.color.status_off');
    }
    return this.isOn ? $r('app.color.icon_on') : $r('app.color.icon_off');
  }

  private getStatusColor(): ResourceColor {
    if (this.isOffline) {
      return $r('app.color.offline_red');
    }
    if (this.isUnbound()) {
      return $r('app.color.text_disabled');
    }
    return this.isOn ? $r('app.color.status_on') : $r('app.color.status_off');
  }

  private getBgColor(): ResourceColor {
    if (this.isOffline) {
      return $r('app.color.card_offline_bg');
    }
    return this.isOn ? $r('app.color.card_on_bg') : $r('app.color.card_off_bg');
  }

  private getDisplayIcon(): string {
    if (this.isUnbound()) {
      return '+';
    }
    return getIconText(this.iconType);
  }

  private getDisplayName(): ResourceStr {
    if (this.isUnbound()) {
      return $r('app.string.widget_link_device');
    }
    return this.deviceName;
  }

  private getDisplayStatus(): ResourceStr {
    if (this.isUnbound()) {
      return $r('app.string.widget_add_device_hint');
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
          .fontColor(this.isUnbound() ? $r('app.color.icon_off') : $r('app.color.text_primary'))
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
      Column() {
        Text(this.getDisplayIcon())
          .fontSize(this.isUnbound() ? 38 : 32)
          .fontColor(this.getIconColor())
      }
      .height(46)
      .justifyContent(FlexAlign.Center)
      .margin({ top: 12, bottom: 6 })

      Text(this.getDisplayName())
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.isUnbound() ? $r('app.color.icon_off') : $r('app.color.text_primary'))
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
      Column() {
        Text(this.getDisplayIcon())
          .fontSize(this.isUnbound() ? 44 : 36)
          .fontColor(this.getIconColor())
      }
      .width(56)
      .height(56)
      .justifyContent(FlexAlign.Center)
      .margin({ left: 16, right: 14 })

      Column() {
        Text(this.getDisplayName())
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.isUnbound() ? $r('app.color.icon_off') : $r('app.color.text_primary'))
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
      Column() {
        Text(this.getDisplayIcon())
          .fontSize(this.isUnbound() ? 56 : 48)
          .fontColor(this.getIconColor())
      }
      .height(64)
      .justifyContent(FlexAlign.Center)
      .margin({ top: 20, bottom: 8 })

      Text(this.getDisplayName())
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.isUnbound() ? $r('app.color.icon_off') : $r('app.color.text_primary'))
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

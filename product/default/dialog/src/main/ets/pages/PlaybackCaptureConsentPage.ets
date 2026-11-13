import { PlaybackCaptureConsent } from '../common/PlaybackCaptureConsent';

const entryOptions: EntryOptions = { useSharedStorage: true };

@Entry(entryOptions)
@Component
struct PlaybackCaptureConsentPage {
  @LocalStorageProp('consentId') consentId: string = '';
  @LocalStorageProp('bundle') bundle: string = '';
  @State private decided: boolean = false;
  private choose(allow: boolean, reason: string): void {
    if (this.decided) { return; }
    this.decided = true; PlaybackCaptureConsent.find(this.consentId)?.decide(allow, reason);
  }
  onBackPress(): boolean { this.choose(false, 'back'); return true; }
  aboutToDisappear(): void { this.choose(false, 'disappear'); }
  build() {
    Column() {
      Column({ space: 16 }) {
        Text($r('app.string.playback_consent579_title')).fontSize(22).fontWeight(FontWeight.Bold)
        Text(this.bundle).id('playback-consent-app').fontSize(16)
        Text($r('app.string.playback_consent579_message')).fontSize(16)
        Row({ space: 16 }) {
          Button($r('app.string.playback_consent579_deny')).id('playback-consent-deny').enabled(!this.decided)
            .onClick((): void => { this.choose(false, 'button'); })
          Button($r('app.string.playback_consent579_allow')).id('playback-consent-allow').enabled(!this.decided)
            .onClick((): void => { this.choose(true, 'button'); })
        }.width('100%').justifyContent(FlexAlign.SpaceEvenly)
      }.width('90%').constraintSize({ maxWidth: 600 }).padding(24).backgroundColor(Color.White).borderRadius(24)
    }.width('100%').height('100%').justifyContent(FlexAlign.Center).backgroundColor('#66000000')
  }
}

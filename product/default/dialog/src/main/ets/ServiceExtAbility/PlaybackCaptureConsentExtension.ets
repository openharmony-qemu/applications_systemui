import UIExtensionAbility from '@ohos.app.ability.UIExtensionAbility';
import UIExtensionContentSession from '@ohos.app.ability.UIExtensionContentSession';
import Want from '@ohos.app.ability.Want';
import hilog from '@ohos.hilog';
import { BusinessError } from '@ohos.base';
import { PlaybackCaptureConsent } from '../common/PlaybackCaptureConsent';

// Non-exported. Only the existing same-bundle SystemUI system-dialog host can
// embed this extension. The host service retains START_SYSTEM_DIALOG protection.
export default class PlaybackCaptureConsentExtension extends UIExtensionAbility {
  private sessions: Map<UIExtensionContentSession, PlaybackCaptureConsent> = new Map();
  onSessionCreate(want: Want, session: UIExtensionContentSession): void {
    try {
      const parameters = want.parameters;
      if (parameters === undefined || typeof parameters.sessionId !== 'number' || typeof parameters.uid !== 'number' ||
        parameters['ability.want.params.uiExtensionType'] !== 'sys/commonUI') {
        throw new Error('real audio-service playback privacy parameters required');
      }
      const request = PlaybackCaptureConsent.create(parameters.sessionId as number, parameters.uid as number, session);
      this.sessions.set(session, request);
      const storage: LocalStorage = new LocalStorage();
      storage.setOrCreate<string>('consentId', request.id);
      storage.setOrCreate<string>('bundle', request.bundle);
      session.loadContent('pages/PlaybackCaptureConsentPage', storage);
      session.setWindowBackgroundColor('#00000000');
    } catch (error) {
      hilog.error(0xFF71, 'AudioPrivacyConsent', 'AP extension rejected code=%{public}d', (error as BusinessError).code || -1);
      const request = this.sessions.get(session);
      if (request !== undefined) { request.decide(false, 'load-error'); }
      else { session.terminateSelf().catch((reason: BusinessError): void => {
        hilog.error(0xFF71, 'AudioPrivacyConsent', 'AP reject close code=%{public}d', reason.code);
      }); }
    }
  }
  onSessionDestroy(session: UIExtensionContentSession): void {
    const request = this.sessions.get(session);
    this.sessions.delete(session); request?.decide(false, 'destroy');
  }
  onDestroy(): void {
    this.sessions.forEach((request: PlaybackCaptureConsent): void => { request.decide(false, 'extension-destroy'); });
    this.sessions.clear();
  }
}

import audio from '@ohos.multimedia.audio';
import bundleManager from '@ohos.bundle.bundleManager';
import UIExtensionContentSession from '@ohos.app.ability.UIExtensionContentSession';
import hilog from '@ohos.hilog';
import util from '@ohos.util';
import { BusinessError } from '@ohos.base';

// This source-local type declares the real exported NAPI entry verified in
// NapiAudioManager::ReportPlaybackCaptureUserChoice; it is not a JS substitute.
interface PrivacyAudioManager extends audio.AudioManager {
  reportPlaybackCaptureUserChoice(sessionId: number, choice: boolean): number;
}
export class PlaybackCaptureConsent {
  readonly id: string = util.generateRandomUUID();
  readonly bundle: string;
  private settled: boolean = false;
  private closeRequested: boolean = false;
  private poll: number = -1;
  private expiry: number = -1;
  private static pending: Map<string, PlaybackCaptureConsent> = new Map();
  private static streams: Map<number, string> = new Map();
  readonly streamId: number;
  readonly uid: number;
  private readonly content: UIExtensionContentSession;
  private constructor(streamId: number, uid: number, content: UIExtensionContentSession) {
    this.streamId = streamId;
    this.uid = uid;
    this.content = content;
    this.verifyLive();
    this.bundle = bundleManager.getBundleNameByUidSync(uid);
    if (this.bundle.length === 0) { throw new Error('requesting capture UID has no actual bundle'); }
  }
  static create(streamId: number, uid: number, content: UIExtensionContentSession): PlaybackCaptureConsent {
    if (!Number.isInteger(streamId) || streamId <= 0 || streamId > 0x7FFFFFFF ||
      !Number.isInteger(uid) || uid < 0 || uid > 0x7FFFFFFF || PlaybackCaptureConsent.streams.has(streamId)) {
      throw new Error('one genuine pending capture stream and UID required');
    }
    const request = new PlaybackCaptureConsent(streamId, uid, content);
    PlaybackCaptureConsent.pending.set(request.id, request);
    PlaybackCaptureConsent.streams.set(streamId, request.id);
    request.poll = setInterval((): void => {
      if (request.settled) { return; }
      try { request.verifyLive(); } catch (error) { request.decide(false, 'stream-gone'); }
    }, 250);
    // Native admission owns the final deadline. This earlier UI expiry cannot
    // grant after native expiry, even under a delayed or suspended callback.
    request.expiry = setTimeout((): void => { request.decide(false, 'timeout'); }, 50000);
    request.log('shown', 0);
    return request;
  }
  static find(id: string): PlaybackCaptureConsent | undefined { return PlaybackCaptureConsent.pending.get(id); }
  private verifyLive(): void {
    const infos = audio.getAudioManager().getStreamManager().getCurrentAudioCapturerInfoArraySync();
    const matching = infos.filter((entry: audio.AudioCapturerChangeInfo): boolean => entry.streamId === this.streamId);
    if (matching.length !== 1 || matching[0].clientUid !== this.uid ||
      matching[0].capturerInfo.source !== audio.SourceType.SOURCE_TYPE_PLAYBACK_CAPTURE ||
      matching[0].capturerState !== audio.AudioState.STATE_PREPARED) {
      throw new Error('actual playback capture stream/UID/source/prepared state changed');
    }
  }
  decide(choice: boolean, reason: string): void {
    if (this.settled) { return; }
    this.settled = true;
    clearInterval(this.poll); clearTimeout(this.expiry);
    let live: boolean = false;
    try { this.verifyLive(); live = true; }
    catch (error) { this.log('stale', (error as BusinessError).code || -1); }
    try {
      if (live) {
        const actual: number = (audio.getAudioManager() as PrivacyAudioManager)
          .reportPlaybackCaptureUserChoice(this.streamId, choice);
        // Only actual OS API return bytes/status are logged. Capture client
        // callback and real running state independently establish any grant.
        this.log((choice ? 'allow-' : 'deny-') + reason, actual);
        if (actual !== 0) { throw new Error('native privacy decision did not succeed'); }
      }
    } catch (error) { this.log('report-error', (error as BusinessError).code || -1); }
    finally { this.close(); }
  }
  private close(): void {
    if (this.closeRequested) { return; }
    this.closeRequested = true;
    PlaybackCaptureConsent.pending.delete(this.id);
    if (PlaybackCaptureConsent.streams.get(this.streamId) === this.id) { PlaybackCaptureConsent.streams.delete(this.streamId); }
    this.content.terminateSelf().then((): void => { this.log('closed', 0); },
      (error: BusinessError): void => { this.log('close-error', error.code); });
  }
  private log(event: string, code: number): void {
    hilog.info(0xFF71, 'AudioPrivacyConsent',
      'AP id=%{public}s event=%{public}s stream=%{public}d uid=%{public}d bundle=%{public}s code=%{public}d',
      this.id, event, this.streamId, this.uid, this.bundle, code);
  }
}

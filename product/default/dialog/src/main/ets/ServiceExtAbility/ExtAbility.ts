/*
 * Copyright (c) 2021-2023 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import ServiceExtensionAbility from '@ohos.app.ability.ServiceExtensionAbility';
import Want from '@ohos.app.ability.Want';
import display from '@ohos.display';
import window from '@ohos.window';
import rpc from '@ohos.rpc';
import Log from '../common/Log';
import Constants, { ServiceStubCode } from '../common/Constants';
import SystemDialogController from '../controller/Controller';
import type { IDialogParameters } from '../controller/Controller';

const TAG = 'Dialog-ServiceExtensionAbility';

const getConnectId = (...args) => {
  return args.join('-');
};

const REPLY_SUCCESS_CODE = 0;

class Stub extends rpc.RemoteObject {
  onRemoteRequest(code: number, data, reply, option) {
    const connectId = getConnectId(rpc.IPCSkeleton.getCallingPid(), rpc.IPCSkeleton.getCallingTokenId());
    Log.showInfo(TAG, `onRemoteRequest start ${connectId}`);

    if (code === 3) {
      const controller = globalThis.SystemDialog_Controller;
      const sessionId = data.readInt();
      const uid = data.readInt();
      if (!Number.isInteger(sessionId) || sessionId <= 0 || !Number.isInteger(uid) || uid < 0) { return false; }
      const audioConnectId = `${connectId}-audio-${uid}-${sessionId}`;
      const current = controller?.getData().get(audioConnectId);
      if (current?.parameters?.bundleName !== 'com.ohos.systemui' ||
          current?.parameters?.abilityName !== 'PlaybackCaptureConsentExtension' ||
          current?.parameters?.parameters?.sessionId !== sessionId || current?.parameters?.parameters?.uid !== uid) {
        return false;
      }
      controller.destroyWindow(audioConnectId);
      reply.writeInt(REPLY_SUCCESS_CODE);
      return true;
    }

    if (code === ServiceStubCode.COMMAND_SEND_REMOTE_OBJECT) {
      Log.showInfo(TAG, `onRemoteRequest code:${ServiceStubCode.COMMAND_SEND_REMOTE_OBJECT} start ${connectId}`);
      const controller = globalThis.SystemDialog_Controller;
      const remoteObject = data.readRemoteObject();
      Log.showDebug(TAG, `onRemoteRequest code:${ServiceStubCode.COMMAND_SEND_REMOTE_OBJECT} ${remoteObject}`);

      if (remoteObject) {
        controller.addDataByKey(connectId, { remoteObject });
        Log.showDebug(TAG, `onRemoteRequest code:${ServiceStubCode.COMMAND_SEND_REMOTE_OBJECT} end`);

        reply.writeInt(REPLY_SUCCESS_CODE);
        return true;
      }

      return false;
    }

    if (code === ServiceStubCode.COMMAND_START_DIALOG) {
      Log.showInfo(TAG, `onRemoteRequest code:${ServiceStubCode.COMMAND_START_DIALOG} ${connectId}`);
      const size = data.readInt();
      const parameters: { [key: string]: any } = {};

      for (let i = 0; i < size; i++) {
        const key = data.readString();
        const value = data.readString();
        parameters[key] = value;
      }

      if (parameters.parameters) {
        try {
          const parse = JSON.parse(parameters.parameters);
          if (typeof parse === 'object') {
            parameters.parameters = parse;
            Log.showDebug(TAG, `onRemoteRequest parameters ${parameters.parameters}`);
          }
        } catch {
          parameters.parameters = undefined;
        }
      }

      let dialogConnectId = connectId;
      if (parameters.bundleName === 'com.ohos.systemui' && parameters.abilityName === 'PlaybackCaptureConsentExtension') {
        const sessionId = parameters.parameters?.sessionId;
        const uid = parameters.parameters?.uid;
        if (!Number.isInteger(sessionId) || sessionId <= 0 || sessionId > 0x7fffffff ||
            !Number.isInteger(uid) || uid < 0 || uid > 0x7fffffff) { return false; }
        // All capturers call through one audio-server PID/token. Retain the
        // protected caller key and add the actual stream/owner identity so two
        // simultaneous authorization windows cannot replace each other.
        dialogConnectId = `${connectId}-audio-${uid}-${sessionId}`;
      }
      this.createWindow(dialogConnectId, parameters).catch(error => {
        Log.showError(TAG, `createWindow failed ${dialogConnectId} ${JSON.stringify(error)}`);
      });

      reply.writeInt(REPLY_SUCCESS_CODE);
      return true;
    }

    return false;
  }

  async createWindow(connectId: string, parameters: IDialogParameters) {
    const controller = globalThis.SystemDialog_Controller;
    const current = controller.getData().get(connectId);
    if (current && current.windowName) { controller.destroyWindow(connectId, false); }
    const windowName = `SystemDialog${++controller.count}`;
    controller.addDataByKey(connectId, { windowName, parameters });
    const alive = () => globalThis.SystemDialog_Controller === controller &&
      controller.getData().get(connectId)?.windowName === windowName;
    let win: window.Window | undefined = undefined;
    try {
      const dis = await display.getDefaultDisplay();
      if (!alive()) { return; }
      win = await window.createWindow({ ctx: controller.getContext(), name: windowName,
        windowType: parameters?.bundleName == "com.ohos.powerdialog" ? window.WindowType.TYPE_SCREENSHOT : window.WindowType.TYPE_FLOAT });
      if (!alive()) { await win.destroyWindow(); return; }
      const localStorage = new LocalStorage({ windowName, connectId, parameters });
      await win.moveWindowTo(0, 0);
      if (!alive()) { await win.destroyWindow(); return; }
      await win.resize(dis.width, dis.height);
      if (!alive()) { await win.destroyWindow(); return; }
      await win.loadContent('pages/ExtIndex', localStorage);
      if (!alive()) { await win.destroyWindow(); return; }
      await win.setWindowBackgroundColor('#00000000');
      if (!alive()) { await win.destroyWindow(); return; }
      await win.showWindow();
      if (!alive()) { await win.destroyWindow(); }
    } catch (error) {
      // Only remove this exact async window generation. An old failed create
      // cannot close a newer request that reuses the same native connection key.
      if (alive()) { controller.destroyWindow(connectId); }
      else if (win !== undefined) {
        try { await win.destroyWindow(); }
        catch (cleanupError) { Log.showError(TAG, `stale window destroy ${JSON.stringify(cleanupError)}`); }
      }
      throw error;
    }
  }

}

export default class DialogServiceExtAbility extends ServiceExtensionAbility {
  onCreate(want: Want) {
    Log.showInfo(TAG, 'onCreate');
    globalThis.SystemDialog_Controller = new SystemDialogController(this.context);
  }

  onConnect() {
    Log.showInfo(TAG, 'onConnect');
    return new Stub('SystemDialog');
  }

  onDisconnect() {
    Log.showInfo(TAG, 'onDisconnect');
  }

  onDestroy() {
    const controller = globalThis.SystemDialog_Controller;
    controller.destroyAllWindow();
    globalThis.SystemDialog_Controller = undefined;

    Log.showInfo(TAG, 'onDestroy end');
  }
}

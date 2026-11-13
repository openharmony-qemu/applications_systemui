/*
 * Copyright (c) 2026 Huawei Device Co., Ltd.
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

import notificationManager from '@ohos.notificationManager';
import { BusinessError } from '@ohos.base';
import Log from '../../../../../../../../../../common/src/main/ets/default/Log';
import { NotificationItemData, NotificationLayout as Layout } from '../../common/constants';

const TAG = 'NoticeItem-SystemLiveViewItem';

@Component
export default struct SystemLiveViewItem {
  @Prop itemData: NotificationItemData;
  @State sending: boolean = false;

  async trigger(buttonName: string): Promise<void> {
    // Use only a button actually advertised by this delivered notification.
    if (this.sending || !this.itemData.systemLiveView?.button?.names?.includes(buttonName) ||
      !this.itemData.systemLiveViewBundle) {
      return;
    }
    this.sending = true;
    try {
      await notificationManager.triggerSystemLiveView(this.itemData.systemLiveViewBundle,
        Number(this.itemData.id), { buttonName: buttonName });
    } catch (error) {
      const failure = error as BusinessError;
      Log.showError(TAG, `triggerSystemLiveView failed: ${failure.code} ${failure.message}`);
    } finally {
      this.sending = false;
    }
  }

  build() {
    Column() {
      Text(this.itemData.title)
        .fontSize($r("sys.float.ohos_id_text_size_body2"))
        .fontColor($r("sys.color.ohos_fa_text_primary"))
      Text(this.itemData.text)
        .fontSize($r("sys.float.ohos_id_text_size_body2"))
        .fontColor($r("sys.color.ohos_fa_text_secondary"))
      Row() {
        ForEach(this.itemData.systemLiveView?.button?.names?.slice(0, 3) ?? [], (name: string) => {
          Button(name, { type: ButtonType.Capsule })
            .id('system-live-view-button-' + name)
            .enabled(!this.sending)
            .height(Layout.ACTION_HEIGHT)
            .margin({ right: Layout.ACTION_MARGIN })
            .onClick(() => { this.trigger(name); })
        }, (name: string) => name)
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .padding(Layout.ITEM_MARGIN)
    .width('100%')
  }
}

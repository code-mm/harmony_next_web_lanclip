import { UIAbility, ConfigurationConstant } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { window, KeyboardAvoidMode } from '@kit.ArkUI';

export default class EntryAbility extends UIAbility {
  onCreate(): void {
    try { this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT); } catch (_) {}
    AppStorage.setOrCreate('foreground', true);
  }
  onWindowStageCreate(stage: window.WindowStage): void {
    stage.getMainWindow().then(async (mainWindow: window.Window) => {
      try {
        await mainWindow.setWindowLayoutFullScreen(false);
        if (deviceInfo.deviceType !== '2in1') {
          await mainWindow.setWindowSystemBarProperties({ statusBarColor: '#F4F5F7', statusBarContentColor: '#252D38',
            navigationBarColor: '#F4F5F7', navigationBarContentColor: '#252D38' });
        }
        mainWindow.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
      } catch (_) { /* Default window insets still apply if an optional style is unavailable. */ }
    }).catch(() => {});
    stage.loadContent('pages/Index');
  }
  onForeground(): void { AppStorage.setOrCreate('foreground', true); }
  onBackground(): void { AppStorage.setOrCreate('foreground', false); }
}

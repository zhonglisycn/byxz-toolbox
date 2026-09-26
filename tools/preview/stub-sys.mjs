/**
 * @system.* 接口的打桩实现（仅供预览渲染使用，不参与打包）
 */
function cb(opts, name, arg) {
  if (!opts) return
  if (typeof opts[name] === 'function') opts[name](arg)
}

export default {
  push() {}, replace() {}, back() {}, clear() {}
}

export const router = { push() {}, replace() {}, back() {}, clear() {} }
export const storage = {
  set(o) { cb(o, 'success') },
  get(o) { cb(o, 'fail', '', 200) },   // 预览时当作没有存档
  delete(o) { cb(o, 'success') },
  length: 0
}
export const prompt = {
  showToast(o) { cb(o, 'success') },
  showDialog(o) { cb(o, 'cancel') }
}
export const device = {
  // deviceType 必须是 watch：真机就是手表（manifest 的 deviceTypeList 只有 watch），
  // 原版这类按设备类型分支的页面在预览里才会走手表那套布局。
  getInfo(o) {
    cb(o, 'success', {
      deviceType: 'watch',
      screenShape: 'pill-shaped',
      screenWidth: 212,
      screenHeight: 520
    })
  }
}
export const vibrator = { vibrate(o) { cb(o, 'success') } }
export const brightness = { setKeepScreenOn(o) { cb(o, 'success') }, setValue(o) { cb(o, 'success') } }
export const interconnect = { send() {}, subscribe() {} }

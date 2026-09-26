/**
 * 存档读写（唯一依赖系统接口的公共模块）
 * 本重制版没有任何激活 / 付费校验——所有内容直接可用。
 */
import storage from '@system.storage'

export function saveKey(key, value, cb) {
  storage.set({
    key: key,
    value: value,
    success: function () { if (cb) cb(true) },
    fail: function (data, code) { if (cb) cb(false, code) }
  })
}

export function loadKey(key, cb) {
  storage.get({
    key: key,
    success: function (data) { cb(true, data) },
    fail: function (data, code) { cb(false, code) }
  })
}

export function dropKey(key, cb) {
  storage.delete({
    key: key,
    success: function () { if (cb) cb(true) },
    fail: function (data, code) { if (cb) cb(false, code) }
  })
}

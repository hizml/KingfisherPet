// 放音勿扰探针二进制:调 MediaRemote 私有 C API MRMediaRemoteGetNowPlayingApplicationIsPlaying
// (mediaserverd 维护的系统真相,控制中心"正在播放"同款信号)。输出 "1"/"0"/"nil"/"timeout"。
// 为什么不用 osascript:JXA 只能摸到 localNowPlayingItem 的 info 字典——那是"App 上次
// SET 的值":实测有播放器暂停后 rate 恒挂 1(《难哄》插曲案,elapsed 冻结 16s 实锤),
// 字典三信号(rate/flag/elapsed)全废;JXA 又调不了 C 函数,故出此二进制。
// 判定端 SpriteLibrary.shouldSwallowChirp:只认 "1",其余(含 timeout)照叫(fail-open)。
import Foundation
let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
guard let handle = dlopen(path, RTLD_LAZY),
      let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") else { print("nil"); exit(1) }
typealias ProbeFn = @convention(c) (UnsafeRawPointer, @escaping @convention(block) (Bool) -> Void) -> Void
let fn = unsafeBitCast(sym, to: ProbeFn.self)
let q = DispatchQueue(label: "kf.probe")
let sem = DispatchSemaphore(value: 0)
var playing = false
let qp = Unmanaged.passUnretained(q).toOpaque()
fn(UnsafeRawPointer(qp)) { flag in
    playing = flag
    sem.signal()
}
if sem.wait(timeout: .now() + 3) == .timedOut {
    print("timeout")
} else {
    print(playing ? "1" : "0")
}

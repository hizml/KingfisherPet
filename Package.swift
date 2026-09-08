// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KingfisherPet",
    platforms: [.macOS(.v13)],
    targets: [
        // 实现核心(库):拆出来是为了 kf-tests 能链接做纯逻辑单测——
        // executable 依赖 executable 会双 main 撞链接,这是 SwiftPM 的标准解法
        .target(
            name: "KingfisherPetCore",
            path: "Sources/KingfisherPetCore",
            swiftSettings: [.swiftLanguageMode(.v5)]   // 升 tools 6.0 不开启严格并发
        ),
        // 应用薄壳(组装 + run)
        .executableTarget(
            name: "KingfisherPet",
            dependencies: ["KingfisherPetCore"],
            path: "Sources/KingfisherPet",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // 放音勿扰探针二进制(随 app 打包,叫前 spawn 查一次系统"真在播"标志)
        .executableTarget(
            name: "kf-media-probe",
            path: "Sources/kf-media-probe",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // 纯逻辑单测 runner(零依赖:本机 CLT 无 XCTest/swift-testing):
        // swift run kf-tests,断言失败 exit 1,CI 与本地通用。
        // 起因:版本比较 bug 属"正常流正确、边界态静默错",review 治不了这类,单测才治得了
        .executableTarget(
            name: "kf-tests",
            dependencies: ["KingfisherPetCore"],
            path: "Tests/KingfisherPetTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)

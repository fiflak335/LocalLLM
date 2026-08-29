// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LocalLLM",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "LocalLLM",
            targets: ["LocalLLM"]
        ),
    ],
    dependencies: [
        // MLX Swift for local LLM inference with Metal acceleration
        .package(url: "https://github.com/ml-explore/mlx-swift.git", from: "0.12.0"),
        // MarkdownUI for rendering markdown in chat
        .package(url: "https://github.com/gonzalezreal/MarkdownUI.git", from: "5.0.0"),
        // SwiftData is built into iOS 17+, no external dependency needed
    ],
    targets: [
        .target(
            name: "LocalLLM",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXOptimizers", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
                .product(name: "MLXFFT", package: "mlx-swift"),
                "MarkdownUI"
            ],
            path: "LocalLLM",
            exclude: ["Resources", "LocalLLM.entitlements"]
        ),
        .testTarget(
            name: "LocalLLMTests",
            dependencies: ["LocalLLM"],
            path: "LocalLLMTests"
        )
    ]
)
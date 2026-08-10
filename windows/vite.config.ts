import { defineConfig } from "vite";

// Tauri 推荐的 vite 配置:固定端口、不清屏(看 tauri 输出)、es2021 目标
export default defineConfig({
  clearScreen: false,
  server: {
    port: 1420,
    strictPort: true,
  },
  envPrefix: ["VITE_", "TAURI_"],
  build: {
    target: "es2021",
    assetsDir: ".",
  },
});

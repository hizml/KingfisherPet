import { defineConfig } from "vite";
import { resolve } from "path";

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
    // 多入口:crack/poop 是独立 webview 窗口,不写进 input 的话 vite build 只打 index.html,
    // 打包后这两个窗口 404(裂纹/屎不渲染)
    rollupOptions: {
      input: {
        main: resolve(__dirname, "index.html"),
        crack: resolve(__dirname, "crack.html"),
        poop: resolve(__dirname, "poop.html"),
        settings: resolve(__dirname, "settings.html"),
      },
    },
  },
});

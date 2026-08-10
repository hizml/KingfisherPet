// 加载当前主题的 sprites.json + 预加载所有帧 png(对应 macOS 版 SpriteLibrary)
// 素材放 windows/public/Sprites/<theme>/,vite 打包到 dist/,Tauri 加载。

export interface SpriteManifest {
  fps: Record<string, number>;
  sequences: Record<string, string[]>;
}

export class SpriteLibrary {
  manifest: SpriteManifest = { fps: {}, sequences: {} };
  frames: Map<string, HTMLImageElement> = new Map();
  theme = "flat";

  async load(theme: string) {
    this.theme = theme;
    const base = `${import.meta.env.BASE_URL}Sprites/${theme}`;
    const res = await fetch(`${base}/sprites.json`);
    if (!res.ok) {
      console.error("sprites.json 加载失败", res.status);
      return;
    }
    this.manifest = await res.json();
    const names = new Set<string>();
    Object.values(this.manifest.sequences).forEach(seq => seq.forEach(n => names.add(n)));
    await Promise.all([...names].map(n => new Promise<void>(resolve => {
      const img = new Image();
      img.src = `${base}/${n}.png`;
      img.onload = () => { this.frames.set(n, img); resolve(); };
      img.onerror = () => { console.warn("缺帧", n); resolve(); };
    })));
  }

  frame(name: string): HTMLImageElement | undefined { return this.frames.get(name); }
  sequence(state: string): string[] { return this.manifest.sequences[state] ?? ["idle_0"]; }
  fps(state: string): number { return this.manifest.fps[state] ?? 8; }
}

// 加载当前主题的 sprites.json + 预加载所有帧 png + 每帧 alpha 缓冲(逐像素点击穿透用)
// 对应 macOS SpriteLibrary(帧)+ PetView.alphaBuffer(alpha)

export interface SpriteManifest {
  fps: Record<string, number>;
  sequences: Record<string, string[]>;
}

/** 单帧:图像 + alpha 缓冲(行优先,顶行在前,长度 w*h) */
export interface Frame {
  img: HTMLImageElement;
  alpha: Uint8Array;
  w: number;
  h: number;
}

export class SpriteLibrary {
  manifest: SpriteManifest = { fps: {}, sequences: {} };
  frames: Map<string, Frame> = new Map();
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
      img.onload = () => {
        const w = img.naturalWidth, h = img.naturalHeight;
        let alpha = new Uint8Array(0);
        try {
          const canvas = document.createElement("canvas");
          canvas.width = w; canvas.height = h;
          const ctx = canvas.getContext("2d");
          if (ctx) {
            ctx.drawImage(img, 0, 0);
            const data = ctx.getImageData(0, 0, w, h).data;
            alpha = new Uint8Array(w * h);
            for (let i = 0; i < alpha.length; i++) alpha[i] = data[i * 4 + 3];
          }
        } catch (e) {
          // getImageData 失败(CORS/taint 等):alpha 留空(逐像素穿透退化为整体穿透),不卡住加载
          console.warn("alpha 计算失败", n, e);
        }
        this.frames.set(n, { img, alpha, w, h });
        resolve();
      };
      img.onerror = () => { console.warn("缺帧", n); resolve(); };
    })));
  }

  frame(name: string): Frame | undefined { return this.frames.get(name); }
  sequence(state: string): string[] { return this.manifest.sequences[state] ?? ["idle_0"]; }
  fps(state: string): number { return this.manifest.fps[state] ?? 8; }

  /** 归一化坐标(nx/ny 0..1)→ 该像素的 alpha。对应 macOS PetView.alphaAt */
  alphaAt(name: string, nx: number, ny: number): number {
    const f = this.frames.get(name);
    if (!f || f.w === 0) return 0;
    const px = Math.min(f.w - 1, Math.max(0, Math.floor(nx * f.w)));
    const py = Math.min(f.h - 1, Math.max(0, Math.floor(ny * f.h)));
    return f.alpha[py * f.w + px];
  }
}

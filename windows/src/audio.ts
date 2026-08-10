// 叫声:4 种 peep_*.wav,随机播。对应 macOS SpriteLibrary.playPeep。
const players: HTMLAudioElement[] = [];
let enabled = true;

export function setupAudio() {
  for (let i = 0; i < 4; i++) {
    const a = new Audio(`${import.meta.env.BASE_URL}peep_${i}.wav`);
    a.preload = "auto";
    players.push(a);
  }
}

export function playPeep() {
  if (!enabled || players.length === 0) return;
  const p = players[Math.floor(Math.random() * players.length)];
  p.currentTime = 0;
  p.play().catch(() => {});
}

export function setSoundOn(on: boolean) { enabled = on; }

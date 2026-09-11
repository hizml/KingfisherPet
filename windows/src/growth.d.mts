export declare function stageOf(intimacy: number): number;
export declare function affectionChance(stage: number): number;
export declare const STAGE_ZH: string[];
export declare const STAGE_EN: string[];
export declare function growthMenuTitle(intimacy: number, hatched: boolean, zh: boolean): string;
export declare const FEED_COOLDOWN_MS: number;
export declare function feedAllowed(nowMs: number, lastFeedAtMs: number | null): boolean;

export declare function isNewer(tag: string, cur: string): boolean;
export interface DayFactors { overall: number; sing: number; fish: number; dart: number; sun: number; }
export interface ThinkBands { idleBand: number; walkEnd: number; k: number; widths: number[]; sleepShare: number; }
export declare function dayFactors(hour: number): DayFactors;
export interface WeatherWx { overall?: number; fly?: number; fish?: number; sing?: number; dart?: number; watch?: number; sun?: number; perch?: number; walk?: number; }
export declare function thinkBands(activity: number, hour: number, wx?: WeatherWx): ThinkBands;
export declare function napSeconds(hour: number): [number, number];
export declare const LAN_PROTO_V: number;
export declare const LAN_TYPES: string[];
export declare const LAN_MAX_LINE: number;
export declare function lanCodename(): string;
export declare function lanEncode(obj: Record<string, unknown>): string | null;
export declare function lanDecode(line: string): { type: string; name: string } | null;
export declare const LAN_VISIT_COOLDOWN_MS: number;
export declare function lanVisitAllowed(nowMs: number, lastVisitMs: number | null): boolean;
export declare function qwIsNewAPI(host: string): boolean;
/// 天气刷新周期:成功 30 分钟,失败 5 分钟(毫秒;契约见 shared.mjs 同名实现)
export declare function nextWeatherIntervalMs(succeeded: boolean): number;

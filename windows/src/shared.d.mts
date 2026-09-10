export declare function isNewer(tag: string, cur: string): boolean;
export interface DayFactors { overall: number; sing: number; fish: number; dart: number; sun: number; }
export interface ThinkBands { idleBand: number; walkEnd: number; k: number; widths: number[]; sleepShare: number; }
export declare function dayFactors(hour: number): DayFactors;
export declare function thinkBands(activity: number, hour: number): ThinkBands;

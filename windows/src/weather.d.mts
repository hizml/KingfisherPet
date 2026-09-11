export declare function severity(k: string): number;
export declare function mergeMain(a: string | null, b: string | null): string | null;
export declare function mainFromOpenMeteo(code: number, windSpeed: number): string | null;
export declare function mainFromQWeather(code: number, windScale: number): string | null;
export declare function tempFlags(tempC: number | null): { hot: boolean; cold: boolean };
export declare function weatherFactors(main: string, hot: boolean, cold: boolean): Record<string, number>;

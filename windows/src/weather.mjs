// 天气归一化纯函数(v1.5.0 B;macOS WeatherService.swift 对称实现——同一映射同一
// 用例口径,任改一处必须同步另一端)。.mjs 让 tests/weather.test.mjs 直打真实现
// (版本比较 bug 的教训:测试必须打真实现,不是复制品)。

/// 11 档枚举(字符串;hot/cold 为温度副档,不作主档)
export const KINDS = ["sunny","overcast","rainLight","rainHeavy","thunder",
                      "snowLight","snowHeavy","fog","wind","hot","cold"];

/// 恶劣度:thunder > rainHeavy > wind > snowHeavy > rainLight > snowLight > fog > overcast > sunny
export function severity(k) {
  const order = { thunder: 9, rainHeavy: 8, wind: 7, snowHeavy: 6, rainLight: 5,
                  snowLight: 4, fog: 3, overcast: 2, sunny: 1, hot: 0, cold: 0 };
  return order[k] ?? 0;
}

/// 主档互斥取最恶劣
export function mergeMain(a, b) {
  if (a == null) return b;
  if (b == null) return a;
  return severity(a) >= severity(b) ? a : b;
}

/// WMO 码表(Open-Meteo 官方 weather codes,逐项核对;与 Mac 同表):
/// 0–2 晴 / 3 阴 / 45,48 雾 / 51,53,56,57,61,80 小雨 / 55,63,65,66,67,81,82 大雨 /
/// 95,96,99 雷暴 / 71,77,85 小雪 / 73,75,86 大雪;未知码 null(静默不干预)。
/// 风速 >10.8 m/s(6 级)→ wind,按恶劣度与码位主档取更凶。
export function mainFromOpenMeteo(code, windSpeed) {
  let byCode = null;
  if ([0,1,2].includes(code)) byCode = "sunny";
  else if (code === 3) byCode = "overcast";
  else if ([45,48].includes(code)) byCode = "fog";
  else if ([51,53,56,57,61,80].includes(code)) byCode = "rainLight";
  else if ([55,63,65,66,67,81,82].includes(code)) byCode = "rainHeavy";
  else if ([95,96,99].includes(code)) byCode = "thunder";
  else if ([71,77,85].includes(code)) byCode = "snowLight";
  else if ([73,75,86].includes(code)) byCode = "snowHeavy";
  const byWind = windSpeed > 10.8 ? "wind" : null;
  return mergeMain(byCode, byWind);
}

/// 和风码表(v7 官方对照,逐项核对;与 Mac 同表;302–304 才是雷阵雨、313 冻雨):
/// 100–103,150–153 晴 / 104 阴 / 500–515 雾霾沙尘(能见度类→fog) /
/// 300,301,305,306,309,350,351 小雨 / 307,308,310–312,313–318 大雨(313 冻雨) /
/// 302,303,304 雷暴 / 400,401,404–408,457 小雪 / 402,403,409,410,456 大雪 /
/// 399/499 未知保守轻档 / 900 热 901 冷;windScale≥6 → wind 取更凶。
export function mainFromQWeather(code, windScale) {
  let byCode = null;
  if ((code >= 100 && code <= 103) || (code >= 150 && code <= 153)) byCode = "sunny";
  else if (code === 104) byCode = "overcast";
  else if (code >= 500 && code <= 515) byCode = "fog";
  else if ([300,301,305,306,309,350,351].includes(code)) byCode = "rainLight";
  else if ([307,308,310,311,312,313,314,315,316,317,318].includes(code)) byCode = "rainHeavy";
  else if ([302,303,304].includes(code)) byCode = "thunder";
  else if ([400,401,404,405,406,407,408,457].includes(code)) byCode = "snowLight";
  else if ([402,403,409,410,456].includes(code)) byCode = "snowHeavy";
  else if (code === 399) byCode = "rainLight";
  else if (code === 499) byCode = "snowLight";
  else if (code === 900) byCode = "sunny";
  else if (code === 901) byCode = "overcast";
  const byWind = windScale >= 6 ? "wind" : null;
  return mergeMain(byCode, byWind);
}

/// 温度副档:>32°C 热 / <5°C 冷(双源同规则)
export function tempFlags(tempC) {
  if (tempC == null || !Number.isFinite(tempC)) return { hot: false, cold: false };
  return { hot: tempC > 32, cold: tempC < 5 };
}

/// 天气权重表(PLAN-B 老板拍板版;全 1 = 不干预;与 Mac WeatherFactors.factors 同表)。
/// 结构与 shared.mjs thinkBands 的 wx 参数对齐(鸭子类型普通对象,可选传入)。
export function weatherFactors(main, hot, cold) {
  const f = { overall: 1, fly: 1, fish: 1, sing: 1, dart: 1, watch: 1, sun: 1, perch: 1, walk: 1 };
  switch (main) {
    case "sunny": f.sun = 1.6; f.watch = 1.2; break;
    case "overcast": break;
    case "rainLight": f.fly = 0.7; f.fish = 0.7; f.dart = 0.7; f.perch = 1.3; break;
    case "rainHeavy": f.fly = 0.3; f.fish = 0.3; f.dart = 0.3; f.perch = 1.6; break;
    case "thunder": f.overall = 0.3; f.fly = 0; f.fish = 0; f.dart = 0; break;   // watch 保留(雷惊探头)
    case "snowLight": f.walk = 0.8; f.watch = 1.5; break;
    case "snowHeavy": f.fly = 0.4; f.fish = 0.4; f.dart = 0.4; f.perch = 1.5; f.watch = 1.5; break;
    case "fog": f.fly = 0.5; f.watch = 1.5; break;
    case "wind": f.fly = 0.3; f.perch = 1.5; break;
    default: break;
  }
  if (hot) { f.sun *= 0.5; f.fish *= 1.2; }   // 热:少晒太阳,戏水降温
  if (cold) { f.sun *= 1.6; f.fly *= 0.8; }   // 冷:取暖,少飞
  return f;
}

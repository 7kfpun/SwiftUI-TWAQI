//! The Lambda's read endpoints (aqi/app.py in 7kfpun/lambda-serverless), same
//! paths, params, response shapes and error messages. Differences, on purpose:
//!   - an unknown `country` / `country_id` answers {"success":false,"error":"No such a country"}
//!     (the Lambda raised and sent a 500 with a Python traceback);
//!   - a database failure is an Err, which the server turns into a 500 without a traceback;
//!   - a current reading whose station row is missing is left out (the Lambda raised KeyError, a 500);
//!   - `station_id` takes at most MAX_STATION_IDS distinct ids, else
//!     {"success":false,"error":"Too many station ids"} (the Lambda had no cap).

use crate::pyjson::{Py, decimal, format_decimal, json_column};
use crate::repo::{CountryRow, ReadingRow, Repo, Result, StationRow};

pub struct ApiResponse {
    pub status: u16,
    pub body: Py,
}

fn ok(body: Py) -> ApiResponse {
    ApiResponse { status: 200, body }
}

fn fail(error: &str) -> ApiResponse {
    ok(Py::dict([
        ("success", Py::Bool(false)),
        ("error", Py::str(error)),
    ]))
}

/// Query parameters as the Lambda saw them: first value wins, and Python
/// truthiness makes a missing and an empty value the same.
pub struct Params(Vec<(String, String)>);

impl Params {
    pub fn parse(query: &str) -> Self {
        Params(
            form_urlencoded::parse(query.as_bytes())
                .into_owned()
                .collect(),
        )
    }

    fn raw(&self, name: &str) -> Option<&str> {
        self.0
            .iter()
            .find(|(k, _)| k == name)
            .map(|(_, v)| v.as_str())
    }

    fn get(&self, name: &str) -> Option<&str> {
        self.raw(name).filter(|v| !v.is_empty())
    }
}

/// MySQL compares `id = 'abc'` as 0 and `id = '12abc'` as 12; the Lambda passed the text straight through.
fn mysql_int(text: &str) -> Option<i64> {
    let t = text.trim_start();
    let (sign, rest) = match t.as_bytes().first() {
        Some(b'-') => (-1, &t[1..]),
        Some(b'+') => (1, &t[1..]),
        _ => (1, t),
    };
    let digits: String = rest.chars().take_while(char::is_ascii_digit).collect();
    let n: i64 = digits.parse().ok()?;
    let n = sign * n;
    (n > 0).then_some(n)
}

/// Python `int(text)`: optional sign, digits with single underscores, surrounding whitespace.
fn python_int(text: Option<&str>) -> Option<i64> {
    let t = text?.trim();
    let (sign, body) = match t.as_bytes().first() {
        Some(b'-') => (-1, &t[1..]),
        Some(b'+') => (1, &t[1..]),
        _ => (1, t),
    };
    if body.is_empty()
        || body.starts_with('_')
        || body.ends_with('_')
        || body.contains("__")
        || !body.chars().all(|c| c.is_ascii_digit() || c == '_')
    {
        return None;
    }
    body.replace('_', "").parse::<i64>().ok().map(|n| sign * n)
}

pub fn country_json(c: &CountryRow) -> Result<Py> {
    Ok(Py::dict([
        ("id", Py::Int(c.id)),
        ("code", Py::str(&c.code)),
        ("name", json_column(c.name.as_deref())?),
        ("lat", decimal(c.lat.as_deref())),
        ("lon", decimal(c.lon.as_deref())),
        ("zoom", decimal(c.zoom.as_deref())),
    ]))
}

/// `Station.to_json()` (has country_id) — /v1/stations and historical-pollutants' `station`.
pub fn station_json(s: &StationRow) -> Result<Py> {
    Ok(Py::dict([
        ("id", Py::Int(s.id)),
        ("country_id", Py::Int(s.country_id)),
        ("code", Py::str(&s.code)),
        ("district", Py::str(&s.district)),
        ("name", json_column(s.name.as_deref())?),
        ("address", json_column(s.address.as_deref())?),
        ("area", json_column(s.area.as_deref())?),
        ("station_type", Py::str(&s.station_type)),
        (
            "additional_info",
            json_column(s.additional_info.as_deref())?,
        ),
        ("lat", decimal(s.lat.as_deref())),
        ("lon", decimal(s.long.as_deref())),
        ("image_url", Py::str(&s.image_url)),
    ]))
}

/// `Station.dict_to_json()` (no country_id) — merged into current-pollutants rows.
fn station_dict_json(s: &StationRow) -> Result<Vec<(String, Py)>> {
    let Py::Dict(entries) = station_json(s)? else {
        unreachable!()
    };
    Ok(entries
        .into_iter()
        .filter(|(k, _)| k != "country_id")
        .collect())
}

fn int_display(n: Option<i64>) -> String {
    n.map_or_else(String::new, |n| n.to_string())
}

/// `Pollutant.dict_to_new_json()`.
pub fn reading_json(p: &ReadingRow) -> Vec<(String, Py)> {
    let dec = |v: &Option<String>| decimal(v.as_deref());
    let disp = |v: &Option<String>| Py::Str(format_decimal(v.as_deref(), 1));
    let Py::Dict(entries) = Py::dict([
        ("station_id", Py::Int(p.station_id)),
        ("aqi", p.aqi.into()),
        ("aqi_display", Py::Str(int_display(p.aqi))),
        ("aqhi", p.aqhi.into()),
        ("aqhi_display", Py::Str(int_display(p.aqhi))),
        ("pm25", dec(&p.pm25)),
        ("pm25_display", disp(&p.pm25)),
        ("pm10", dec(&p.pm10)),
        ("pm10_display", disp(&p.pm10)),
        ("no2", dec(&p.no2)),
        ("no2_display", disp(&p.no2)),
        ("so2", dec(&p.so2)),
        ("so2_display", disp(&p.so2)),
        ("co", dec(&p.co)),
        ("co_display", disp(&p.co)),
        ("o3", dec(&p.o3)),
        ("o3_display", disp(&p.o3)),
        ("wind_direction", dec(&p.wind_direction)),
        ("wind_speed", dec(&p.wind_speed)),
        // datetime.isoformat() of the naive Taiwan-local DATETIME.
        (
            "publish_time",
            p.publish_time
                .as_ref()
                .map_or(Py::Null, |t| Py::Str(t.replacen(' ', "T", 1))),
        ),
    ]) else {
        unreachable!()
    };
    entries
}

async fn find_country<R: Repo>(repo: &R, params: &Params) -> Result<Option<CountryRow>> {
    if let Some(code) = params.get("country") {
        return repo.country_by_code(code).await;
    }
    match params.get("country_id").and_then(mysql_int) {
        Some(id) => repo.country_by_id(id).await,
        None => Ok(None),
    }
}

/// current-pollutants rows: station fields, then the reading, with `id` nulled in place.
fn merge_current(stations: &[StationRow], readings: &[ReadingRow]) -> Result<Py> {
    let mut out = Vec::with_capacity(readings.len());
    for p in readings {
        // The Lambda would KeyError (500) on an orphan reading; skip it instead.
        let Some(s) = stations.iter().find(|s| s.id == p.station_id) else {
            continue;
        };
        let mut item = Py::Dict(station_dict_json(s)?);
        for (k, v) in reading_json(p) {
            item.set(&k, v);
        }
        item.set("id", Py::Null);
        out.push(item);
    }
    Ok(Py::List(out))
}

/// Every id is a placeholder in two `IN (...)` queries. Taiwan has 84 stations, so a list of
/// all of them still fits.
pub const MAX_STATION_IDS: usize = 100;

pub const ROUTES: [&str; 4] = [
    "/v1/countries",
    "/v1/stations",
    "/v1/current-pollutants",
    "/v1/historical-pollutants",
];

/// `None` for a path this API doesn't serve.
pub async fn handle<R: Repo>(path: &str, params: &Params, repo: &R) -> Result<Option<ApiResponse>> {
    let response = match path {
        "/v1/countries" => {
            let rows = repo.countries().await?;
            let data = rows.iter().map(country_json).collect::<Result<Vec<_>>>()?;
            ok(Py::dict([
                ("success", Py::Bool(true)),
                ("data", Py::List(data)),
            ]))
        }

        "/v1/stations" => {
            if params.get("country").is_none() && params.get("country_id").is_none() {
                return Ok(Some(fail("Param `country` or `country_id` is required")));
            }
            match find_country(repo, params).await? {
                None => fail("No such a country"),
                Some(country) => {
                    let stations = repo.stations_by_country(country.id).await?;
                    let data = stations
                        .iter()
                        .map(station_json)
                        .collect::<Result<Vec<_>>>()?;
                    ok(Py::dict([
                        ("success", Py::Bool(true)),
                        ("data", Py::List(data)),
                    ]))
                }
            }
        }

        "/v1/current-pollutants" => {
            if params.get("country").is_some() || params.get("country_id").is_some() {
                match find_country(repo, params).await? {
                    None => fail("No such a country"),
                    Some(country) => {
                        let (stations, readings) = tokio::try_join!(
                            repo.stations_by_country(country.id),
                            repo.current_by_country(country.id)
                        )?;
                        ok(Py::dict([
                            ("success", Py::Bool(true)),
                            ("data", merge_current(&stations, &readings)?),
                        ]))
                    }
                }
            } else if let Some(text) = params.get("station_id") {
                // [int(x) for x in station_id.split(',') if x.strip().isdigit()]
                // Deduped: `IN (...)` gives the same rows either way.
                let mut ids: Vec<i64> = text
                    .split(',')
                    .map(str::trim)
                    .filter(|x| !x.is_empty() && x.chars().all(|c| c.is_ascii_digit()))
                    .filter_map(|x| x.parse().ok())
                    .collect();
                ids.sort_unstable();
                ids.dedup();
                if ids.len() > MAX_STATION_IDS {
                    return Ok(Some(fail("Too many station ids")));
                }
                let stations = if ids.is_empty() {
                    vec![]
                } else {
                    repo.stations_by_ids(&ids).await?
                };
                if stations.is_empty() {
                    fail("No such a station")
                } else {
                    let station_ids: Vec<i64> = stations.iter().map(|s| s.id).collect();
                    let readings = repo.current_by_station_ids(&station_ids).await?;
                    ok(Py::dict([
                        ("success", Py::Bool(true)),
                        ("data", merge_current(&stations, &readings)?),
                    ]))
                }
            } else {
                fail("country/station param is required")
            }
        }

        "/v1/historical-pollutants" => {
            // limit = int(limit) if it parses, else 24; then min(limit, 100). A
            // negative limit made MySQL fail, which the Lambda reported as below.
            let limit = python_int(params.raw("limit")).unwrap_or(24).min(100);
            let code = params.get("station");
            let id_text = params.get("station_id");
            if limit < 0 || (code.is_none() && id_text.is_none()) {
                return Ok(Some(fail("station param is required")));
            }
            let station = match code {
                Some(code) => repo.station_by_code(code).await?,
                None => match id_text.and_then(mysql_int) {
                    Some(id) => repo.station_by_id(id).await?,
                    None => None,
                },
            };
            match station {
                None => fail("station param is required"),
                Some(station) => {
                    let rows = if limit == 0 {
                        vec![]
                    } else {
                        repo.history(station.id, limit).await?
                    };
                    let data = rows
                        .iter()
                        .rev()
                        .map(|p| {
                            let mut item = Py::Dict(reading_json(p));
                            item.set("id", Py::Null);
                            item
                        })
                        .collect();
                    ok(Py::dict([
                        ("success", Py::Bool(true)),
                        ("station", station_json(&station)?),
                        ("data", Py::List(data)),
                    ]))
                }
            }
        }

        _ => return Ok(None),
    };
    Ok(Some(response))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn python_int_parses_like_python() {
        assert_eq!(python_int(Some(" 24 ")), Some(24));
        assert_eq!(python_int(Some("+5")), Some(5));
        assert_eq!(python_int(Some("-1")), Some(-1));
        assert_eq!(python_int(Some("1_000")), Some(1000));
        assert_eq!(python_int(Some("1__0")), None);
        assert_eq!(python_int(Some("5.0")), None);
        assert_eq!(python_int(Some("abc")), None);
        assert_eq!(python_int(Some("")), None);
        assert_eq!(python_int(None), None);
    }

    #[test]
    fn merge_current_leaves_out_a_reading_without_its_station() {
        let stations = [StationRow {
            id: 1,
            ..Default::default()
        }];
        let readings = [
            ReadingRow {
                station_id: 1,
                ..Default::default()
            },
            ReadingRow {
                station_id: 2,
                ..Default::default()
            },
        ];
        let Py::List(rows) = merge_current(&stations, &readings).unwrap() else {
            panic!("not a list")
        };
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].get("station_id"), Some(&Py::Int(1)));
    }

    #[test]
    fn mysql_int_takes_the_leading_number() {
        assert_eq!(mysql_int("12abc"), Some(12));
        assert_eq!(mysql_int(" 3"), Some(3));
        assert_eq!(mysql_int("abc"), None);
        assert_eq!(mysql_int("0"), None);
        assert_eq!(mysql_int("-4"), None);
    }
}

//! An in-memory Repo rebuilt from recorded Lambda responses: each JSON value is
//! turned back into the column value MySQL sends (DECIMAL as text at the
//! column's scale, DATETIME as "YYYY-MM-DD HH:MM:SS", JSON columns as text).
#![allow(dead_code)]

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Mutex;

use twaqi_api::pyjson::{Py, dumps, parse};
use twaqi_api::repo::{CountryRow, ReadingRow, Repo, Result, StationRow};

pub struct Case {
    pub name: String,
    pub path: String,
}

fn dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("test")
}

pub fn cases() -> Vec<Case> {
    let text = std::fs::read_to_string(dir().join("cases.json")).unwrap();
    let Py::List(items) = parse(&text).unwrap() else {
        panic!("cases.json")
    };
    items
        .iter()
        .map(|c| Case {
            name: text_of(c.get("name").unwrap()),
            path: text_of(c.get("path").unwrap()),
        })
        .collect()
}

pub fn fixture_text(name: &str) -> String {
    std::fs::read_to_string(dir().join("fixtures").join(format!("{name}.json"))).unwrap()
}

pub fn fixture(name: &str) -> Py {
    parse(&fixture_text(name)).unwrap()
}

pub fn get<'a>(v: &'a Py, key: &str) -> &'a Py {
    v.get(key).unwrap_or_else(|| panic!("missing key {key}"))
}

pub fn list(v: &Py) -> &[Py] {
    match v {
        Py::List(items) => items,
        _ => panic!("not a list"),
    }
}

fn text_of(v: &Py) -> String {
    match v {
        Py::Str(s) => s.clone(),
        _ => panic!("not a string: {v:?}"),
    }
}

fn int_of(v: &Py) -> i64 {
    match v {
        Py::Int(n) => *n,
        _ => panic!("not an int: {v:?}"),
    }
}

fn opt_int(v: &Py) -> Option<i64> {
    match v {
        Py::Null => None,
        v => Some(int_of(v)),
    }
}

fn dec(v: &Py, scale: usize) -> Option<String> {
    match v {
        Py::Null => None,
        Py::Float(f) => Some(format!("{f:.scale$}")),
        Py::Int(n) => Some(format!("{:.scale$}", *n as f64)),
        _ => panic!("not a decimal: {v:?}"),
    }
}

fn has(v: &Py, key: &str) -> bool {
    v.get(key).is_some()
}

pub fn country_row(c: &Py) -> CountryRow {
    CountryRow {
        id: int_of(get(c, "id")),
        code: text_of(get(c, "code")),
        name: Some(dumps(get(c, "name"))),
        lat: dec(get(c, "lat"), 6),
        lon: dec(get(c, "lon"), 6),
        zoom: dec(get(c, "zoom"), 1),
    }
}

/// Station fields from either Station.to_json or the station half of a current-pollutants row.
pub fn station_row(s: &Py, country_id: i64) -> StationRow {
    StationRow {
        id: int_of(if has(s, "station_id") {
            get(s, "station_id")
        } else {
            get(s, "id")
        }),
        country_id: if has(s, "country_id") {
            int_of(get(s, "country_id"))
        } else {
            country_id
        },
        code: text_of(get(s, "code")),
        district: text_of(get(s, "district")),
        name: Some(dumps(get(s, "name"))),
        address: Some(dumps(get(s, "address"))),
        area: Some(dumps(get(s, "area"))),
        station_type: text_of(get(s, "station_type")),
        additional_info: Some(dumps(get(s, "additional_info"))),
        lat: dec(get(s, "lat"), 6),
        long: dec(get(s, "lon"), 6),
        image_url: text_of(get(s, "image_url")),
    }
}

pub fn reading_row(p: &Py) -> ReadingRow {
    ReadingRow {
        station_id: int_of(get(p, "station_id")),
        aqi: opt_int(get(p, "aqi")),
        aqhi: opt_int(get(p, "aqhi")),
        pm25: dec(get(p, "pm25"), 3),
        pm10: dec(get(p, "pm10"), 3),
        no2: dec(get(p, "no2"), 3),
        so2: dec(get(p, "so2"), 3),
        co: dec(get(p, "co"), 3),
        o3: dec(get(p, "o3"), 3),
        wind_direction: dec(get(p, "wind_direction"), 3),
        wind_speed: dec(get(p, "wind_speed"), 3),
        publish_time: match get(p, "publish_time") {
            Py::Null => None,
            t => Some(text_of(t).replacen('T', " ", 1)),
        },
    }
}

#[derive(Default)]
pub struct FakeRepo {
    pub countries: Vec<CountryRow>,
    pub stations: Vec<StationRow>,
    /// (country_id, reading)
    pub current: Vec<(i64, ReadingRow)>,
    /// station id → readings, newest first.
    pub history: HashMap<i64, Vec<ReadingRow>>,
    pub calls: Mutex<Vec<String>>,
    pub fail: bool,
}

impl FakeRepo {
    fn call(&self, what: String) -> Result<()> {
        self.calls.lock().unwrap().push(what);
        if self.fail {
            Err("ER_ACCESS_DENIED secret detail".into())
        } else {
            Ok(())
        }
    }

    pub fn calls(&self) -> Vec<String> {
        self.calls.lock().unwrap().clone()
    }
}

impl Repo for FakeRepo {
    async fn countries(&self) -> Result<Vec<CountryRow>> {
        self.call("countries".into())?;
        Ok(self.countries.clone())
    }
    async fn country_by_code(&self, code: &str) -> Result<Option<CountryRow>> {
        self.call(format!("country_by_code:{code}"))?;
        Ok(self.countries.iter().find(|c| c.code == code).cloned())
    }
    async fn country_by_id(&self, id: i64) -> Result<Option<CountryRow>> {
        self.call(format!("country_by_id:{id}"))?;
        Ok(self.countries.iter().find(|c| c.id == id).cloned())
    }
    async fn stations_by_country(&self, country_id: i64) -> Result<Vec<StationRow>> {
        self.call(format!("stations_by_country:{country_id}"))?;
        Ok(self
            .stations
            .iter()
            .filter(|s| s.country_id == country_id)
            .cloned()
            .collect())
    }
    async fn stations_by_ids(&self, ids: &[i64]) -> Result<Vec<StationRow>> {
        self.call(format!("stations_by_ids:{ids:?}"))?;
        Ok(self
            .stations
            .iter()
            .filter(|s| ids.contains(&s.id))
            .cloned()
            .collect())
    }
    async fn station_by_code(&self, code: &str) -> Result<Option<StationRow>> {
        self.call(format!("station_by_code:{code}"))?;
        Ok(self.stations.iter().find(|s| s.code == code).cloned())
    }
    async fn station_by_id(&self, id: i64) -> Result<Option<StationRow>> {
        self.call(format!("station_by_id:{id}"))?;
        Ok(self.stations.iter().find(|s| s.id == id).cloned())
    }
    async fn current_by_country(&self, country_id: i64) -> Result<Vec<ReadingRow>> {
        self.call(format!("current_by_country:{country_id}"))?;
        Ok(self
            .current
            .iter()
            .filter(|(c, _)| *c == country_id)
            .map(|(_, r)| r.clone())
            .collect())
    }
    async fn current_by_station_ids(&self, ids: &[i64]) -> Result<Vec<ReadingRow>> {
        self.call(format!("current_by_station_ids:{ids:?}"))?;
        Ok(self
            .current
            .iter()
            .filter(|(_, r)| ids.contains(&r.station_id))
            .map(|(_, r)| r.clone())
            .collect())
    }
    async fn history(&self, station_id: i64, limit: i64) -> Result<Vec<ReadingRow>> {
        self.call(format!("history:{station_id}:{limit}"))?;
        let rows = self.history.get(&station_id).cloned().unwrap_or_default();
        Ok(rows.into_iter().take(limit.max(0) as usize).collect())
    }
}

pub fn countries() -> Vec<CountryRow> {
    list(get(&fixture("countries"), "data"))
        .iter()
        .map(country_row)
        .collect()
}

/// The fake a golden case needs, rebuilt from its own recorded response.
pub fn case_repo(name: &str) -> FakeRepo {
    let body = fixture(name);
    let countries = countries();
    let twn = countries.iter().find(|c| c.code == "twn").unwrap().id;
    let mut repo = FakeRepo {
        countries,
        ..Default::default()
    };
    if name.starts_with("stations-") {
        repo.stations = list(get(&body, "data"))
            .iter()
            .map(|s| station_row(s, 0))
            .collect();
    } else if name.starts_with("current-") {
        let items = list(get(&body, "data"));
        repo.stations = items.iter().map(|p| station_row(p, twn)).collect();
        repo.current = items.iter().map(|p| (twn, reading_row(p))).collect();
    } else if name.starts_with("history-") {
        let station = station_row(get(&body, "station"), 0);
        let mut rows: Vec<ReadingRow> = list(get(&body, "data")).iter().map(reading_row).collect();
        rows.reverse();
        repo.history.insert(station.id, rows);
        repo.stations = vec![station];
    } else if name.starts_with("error-") {
        // The fake knows the twn stations, so "unknown" really means unknown.
        repo.stations = list(get(&fixture("stations-twn"), "data"))
            .iter()
            .map(|s| station_row(s, 0))
            .collect();
    }
    repo
}

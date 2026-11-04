//! Read-only access to the Lambda's MySQL schema (peewee models in
//! 7kfpun/lambda-serverless aqi/chalicelib/models.py). Tables are the peewee
//! defaults: country, station, pollutant, currentpollutant. Column values are
//! kept the way MySQL sends them: DECIMAL as text ("17.000"), DATETIME as
//! "YYYY-MM-DD HH:MM:SS" (Taiwan local time as stored, no zone), JSON-in-TEXT
//! columns as text.

use std::future::Future;
use std::time::Duration;

use mysql_async::prelude::Queryable;
use mysql_async::{OptsBuilder, Params, Pool, PoolConstraints, PoolOpts, Row, Value};

pub type Error = Box<dyn std::error::Error + Send + Sync>;
pub type Result<T> = std::result::Result<T, Error>;

#[derive(Debug, Clone, Default, PartialEq)]
pub struct CountryRow {
    pub id: i64,
    pub code: String,
    pub name: Option<String>,
    pub lat: Option<String>,
    pub lon: Option<String>,
    pub zoom: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct StationRow {
    pub id: i64,
    pub country_id: i64,
    pub code: String,
    pub district: String,
    pub name: Option<String>,
    pub address: Option<String>,
    pub area: Option<String>,
    pub station_type: String,
    pub additional_info: Option<String>,
    pub lat: Option<String>,
    pub long: Option<String>,
    pub image_url: String,
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct ReadingRow {
    pub station_id: i64,
    pub aqi: Option<i64>,
    pub aqhi: Option<i64>,
    pub pm25: Option<String>,
    pub pm10: Option<String>,
    pub no2: Option<String>,
    pub so2: Option<String>,
    pub co: Option<String>,
    pub o3: Option<String>,
    pub wind_direction: Option<String>,
    pub wind_speed: Option<String>,
    pub publish_time: Option<String>,
}

/// What the API reads. Implemented by MySQL in production and by an in-memory
/// fake in the tests.
pub trait Repo: Send + Sync {
    fn countries(&self) -> impl Future<Output = Result<Vec<CountryRow>>> + Send;
    fn country_by_code(
        &self,
        code: &str,
    ) -> impl Future<Output = Result<Option<CountryRow>>> + Send;
    fn country_by_id(&self, id: i64) -> impl Future<Output = Result<Option<CountryRow>>> + Send;
    /// A country's stations, `lat` descending (as /v1/stations orders them).
    fn stations_by_country(
        &self,
        country_id: i64,
    ) -> impl Future<Output = Result<Vec<StationRow>>> + Send;
    fn stations_by_ids(&self, ids: &[i64]) -> impl Future<Output = Result<Vec<StationRow>>> + Send;
    fn station_by_code(
        &self,
        code: &str,
    ) -> impl Future<Output = Result<Option<StationRow>>> + Send;
    fn station_by_id(&self, id: i64) -> impl Future<Output = Result<Option<StationRow>>> + Send;
    fn current_by_country(
        &self,
        country_id: i64,
    ) -> impl Future<Output = Result<Vec<ReadingRow>>> + Send;
    fn current_by_station_ids(
        &self,
        ids: &[i64],
    ) -> impl Future<Output = Result<Vec<ReadingRow>>> + Send;
    /// The newest `limit` readings for a station, newest first.
    fn history(
        &self,
        station_id: i64,
        limit: i64,
    ) -> impl Future<Output = Result<Vec<ReadingRow>>> + Send;
}

const COUNTRY: &str = "SELECT id, code, name, lat, lon, zoom FROM country";
const STATION: &str = "SELECT id, country_id, code, district, name, address, area, station_type, \
                       additional_info, lat, `long`, image_url FROM station";
const READING: &str = "SELECT station_id, aqi, aqhi, pm25, pm10, no2, so2, co, o3, wind_direction, \
                       wind_speed, publish_time";

pub struct DbConfig {
    /// Cloud Run: /cloudsql/<project>:<region>:<instance>.
    pub socket: Option<String>,
    pub host: String,
    pub port: u16,
    pub user: String,
    pub password: String,
    pub database: String,
    pub connection_limit: usize,
}

pub struct MySqlRepo {
    pool: Pool,
}

impl MySqlRepo {
    pub fn new(cfg: DbConfig) -> Result<Self> {
        // Keep the tiny db-f1-micro safe: few connections per instance; Cloud
        // Run's max instances caps the total.
        let constraints =
            PoolConstraints::new(0, cfg.connection_limit.max(1)).ok_or("bad pool limits")?;
        let pool_opts = PoolOpts::default()
            .with_constraints(constraints)
            .with_inactive_connection_ttl(Duration::from_secs(60))
            .with_ttl_check_interval(Duration::from_secs(30));
        let mut opts = OptsBuilder::default()
            .user(Some(cfg.user))
            .pass(Some(cfg.password))
            .db_name(Some(cfg.database))
            .pool_opts(pool_opts);
        opts = match cfg.socket {
            Some(socket) => opts.socket(Some(socket)),
            None => opts.ip_or_hostname(cfg.host).tcp_port(cfg.port),
        };
        Ok(Self {
            pool: Pool::new(opts),
        })
    }

    pub async fn close(self) {
        let _ = self.pool.disconnect().await;
    }

    async fn rows(&self, sql: &str, params: Vec<Value>) -> Result<Vec<Row>> {
        let mut conn = self.pool.get_conn().await?;
        let params = if params.is_empty() {
            Params::Empty
        } else {
            Params::Positional(params)
        };
        Ok(conn.exec(sql, params).await?)
    }
}

/// Column `i` as text: DECIMAL/TEXT bytes, numbers, and DATETIME as "YYYY-MM-DD HH:MM:SS".
fn text(row: &Row, i: usize) -> Option<String> {
    match row.as_ref(i)? {
        Value::NULL => None,
        Value::Bytes(b) => Some(String::from_utf8_lossy(b).into_owned()),
        Value::Int(n) => Some(n.to_string()),
        Value::UInt(n) => Some(n.to_string()),
        Value::Float(f) => Some(f.to_string()),
        Value::Double(f) => Some(f.to_string()),
        Value::Date(y, mo, d, h, mi, s, us) => {
            let base = format!("{y:04}-{mo:02}-{d:02} {h:02}:{mi:02}:{s:02}");
            // datetime.isoformat() adds microseconds only when there are some.
            Some(if *us > 0 {
                format!("{base}.{us:06}")
            } else {
                base
            })
        }
        Value::Time(neg, days, h, mi, s, _) => {
            let hours = u32::from(*h) + days * 24;
            Some(format!(
                "{}{hours:02}:{mi:02}:{s:02}",
                if *neg { "-" } else { "" }
            ))
        }
    }
}

fn int(row: &Row, i: usize) -> Option<i64> {
    match row.as_ref(i)? {
        Value::Int(n) => Some(*n),
        Value::UInt(n) => i64::try_from(*n).ok(),
        Value::Bytes(b) => std::str::from_utf8(b).ok()?.trim().parse().ok(),
        _ => None,
    }
}

fn country(row: &Row) -> CountryRow {
    CountryRow {
        id: int(row, 0).unwrap_or_default(),
        code: text(row, 1).unwrap_or_default(),
        name: text(row, 2),
        lat: text(row, 3),
        lon: text(row, 4),
        zoom: text(row, 5),
    }
}

fn station(row: &Row) -> StationRow {
    StationRow {
        id: int(row, 0).unwrap_or_default(),
        country_id: int(row, 1).unwrap_or_default(),
        code: text(row, 2).unwrap_or_default(),
        district: text(row, 3).unwrap_or_default(),
        name: text(row, 4),
        address: text(row, 5),
        area: text(row, 6),
        station_type: text(row, 7).unwrap_or_default(),
        additional_info: text(row, 8),
        lat: text(row, 9),
        long: text(row, 10),
        image_url: text(row, 11).unwrap_or_default(),
    }
}

fn reading(row: &Row) -> ReadingRow {
    ReadingRow {
        station_id: int(row, 0).unwrap_or_default(),
        aqi: int(row, 1),
        aqhi: int(row, 2),
        pm25: text(row, 3),
        pm10: text(row, 4),
        no2: text(row, 5),
        so2: text(row, 6),
        co: text(row, 7),
        o3: text(row, 8),
        wind_direction: text(row, 9),
        wind_speed: text(row, 10),
        publish_time: text(row, 11),
    }
}

fn placeholders(n: usize) -> String {
    vec!["?"; n].join(",")
}

fn ids(values: &[i64]) -> Vec<Value> {
    values.iter().map(|v| Value::Int(*v)).collect()
}

impl Repo for MySqlRepo {
    async fn countries(&self) -> Result<Vec<CountryRow>> {
        Ok(self
            .rows(&format!("{COUNTRY} ORDER BY id"), vec![])
            .await?
            .iter()
            .map(country)
            .collect())
    }

    async fn country_by_code(&self, code: &str) -> Result<Option<CountryRow>> {
        let rows = self
            .rows(
                &format!("{COUNTRY} WHERE code = ? LIMIT 1"),
                vec![code.into()],
            )
            .await?;
        Ok(rows.first().map(country))
    }

    async fn country_by_id(&self, id: i64) -> Result<Option<CountryRow>> {
        let rows = self
            .rows(&format!("{COUNTRY} WHERE id = ? LIMIT 1"), vec![id.into()])
            .await?;
        Ok(rows.first().map(country))
    }

    async fn stations_by_country(&self, country_id: i64) -> Result<Vec<StationRow>> {
        let sql = format!("{STATION} WHERE country_id = ? ORDER BY lat DESC, id");
        Ok(self
            .rows(&sql, vec![country_id.into()])
            .await?
            .iter()
            .map(station)
            .collect())
    }

    async fn stations_by_ids(&self, values: &[i64]) -> Result<Vec<StationRow>> {
        if values.is_empty() {
            return Ok(vec![]);
        }
        let sql = format!(
            "{STATION} WHERE id IN ({}) ORDER BY id",
            placeholders(values.len())
        );
        Ok(self
            .rows(&sql, ids(values))
            .await?
            .iter()
            .map(station)
            .collect())
    }

    async fn station_by_code(&self, code: &str) -> Result<Option<StationRow>> {
        let rows = self
            .rows(
                &format!("{STATION} WHERE code = ? LIMIT 1"),
                vec![code.into()],
            )
            .await?;
        Ok(rows.first().map(station))
    }

    async fn station_by_id(&self, id: i64) -> Result<Option<StationRow>> {
        let rows = self
            .rows(&format!("{STATION} WHERE id = ? LIMIT 1"), vec![id.into()])
            .await?;
        Ok(rows.first().map(station))
    }

    async fn current_by_country(&self, country_id: i64) -> Result<Vec<ReadingRow>> {
        let sql = format!("{READING} FROM currentpollutant WHERE country_id = ? ORDER BY id");
        Ok(self
            .rows(&sql, vec![country_id.into()])
            .await?
            .iter()
            .map(reading)
            .collect())
    }

    async fn current_by_station_ids(&self, values: &[i64]) -> Result<Vec<ReadingRow>> {
        if values.is_empty() {
            return Ok(vec![]);
        }
        // The Lambda's rows come back in station_id order here (MySQL reads the
        // station_id index for the IN list), not in row id order as by country.
        let sql = format!(
            "{READING} FROM currentpollutant WHERE station_id IN ({}) ORDER BY station_id, id",
            placeholders(values.len())
        );
        Ok(self
            .rows(&sql, ids(values))
            .await?
            .iter()
            .map(reading)
            .collect())
    }

    async fn history(&self, station_id: i64, limit: i64) -> Result<Vec<ReadingRow>> {
        let sql = format!(
            "{READING} FROM pollutant WHERE station_id = ? ORDER BY publish_time DESC LIMIT ?"
        );
        Ok(self
            .rows(&sql, vec![station_id.into(), limit.into()])
            .await?
            .iter()
            .map(reading)
            .collect())
    }
}

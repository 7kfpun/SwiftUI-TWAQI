//! Cloud Run entry point for twaqi-api. Reaches Cloud SQL over Cloud Run's
//! built-in Cloud SQL connection (unix socket DB_SOCKET).

use twaqi_api::repo::{DbConfig, MySqlRepo};
use twaqi_api::server::{log, router};

fn env(name: &str) -> Option<String> {
    std::env::var(name).ok().filter(|v| !v.is_empty())
}

fn required(name: &str) -> String {
    env(name).unwrap_or_else(|| panic!("Missing environment variable {name}"))
}

#[tokio::main]
async fn main() {
    let repo = MySqlRepo::new(DbConfig {
        socket: env("DB_SOCKET"),
        host: env("DB_HOST").unwrap_or_else(|| "127.0.0.1".into()),
        port: env("DB_PORT").and_then(|p| p.parse().ok()).unwrap_or(3306),
        user: required("DB_USER"),
        password: required("DB_PASSWORD"),
        database: env("DB_NAME").unwrap_or_else(|| "aqi".into()),
        connection_limit: env("DB_CONNECTION_LIMIT")
            .and_then(|n| n.parse().ok())
            .unwrap_or(3),
    })
    .expect("database config");
    let app = router(repo, required("ORIGIN_TOKEN"));

    let port = env("PORT").unwrap_or_else(|| "8080".into());
    let listener = tokio::net::TcpListener::bind(format!("0.0.0.0:{port}"))
        .await
        .expect("bind");
    log(
        "INFO",
        &format!("twaqi-api listening on {port}"),
        serde_json::json!({}),
    );
    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown())
        .await
        .expect("server");
}

async fn shutdown() {
    let mut term = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
        .expect("SIGTERM handler");
    tokio::select! {
        _ = term.recv() => {},
        _ = tokio::signal::ctrl_c() => {},
    }
}

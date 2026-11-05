//! HTTP layer. Serves the Lambda's read API (see api.rs) to the `twaqi-workers`
//! Worker only (workers/twaqi-workers/src/api.ts): every /v1 request must carry
//! the shared origin token.

use std::sync::Arc;
use std::time::Instant;

use axum::Router;
use axum::body::Body;
use axum::extract::State;
use axum::http::{HeaderMap, HeaderValue, Method, Response, StatusCode, Uri, header};
use subtle::ConstantTimeEq;

use crate::api::{Params, handle};
use crate::pyjson::dumps;
use crate::repo::Repo;

/// Must match ORIGIN_TOKEN_HEADER in workers/twaqi-workers/src/api.ts.
pub const ORIGIN_TOKEN_HEADER: &str = "x-twaqi-origin-token";

struct AppState<R> {
    repo: R,
    origin_token: String,
}

pub fn router<R: Repo + 'static>(repo: R, origin_token: String) -> Router {
    let state = Arc::new(AppState { repo, origin_token });
    Router::new().fallback(serve::<R>).with_state(state)
}

/// One JSON object per line, as Cloud Logging reads it.
pub fn log(severity: &str, message: &str, fields: serde_json::Value) {
    let mut line = serde_json::json!({ "severity": severity, "message": message });
    if let (Some(obj), serde_json::Value::Object(extra)) = (line.as_object_mut(), fields) {
        obj.extend(extra);
    }
    println!("{line}");
}

fn json(status: u16, body: impl Into<Body>) -> Response<Body> {
    let mut res = Response::new(body.into());
    *res.status_mut() = StatusCode::from_u16(status).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR);
    res.headers_mut().insert(
        header::CONTENT_TYPE,
        HeaderValue::from_static("application/json"),
    );
    res
}

fn token_matches(headers: &HeaderMap, expected: &str) -> bool {
    headers.get(ORIGIN_TOKEN_HEADER).is_some_and(|given| {
        given.as_bytes().len() == expected.len()
            && bool::from(given.as_bytes().ct_eq(expected.as_bytes()))
    })
}

async fn serve<R: Repo>(
    State(state): State<Arc<AppState<R>>>,
    method: Method,
    uri: Uri,
    headers: HeaderMap,
) -> Response<Body> {
    let started = Instant::now();
    let path = uri.path();
    // Not /healthz: Cloud Run's front end reserves it and answers 404 itself.
    if path == "/health" {
        return json(200, r#"{"ok":true}"#);
    }
    if method != Method::GET && method != Method::HEAD {
        let mut res = json(405, r#"{"message":"Method Not Allowed"}"#);
        res.headers_mut()
            .insert(header::ALLOW, HeaderValue::from_static("GET, HEAD"));
        return res;
    }
    if !token_matches(&headers, &state.origin_token) {
        return json(403, r#"{"message":"Forbidden"}"#);
    }
    let query = uri.query().unwrap_or("");
    match handle(path, &Params::parse(query), &state.repo).await {
        Ok(None) => json(404, r#"{"message":"Not Found"}"#),
        Ok(Some(result)) => {
            log(
                "INFO",
                "request",
                serde_json::json!({ "path": path, "query": query, "status": result.status, "ms": started.elapsed().as_millis() as u64 }),
            );
            // hyper drops the body of a HEAD response itself.
            json(result.status, dumps(&result.body))
        }
        Err(error) => {
            log(
                "ERROR",
                "request failed",
                serde_json::json!({ "path": path, "query": query, "error": error.to_string() }),
            );
            json(500, r#"{"success":false,"error":"Internal error"}"#)
        }
    }
}

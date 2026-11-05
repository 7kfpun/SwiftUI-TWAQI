//! The HTTP layer over a real socket: token gate, health, errors.
mod common;

use common::FakeRepo;
use twaqi_api::server::{ORIGIN_TOKEN_HEADER, router};

async fn start(repo: FakeRepo) -> String {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(axum::serve(listener, router(repo, "secret-token".into())).into_future());
    format!("http://{addr}")
}

/// A minimal HTTP/1.1 client, so the tests need no client crate.
async fn request(
    base: &str,
    method: &str,
    path: &str,
    token: Option<&str>,
) -> (u16, String, String) {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    let host = base.trim_start_matches("http://");
    let mut stream = tokio::net::TcpStream::connect(host).await.unwrap();
    let auth = token
        .map(|t| format!("{ORIGIN_TOKEN_HEADER}: {t}\r\n"))
        .unwrap_or_default();
    let req =
        format!("{method} {path} HTTP/1.1\r\nHost: {host}\r\n{auth}Connection: close\r\n\r\n");
    stream.write_all(req.as_bytes()).await.unwrap();
    let mut raw = String::new();
    stream.read_to_string(&mut raw).await.unwrap();
    let (head, body) = raw.split_once("\r\n\r\n").unwrap();
    let status = head.split(' ').nth(1).unwrap().parse().unwrap();
    (status, head.to_lowercase(), body.to_string())
}

#[tokio::test]
async fn requires_the_origin_token_on_v1_not_on_health() {
    let base = start(FakeRepo::default()).await;
    assert_eq!(request(&base, "GET", "/health", None).await.0, 200);
    assert_eq!(request(&base, "GET", "/v1/countries", None).await.0, 403);
    assert_eq!(
        request(&base, "GET", "/v1/countries", Some("wrong-token!"))
            .await
            .0,
        403
    );
    assert_eq!(
        request(&base, "GET", "/v1/countries", Some("secret-tokenX"))
            .await
            .0,
        403
    );
    let (status, head, body) = request(&base, "GET", "/v1/countries", Some("secret-token")).await;
    assert_eq!(status, 200);
    assert!(head.contains("content-type: application/json"), "{head}");
    assert_eq!(body, r#"{"success":true,"data":[]}"#);
}

#[tokio::test]
async fn not_found_method_not_allowed_head_and_db_failure() {
    let base = start(FakeRepo {
        fail: true,
        ..Default::default()
    })
    .await;
    let t = Some("secret-token");
    assert_eq!(request(&base, "GET", "/v1/success-ads", t).await.0, 404);
    assert_eq!(request(&base, "POST", "/v1/countries", t).await.0, 405);
    let (status, _, body) = request(&base, "GET", "/v1/countries", t).await;
    assert_eq!(status, 500);
    assert_eq!(
        body, r#"{"success":false,"error":"Internal error"}"#,
        "no detail leaks"
    );

    let ok = start(FakeRepo::default()).await;
    let (status, head, body) = request(&ok, "HEAD", "/v1/countries", t).await;
    assert_eq!(status, 200);
    assert!(head.contains("content-length: 26"), "{head}");
    assert_eq!(body, "");
}

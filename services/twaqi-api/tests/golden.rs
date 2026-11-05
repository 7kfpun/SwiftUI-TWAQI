//! Golden tests: rows rebuilt from each recorded Lambda response must produce
//! that exact response body again. Re-record with `make record`.
mod common;

use common::*;
use twaqi_api::api::{Params, handle};
use twaqi_api::pyjson::dumps;

async fn run(path_and_query: &str, repo: &FakeRepo) -> Option<(u16, String)> {
    let (path, query) = path_and_query
        .split_once('?')
        .unwrap_or((path_and_query, ""));
    handle(path, &Params::parse(query), repo)
        .await
        .unwrap()
        .map(|r| (r.status, dumps(&r.body)))
}

#[tokio::test]
async fn every_recorded_lambda_response_is_reproduced_byte_for_byte() {
    let cases = cases();
    assert!(cases.len() >= 16);
    for case in cases {
        let expected = fixture_text(&case.name);
        let (status, body) = run(&case.path, &case_repo(&case.name))
            .await
            .expect("route handled");
        assert_eq!(status, 200, "{}", case.name);
        assert!(
            body == expected,
            "{}: body differs\n  got      {}…\n  expected {}…",
            case.name,
            &body[..body.len().min(160)],
            &expected[..expected.len().min(160)]
        );
    }
}

#[tokio::test]
async fn country_id_resolves_to_the_same_stations_as_the_code() {
    assert_eq!(
        fixture_text("stations-country-id"),
        fixture_text("stations-twn")
    );
}

#[tokio::test]
async fn unknown_country_is_a_success_false_answer_not_a_500() {
    let repo = FakeRepo {
        countries: countries(),
        ..Default::default()
    };
    for path in [
        "/v1/stations?country=zzz",
        "/v1/current-pollutants?country_id=4242",
        "/v1/stations?country_id=abc",
    ] {
        let (_, body) = run(path, &repo).await.unwrap();
        assert_eq!(
            body, r#"{"success":false,"error":"No such a country"}"#,
            "{path}"
        );
    }
}

#[tokio::test]
async fn historical_caps_limit_at_100_and_treats_0_as_empty() {
    let repo = case_repo("history-station-id");
    run("/v1/historical-pollutants?station_id=91&limit=500", &repo)
        .await
        .unwrap();
    assert!(
        repo.calls().contains(&"history:91:100".to_string()),
        "{:?}",
        repo.calls()
    );
    let (_, body) = run("/v1/historical-pollutants?station_id=91&limit=0", &repo)
        .await
        .unwrap();
    assert!(body.ends_with(r#","data":[]}"#), "{body}");
}

#[tokio::test]
async fn country_wins_over_station_id_like_the_lambda() {
    let repo = FakeRepo {
        countries: countries(),
        ..Default::default()
    };
    run("/v1/current-pollutants?country=twn&station_id=91", &repo)
        .await
        .unwrap();
    assert_eq!(
        repo.calls().first().map(String::as_str),
        Some("country_by_code:twn")
    );
}

#[tokio::test]
async fn unknown_paths_are_not_handled() {
    let repo = FakeRepo::default();
    assert!(run("/v1/success-ads", &repo).await.is_none());
    assert!(run("/twn/retrieve_aqi", &repo).await.is_none());
}

#[tokio::test]
async fn station_ids_are_deduped_and_capped() {
    let repo = case_repo("current-station-ids");
    run("/v1/current-pollutants?station_id=91,2,91,02", &repo)
        .await
        .unwrap();
    assert!(
        repo.calls()
            .contains(&"stations_by_ids:[2, 91]".to_string()),
        "{:?}",
        repo.calls()
    );

    let calls_before = repo.calls().len();
    let many: Vec<String> = (1..=101).map(|n| n.to_string()).collect();
    let (_, body) = run(
        &format!("/v1/current-pollutants?station_id={}", many.join(",")),
        &repo,
    )
    .await
    .unwrap();
    assert_eq!(body, r#"{"success":false,"error":"Too many station ids"}"#);
    assert_eq!(
        repo.calls().len(),
        calls_before,
        "no query for a refused list"
    );

    // 100 distinct ids (plus repeats) are still served.
    let hundred = format!("{},1,2,3", many[..100].join(","));
    let (_, body) = run(
        &format!("/v1/current-pollutants?station_id={hundred}"),
        &repo,
    )
    .await
    .unwrap();
    assert!(body.starts_with(r#"{"success":true"#), "{body}");
}

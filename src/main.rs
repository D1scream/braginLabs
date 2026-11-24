use std::{env, error::Error, net::SocketAddr};

use axum::{
    Json, Router,
    extract::State,
    http::StatusCode,
    response::{IntoResponse, Response},
    routing::get,
};
use chrono::{DateTime, Utc};
use serde::Serialize;
use sqlx::PgPool;
use uuid::Uuid;

#[derive(Serialize)]
#[cfg_attr(feature = "lab6", derive(sqlx::FromRow))]
struct Pie {
    id: Uuid,
    prediction: String,
    created_at: DateTime<Utc>,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    let bind_addr = match env::var_os("PORT") {
        Some(_) => SocketAddr::from(([127, 0, 0, 1], env::var("PORT")?.parse::<u16>()?)),
        None => env::var("APP_ADDR")?.parse()?,
    };
    let pool = PgPool::connect(&env::var("DATABASE_URL")?).await?;
    let app = Router::new().route("/pie", get(get_pie)).with_state(pool);
    let listener = tokio::net::TcpListener::bind(bind_addr).await?;

    axum::serve(listener, app).await?;
    Ok(())
}

async fn get_pie(State(pool): State<PgPool>) -> Response {
    match random_pie(&pool).await {
        Ok(Some(pie)) if is_valid_prediction(&pie.prediction) => Json(pie).into_response(),
        Ok(Some(_)) | Err(_) => StatusCode::INTERNAL_SERVER_ERROR.into_response(),
        Ok(None) => StatusCode::NOT_FOUND.into_response(),
    }
}

#[cfg(not(feature = "lab6"))]
async fn random_pie(pool: &PgPool) -> Result<Option<Pie>, sqlx::Error> {
    let row = sqlx::query!(
        "SELECT id, prediction, created_at, category FROM pies ORDER BY random() LIMIT 1"
    )
    .fetch_optional(pool)
    .await?;
    Ok(row.map(|row| {
        // Category is part of the database query; the API keeps its original shape.
        let _category = row.category;
        Pie {
            id: row.id,
            prediction: row.prediction,
            created_at: row.created_at,
        }
    }))
}

#[cfg(feature = "lab6")]
async fn random_pie(pool: &PgPool) -> Result<Option<Pie>, sqlx::Error> {
    sqlx::query_as("SELECT id, prediction, created_at FROM pies ORDER BY random() LIMIT 1")
        .fetch_optional(pool)
        .await
}

fn is_valid_prediction(prediction: &str) -> bool {
    !prediction.trim().is_empty()
}

#[cfg(test)]
mod tests {
    use super::is_valid_prediction;

    #[test]
    fn rejects_blank_predictions() {
        assert!(!is_valid_prediction(""));
        assert!(!is_valid_prediction("   "));
        assert!(is_valid_prediction("Удача рядом"));
    }
}

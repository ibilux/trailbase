use axum::{
  extract::{Path, Query, State},
  http::StatusCode,
  response::{IntoResponse, Redirect, Response},
};
use lazy_static::lazy_static;
use serde::Deserialize;
use trailbase_sqlite::{named_params, params};
use ts_rs::TS;
use utoipa::{IntoParams, ToSchema};

use crate::app_state::AppState;
use crate::auth::util::{user_by_id, validate_and_normalize_email_address, validate_redirect};
use crate::auth::{AuthError, User};
use crate::auth::{LOGIN_UI, PROFILE_UI};
use crate::constants::{USER_TABLE, VERIFICATION_CODE_LENGTH};
use crate::email::Email;
use crate::extract::Either;
use crate::rand::generate_random_string;

const TTL_SEC: i64 = 3600;

#[derive(Debug, Default, Deserialize, TS, ToSchema)]
#[ts(export)]
pub struct ChangeEmailRequest {
  pub csrf_token: String,
  pub old_email: Option<String>,
  pub new_email: String,
}

/// Request an email change.
#[utoipa::path(
  post,
  path = "/change_email/request",
  tag = "auth",
  request_body = ChangeEmailRequest,
  responses(
    (status = 200, description = "Success.")
  )
)]
pub async fn change_email_request_handler(
  State(state): State<AppState>,
  user: User,
  either_request: Either<ChangeEmailRequest>,
) -> Result<Response, AuthError> {
  let (request, json) = match either_request {
    Either::Json(req) => (req, true),
    Either::Multipart(req, _) => (req, false),
    Either::Form(req) => (req, false),
  };

  if request.csrf_token != user.csrf_token {
    return Err(AuthError::BadRequest("Invalid CSRF token"));
  }

  // NOTE: This is pretty arbitrary, we could do away with this entirely.
  if !json && request.old_email.is_none() {
    return Err(AuthError::BadRequest("Missing old email address"));
  }

  if validate_and_normalize_email_address(&request.new_email).is_err() {
    return Err(AuthError::BadRequest("Invalid email address"));
  }
  let Ok(db_user) = user_by_id(&state, &user.uuid).await else {
    return Err(AuthError::Forbidden);
  };

  if let Some(last_verification) = db_user.email_verification_code_sent_at {
    let Some(timestamp) = chrono::DateTime::from_timestamp(last_verification, 0) else {
      return Err(AuthError::Internal("Invalid timestamp".into()));
    };

    // NOTE: rate limiting isn't strictly needed since user is authed. Short limit just egregious
    // abuse prevention.
    const RATE_LIMIT_SEC: i64 = 10;
    let age: chrono::Duration = chrono::Utc::now() - timestamp;
    if age < chrono::Duration::seconds(RATE_LIMIT_SEC) {
      return Err(AuthError::BadRequest("verification sent already"));
    }
  }

  let email_verification_code = generate_random_string(VERIFICATION_CODE_LENGTH);
  lazy_static! {
    pub static ref QUERY: String = format!(
      r#"
        UPDATE
          '{USER_TABLE}'
        SET
          pending_email = :new_email,
          email_verification_code = :email_verification_code,
          email_verification_code_sent_at = UNIXEPOCH()
        WHERE
          id = :user_id AND (
            CASE :old_email
              WHEN NULL THEN TRUE
              ELSE email = :old_email
            END
          )
      "#
    );
  }

  let rows_affected = state
    .user_conn()
    .execute(
      &*QUERY,
      named_params! {
        ":new_email": request.new_email,
        ":old_email": request.old_email,
        ":email_verification_code": email_verification_code.clone(),
        ":user_id": user.uuid.into_bytes().to_vec(),
      },
    )
    .await?;

  return match rows_affected {
    0 => Err(AuthError::BadRequest("failed to change email")),
    1 => {
      let email =
        Email::change_email_address_email(&state, &db_user.email, &email_verification_code)
          .map_err(|err| AuthError::Internal(err.into()))?;
      email
        .send()
        .await
        .map_err(|err| AuthError::Internal(err.into()))?;

      Ok((StatusCode::OK, "Verification email sent.").into_response())
      // TODO: Redirect, however profile page doesn't support `?alert=`.
      // Ok(Redirect::to(&format!("{PROFILE_UI}?alert=Verification email sent.")).into_response())
    }
    _ => {
      panic!("Email change request affected multiple users: {rows_affected}");
    }
  };
}

#[derive(Debug, Default, Deserialize, IntoParams)]
pub(crate) struct ChangeEmailConfigQuery {
  pub redirect_uri: Option<String>,
}

/// Confirm a change of email address.
#[utoipa::path(
  get,
  path = "/change_email/confirm/:email_verification_code",
  tag = "auth",
  responses(
    (status = 200, description = "Success.")
  )
)]
pub async fn change_email_confirm_handler(
  State(state): State<AppState>,
  Path(email_verification_code): Path<String>,
  Query(ChangeEmailConfigQuery { redirect_uri }): Query<ChangeEmailConfigQuery>,
  user: Option<User>,
) -> Result<Redirect, AuthError> {
  validate_redirect(&state, redirect_uri.as_deref())?;

  if email_verification_code.len() != VERIFICATION_CODE_LENGTH {
    return Err(AuthError::BadRequest("Invalid code"));
  }

  lazy_static! {
    pub static ref QUERY: String = format!(
      r#"
        UPDATE
          '{USER_TABLE}'
        SET
          email = pending_email,
          verified = TRUE,
          pending_email = NULL,
          email_verification_code = NULL,
          email_verification_code_sent_at = NULL
        WHERE
          email_verification_code = $1
            AND email_verification_code_sent_at > (UNIXEPOCH() - {TTL_SEC})
            AND pending_email IS NOT NULL
      "#
    );
  }

  let rows_affected = state
    .user_conn()
    .execute(&*QUERY, params!(email_verification_code))
    .await?;

  return match rows_affected {
    0 => Err(AuthError::BadRequest("Invalid verification code")),
    1 => {
      if user.is_some() {
        Ok(Redirect::to(redirect_uri.as_deref().unwrap_or(PROFILE_UI)))
      } else {
        Ok(Redirect::to(redirect_uri.as_deref().unwrap_or(LOGIN_UI)))
      }
    }
    _ => panic!("emails updated for multiple users at once: {rows_affected}"),
  };
}

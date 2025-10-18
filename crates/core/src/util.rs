use axum::http::HeaderMap;
use base64::prelude::*;
use reqwest::header::AsHeaderName;
use std::borrow::Cow;
use thiserror::Error;
use uuid::Uuid;

#[derive(Clone, Debug, Error)]
pub enum IdError {
  #[error("Id error: {0}")]
  InvalidLength(usize),
  #[error("Id error: {0}")]
  Decode(#[from] base64::DecodeSliceError),
}

pub fn b64_to_id(b64_id: &str) -> Result<[u8; 16], IdError> {
  let mut buffer: [u8; 16] = [0; 16];
  let len = BASE64_URL_SAFE.decode_slice(b64_id, &mut buffer)?;
  if len != 16 {
    return Err(IdError::InvalidLength(len));
  }
  return Ok(buffer);
}

pub fn id_to_b64(id: &[u8; 16]) -> String {
  return BASE64_URL_SAFE.encode(id);
}

pub fn uuid_to_b64(uuid: &Uuid) -> String {
  return BASE64_URL_SAFE.encode(uuid.into_bytes());
}

pub fn b64_to_uuid(b64_id: &str) -> Result<Uuid, IdError> {
  return Ok(Uuid::from_bytes(b64_to_id(b64_id)?));
}

pub fn urlencode(s: &str) -> String {
  return form_urlencoded::byte_serialize(s.as_bytes()).collect();
}

#[inline]
pub(crate) fn get_header(headers: &HeaderMap, header_name: impl AsHeaderName) -> Option<&str> {
  if let Some(header) = headers.get(header_name) {
    return header.to_str().ok();
  }
  return None;
}

#[inline]
pub(crate) fn get_header_owned(
  headers: &HeaderMap,
  header_name: impl AsHeaderName,
) -> Option<String> {
  if let Some(header) = headers.get(header_name)
    && let Ok(str) = header.to_str()
  {
    return Some(str.to_string());
  }
  return None;
}

pub fn cow_to_string(cow: Cow<'static, [u8]>) -> String {
  match cow {
    Cow::Borrowed(x) => String::from_utf8_lossy(x).to_string(),
    Cow::Owned(x) => String::from_utf8_lossy(&x).to_string(),
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn test_urlencode() {
    assert_eq!(urlencode("+col0,-col1"), "%2Bcol0%2C-col1");
  }
}

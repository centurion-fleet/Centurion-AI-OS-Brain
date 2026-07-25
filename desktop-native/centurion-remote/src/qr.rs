//! QR encoding for remote pairing connection strings.
//!
//! Payload is the existing `token:<secret>@<host>:<port>` string — no new protocol.

use image::Luma;
use qrcode::QrCode;
use qrcode::render::unicode::Dense1x2;
use std::io::Cursor;

/// Render `payload` as terminal ASCII/Unicode QR art.
pub fn encode_ascii(payload: &str) -> Result<String, String> {
    let code = QrCode::new(payload.as_bytes()).map_err(|error| error.to_string())?;
    Ok(code
        .render::<Dense1x2>()
        .dark_color(Dense1x2::Dark)
        .light_color(Dense1x2::Light)
        .build())
}

/// Render `payload` as a square PNG (grayscale QR modules).
pub fn encode_png(payload: &str, min_dimension: u32) -> Result<Vec<u8>, String> {
    let code = QrCode::new(payload.as_bytes()).map_err(|error| error.to_string())?;
    let image = code
        .render::<Luma<u8>>()
        .min_dimensions(min_dimension, min_dimension)
        .build();
    let mut buffer = Cursor::new(Vec::new());
    image::DynamicImage::ImageLuma8(image)
        .write_to(&mut buffer, image::ImageFormat::Png)
        .map_err(|error| error.to_string())?;
    Ok(buffer.into_inner())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::pairing::{format_connection_string, parse_connection_string};

    #[test]
    fn ascii_and_png_encode_exact_connection_string() {
        let connection = format_connection_string(
            "test-secret-abcdefghijklmnopqrstuvwxyz",
            "brain.example.com",
            9119,
        );
        let parsed = parse_connection_string(&connection).expect("parse");
        assert_eq!(parsed.0, "test-secret-abcdefghijklmnopqrstuvwxyz");
        assert_eq!(parsed.1, "brain.example.com");
        assert_eq!(parsed.2, 9119);

        let ascii = encode_ascii(&connection).expect("ascii qr");
        assert!(ascii.lines().count() > 10);

        let png = encode_png(&connection, 256).expect("png qr");
        assert!(png.starts_with(&[0x89, b'P', b'N', b'G']));
        assert!(png.len() > 200);

        // QrCode accepts the same UTF-8 payload we ship in the QR.
        QrCode::new(connection.as_bytes()).expect("payload fits in QR");
    }
}

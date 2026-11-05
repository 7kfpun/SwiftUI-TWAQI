//! JSON that matches what the Lambda (Chalice on Python) sends, byte for byte:
//! `json.dumps(body, separators=(',', ':'))` with ensure_ascii on, MySQL DECIMAL
//! written as a Python float (`17.0`, `0.8`), ints as ints, keys in insertion
//! order. The apps parse it with JSONSerialization / Codable either way, but
//! matching bytes lets the golden tests compare whole responses.

/// A JSON value with Python's distinctions: int vs float, ordered dict keys.
#[derive(Debug, Clone, PartialEq)]
pub enum Py {
    Null,
    Bool(bool),
    Int(i64),
    /// An int too big for i64, kept as its digits.
    BigInt(String),
    Float(f64),
    Str(String),
    List(Vec<Py>),
    Dict(Vec<(String, Py)>),
}

impl Py {
    pub fn dict<const N: usize>(entries: [(&str, Py); N]) -> Py {
        Py::Dict(
            entries
                .into_iter()
                .map(|(k, v)| (k.to_string(), v))
                .collect(),
        )
    }

    pub fn str(s: impl Into<String>) -> Py {
        Py::Str(s.into())
    }

    /// The value for `key` in a Dict.
    pub fn get(&self, key: &str) -> Option<&Py> {
        match self {
            Py::Dict(entries) => entries.iter().find(|(k, _)| k == key).map(|(_, v)| v),
            _ => None,
        }
    }

    /// Set `key`, keeping its position if present (Python dict assignment).
    pub fn set(&mut self, key: &str, value: Py) {
        if let Py::Dict(entries) = self {
            match entries.iter_mut().find(|(k, _)| k == key) {
                Some(entry) => entry.1 = value,
                None => entries.push((key.to_string(), value)),
            }
        }
    }
}

impl From<Option<i64>> for Py {
    fn from(v: Option<i64>) -> Py {
        v.map_or(Py::Null, Py::Int)
    }
}

/// Python's `repr(float)`: shortest round-trip digits, `.0` on whole numbers,
/// exponent below 1e-4 or from 1e16.
pub fn float_repr(x: f64) -> String {
    if x.is_nan() {
        return "NaN".into();
    }
    if x.is_infinite() {
        return if x > 0.0 {
            "Infinity".into()
        } else {
            "-Infinity".into()
        };
    }
    if x == 0.0 {
        return if x.is_sign_negative() {
            "-0.0".into()
        } else {
            "0.0".into()
        };
    }
    let abs = x.abs();
    if (1e-4..1e16).contains(&abs) {
        // Display never uses an exponent and prints the shortest round-trip digits.
        let s = format!("{x}");
        return if s.contains('.') { s } else { format!("{s}.0") };
    }
    // `{:e}` is shortest round-trip too: "5e-5", "1.5e-7", "1e16".
    let s = format!("{x:e}");
    let (mantissa, exp) = s.split_once('e').expect("exponent form");
    let exp: i32 = exp.parse().expect("exponent");
    let sign = if exp < 0 { '-' } else { '+' };
    format!("{mantissa}e{sign}{:02}", exp.abs())
}

/// `json.dumps` string escaping with ensure_ascii: anything outside space..~
/// becomes \uXXXX (UTF-16 units, lowercase hex).
pub fn write_str(out: &mut String, s: &str) {
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\u{8}' => out.push_str("\\b"),
            '\u{c}' => out.push_str("\\f"),
            ' '..='~' => out.push(c),
            _ => {
                let mut units = [0u16; 2];
                for unit in c.encode_utf16(&mut units) {
                    out.push_str(&format!("\\u{unit:04x}"));
                }
            }
        }
    }
    out.push('"');
}

pub fn dumps(value: &Py) -> String {
    let mut out = String::new();
    write_value(&mut out, value);
    out
}

fn write_value(out: &mut String, value: &Py) {
    match value {
        Py::Null => out.push_str("null"),
        Py::Bool(true) => out.push_str("true"),
        Py::Bool(false) => out.push_str("false"),
        Py::Int(i) => out.push_str(&i.to_string()),
        Py::BigInt(digits) => out.push_str(digits),
        Py::Float(f) => out.push_str(&float_repr(*f)),
        Py::Str(s) => write_str(out, s),
        Py::List(items) => {
            out.push('[');
            for (i, item) in items.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                write_value(out, item);
            }
            out.push(']');
        }
        Py::Dict(entries) => {
            out.push('{');
            for (i, (k, v)) in entries.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                write_str(out, k);
                out.push(':');
                write_value(out, v);
            }
            out.push('}');
        }
    }
}

/// A MySQL DECIMAL as the driver returns it ("17.000") → the float Python's
/// `float(Decimal(...))` writes. NULL stays null.
pub fn decimal(raw: Option<&str>) -> Py {
    match raw {
        None => Py::Null,
        Some(s) => s.trim().parse::<f64>().map_or(Py::Null, Py::Float),
    }
}

/// Python `f"{Decimal(raw):.{places}f}"`: exact decimal rounding, half to even,
/// sign kept on a value that rounds to zero ("-0.0"). NULL → "".
pub fn format_decimal(raw: Option<&str>, places: usize) -> String {
    let Some(raw) = raw else { return String::new() };
    let mut s = raw.trim();
    let mut negative = false;
    if let Some(rest) = s.strip_prefix('-') {
        negative = true;
        s = rest;
    } else if let Some(rest) = s.strip_prefix('+') {
        s = rest;
    }
    let (int_part, frac_part) = s.split_once('.').unwrap_or((s, ""));
    let int_part = if int_part.is_empty() { "0" } else { int_part };
    let mut frac: Vec<u8> = frac_part.bytes().collect();
    while frac.len() < places + 1 {
        frac.push(b'0');
    }
    // Kept digits as a decimal string, then rounded by hand (no size limit).
    let mut kept: Vec<u8> = int_part
        .bytes()
        .chain(frac[..places].iter().copied())
        .collect();
    let first = frac[places] - b'0';
    let beyond = frac[places + 1..].iter().any(|d| *d != b'0');
    let last_odd = kept.last().is_some_and(|d| (d - b'0') % 2 == 1);
    if first > 5 || (first == 5 && (beyond || last_odd)) {
        let mut i = kept.len();
        loop {
            if i == 0 {
                kept.insert(0, b'1');
                break;
            }
            i -= 1;
            if kept[i] == b'9' {
                kept[i] = b'0';
            } else {
                kept[i] += 1;
                break;
            }
        }
    }
    while kept.len() < places + 1 {
        kept.insert(0, b'0');
    }
    // Drop leading zeros of the integer part, keeping at least one.
    let int_len = kept.len() - places;
    let lead = kept[..int_len - 1]
        .iter()
        .take_while(|d| **d == b'0')
        .count();
    let digits = String::from_utf8(kept[lead..].to_vec()).expect("ascii digits");
    let split = digits.len() - places;
    let body = if places > 0 {
        format!("{}.{}", &digits[..split], &digits[split..])
    } else {
        digits
    };
    if negative { format!("-{body}") } else { body }
}

/// Parse JSON text the way Python's `json.loads` sees it, keeping key order and
/// number types, so `dumps` writes what the Lambda wrote for its JSON-in-TEXT
/// columns (`name`, `address`, …).
pub fn parse(text: &str) -> Result<Py, String> {
    let mut p = Parser {
        s: text.as_bytes(),
        i: 0,
    };
    let v = p.value()?;
    p.ws();
    if p.i != p.s.len() {
        return Err(p.fail("trailing data"));
    }
    Ok(v)
}

/// A JSON-in-TEXT column as Python's JSONField returns it. NULL/empty → {} (the field's default).
pub fn json_column(raw: Option<&str>) -> Result<Py, String> {
    match raw {
        None | Some("") => Ok(Py::Dict(vec![])),
        Some(s) => parse(s),
    }
}

struct Parser<'a> {
    s: &'a [u8],
    i: usize,
}

impl Parser<'_> {
    fn fail(&self, what: &str) -> String {
        format!("bad JSON ({what}) at {}", self.i)
    }

    fn ws(&mut self) {
        while self.i < self.s.len() && matches!(self.s[self.i], b' ' | b'\t' | b'\n' | b'\r') {
            self.i += 1;
        }
    }

    fn eat(&mut self, lit: &str) -> bool {
        if self.s[self.i..].starts_with(lit.as_bytes()) {
            self.i += lit.len();
            true
        } else {
            false
        }
    }

    fn value(&mut self) -> Result<Py, String> {
        self.ws();
        match self.s.get(self.i) {
            Some(b'{') => {
                self.i += 1;
                let mut dict = Py::Dict(vec![]);
                self.ws();
                if self.s.get(self.i) == Some(&b'}') {
                    self.i += 1;
                    return Ok(dict);
                }
                loop {
                    self.ws();
                    if self.s.get(self.i) != Some(&b'"') {
                        return Err(self.fail("key"));
                    }
                    let key = self.string()?;
                    self.ws();
                    if self.s.get(self.i) != Some(&b':') {
                        return Err(self.fail("colon"));
                    }
                    self.i += 1;
                    let v = self.value()?;
                    // Python keeps the last value for a repeated key, in the first key's place.
                    dict.set(&key, v);
                    self.ws();
                    match self.s.get(self.i) {
                        Some(b',') => self.i += 1,
                        Some(b'}') => {
                            self.i += 1;
                            return Ok(dict);
                        }
                        _ => return Err(self.fail("object")),
                    }
                }
            }
            Some(b'[') => {
                self.i += 1;
                let mut items = vec![];
                self.ws();
                if self.s.get(self.i) == Some(&b']') {
                    self.i += 1;
                    return Ok(Py::List(items));
                }
                loop {
                    items.push(self.value()?);
                    self.ws();
                    match self.s.get(self.i) {
                        Some(b',') => self.i += 1,
                        Some(b']') => {
                            self.i += 1;
                            return Ok(Py::List(items));
                        }
                        _ => return Err(self.fail("array")),
                    }
                }
            }
            Some(b'"') => Ok(Py::Str(self.string()?)),
            Some(_) => {
                if self.eat("true") {
                    return Ok(Py::Bool(true));
                }
                if self.eat("false") {
                    return Ok(Py::Bool(false));
                }
                if self.eat("null") {
                    return Ok(Py::Null);
                }
                if self.eat("NaN") {
                    return Ok(Py::Float(f64::NAN));
                }
                if self.eat("Infinity") {
                    return Ok(Py::Float(f64::INFINITY));
                }
                if self.eat("-Infinity") {
                    return Ok(Py::Float(f64::NEG_INFINITY));
                }
                self.number()
            }
            None => Err(self.fail("value")),
        }
    }

    fn number(&mut self) -> Result<Py, String> {
        let start = self.i;
        let digits = |p: &mut Self| {
            let from = p.i;
            while p.i < p.s.len() && p.s[p.i].is_ascii_digit() {
                p.i += 1;
            }
            p.i > from
        };
        if self.s.get(self.i) == Some(&b'-') {
            self.i += 1;
        }
        if !digits(self) {
            return Err(self.fail("number"));
        }
        let mut float = false;
        if self.s.get(self.i) == Some(&b'.') {
            self.i += 1;
            float = true;
            if !digits(self) {
                return Err(self.fail("fraction"));
            }
        }
        if matches!(self.s.get(self.i), Some(b'e' | b'E')) {
            self.i += 1;
            float = true;
            if matches!(self.s.get(self.i), Some(b'+' | b'-')) {
                self.i += 1;
            }
            if !digits(self) {
                return Err(self.fail("exponent"));
            }
        }
        let lexeme = std::str::from_utf8(&self.s[start..self.i]).expect("ascii");
        if float {
            return lexeme
                .parse::<f64>()
                .map(Py::Float)
                .map_err(|_| self.fail("float"));
        }
        match lexeme.parse::<i64>() {
            Ok(n) => Ok(Py::Int(n)),
            Err(_) => Ok(Py::BigInt(lexeme.to_string())),
        }
    }

    fn string(&mut self) -> Result<String, String> {
        self.i += 1; // opening quote
        let mut out = String::new();
        loop {
            let Some(&b) = self.s.get(self.i) else {
                return Err(self.fail("string"));
            };
            match b {
                b'"' => {
                    self.i += 1;
                    return Ok(out);
                }
                b'\\' => {
                    self.i += 1;
                    let Some(&e) = self.s.get(self.i) else {
                        return Err(self.fail("escape"));
                    };
                    self.i += 1;
                    match e {
                        b'"' => out.push('"'),
                        b'\\' => out.push('\\'),
                        b'/' => out.push('/'),
                        b'b' => out.push('\u{8}'),
                        b'f' => out.push('\u{c}'),
                        b'n' => out.push('\n'),
                        b'r' => out.push('\r'),
                        b't' => out.push('\t'),
                        b'u' => {
                            let hi = self.hex4()?;
                            if (0xD800..0xDC00).contains(&hi)
                                && self.s[self.i..].starts_with(b"\\u")
                            {
                                let save = self.i;
                                self.i += 2;
                                let lo = self.hex4()?;
                                if (0xDC00..0xE000).contains(&lo) {
                                    let c = 0x10000 + ((hi - 0xD800) << 10) + (lo - 0xDC00);
                                    out.push(char::from_u32(c).unwrap_or('\u{fffd}'));
                                    continue;
                                }
                                self.i = save;
                            }
                            out.push(char::from_u32(hi).unwrap_or('\u{fffd}'));
                        }
                        _ => return Err(self.fail("escape")),
                    }
                }
                _ => {
                    // Copy one UTF-8 character.
                    let len = match b {
                        0x00..=0x7f => 1,
                        0xc0..=0xdf => 2,
                        0xe0..=0xef => 3,
                        _ => 4,
                    };
                    let end = (self.i + len).min(self.s.len());
                    out.push_str(&String::from_utf8_lossy(&self.s[self.i..end]));
                    self.i = end;
                }
            }
        }
    }

    fn hex4(&mut self) -> Result<u32, String> {
        let hex = self
            .s
            .get(self.i..self.i + 4)
            .ok_or_else(|| self.fail("\\u"))?;
        let n = u32::from_str_radix(std::str::from_utf8(hex).map_err(|_| self.fail("\\u"))?, 16)
            .map_err(|_| self.fail("\\u"))?;
        self.i += 4;
        Ok(n)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn float_repr_matches_python() {
        let cases: &[(f64, &str)] = &[
            (17.0, "17.0"),
            (0.8, "0.8"),
            (0.0, "0.0"),
            (-0.0, "-0.0"),
            (25.129167, "25.129167"),
            (121.760056, "121.760056"),
            (0.0001, "0.0001"),
            (0.00005, "5e-05"),
            (1.5e-7, "1.5e-07"),
            (1e16, "1e+16"),
            (123456789012345.6, "123456789012345.6"),
            (-3.25, "-3.25"),
            (1e22, "1e+22"),
        ];
        for (x, expected) in cases {
            assert_eq!(float_repr(*x), *expected, "{x}");
        }
    }

    #[test]
    fn format_decimal_rounds_half_even_on_the_exact_decimal() {
        let cases: &[(&str, usize, &str)] = &[
            ("0.190", 1, "0.2"),
            ("2.250", 1, "2.2"),
            ("2.350", 1, "2.4"),
            ("2.251", 1, "2.3"),
            ("0.050", 1, "0.0"),
            ("0.150", 1, "0.2"),
            ("17.000", 1, "17.0"),
            ("-0.040", 1, "-0.0"),
            ("-1.250", 1, "-1.2"),
            ("9.950", 1, "10.0"),
            ("99.950", 1, "100.0"),
            ("63", 0, "63"),
            ("2.5", 0, "2"),
            ("3.5", 0, "4"),
            ("1.005", 2, "1.00"),
            ("0", 1, "0.0"),
            (".5", 0, "0"),
        ];
        for (raw, places, expected) in cases {
            assert_eq!(
                format_decimal(Some(raw), *places),
                *expected,
                "{raw} .{places}f"
            );
        }
        assert_eq!(format_decimal(None, 1), "");
    }

    #[test]
    fn dumps_escapes_like_ensure_ascii() {
        let v = Py::dict([
            ("a", Py::str("基隆")),
            ("b", Py::str("x\"\\/\n\u{7f}")),
            ("c", Py::str("😀")),
        ]);
        assert_eq!(
            dumps(&v),
            r#"{"a":"\u57fa\u9686","b":"x\"\\/\n\u007f","c":"\ud83d\ude00"}"#
        );
        let list = Py::List(vec![Py::Int(1), Py::Float(2.0), Py::Null, Py::Bool(true)]);
        assert_eq!(dumps(&list), "[1,2.0,null,true]");
    }

    #[test]
    fn parse_keeps_key_order_and_number_types() {
        let v = parse(
            r#"{"zh":"\u57fa","en":"K","2":1,"1":1.0,"x":[1e2,-0],"big":123456789012345678901}"#,
        )
        .unwrap();
        assert_eq!(
            dumps(&v),
            r#"{"zh":"\u57fa","en":"K","2":1,"1":1.0,"x":[100.0,0],"big":123456789012345678901}"#
        );
    }

    #[test]
    fn parse_repeated_key_keeps_first_position_and_last_value() {
        assert_eq!(
            dumps(&parse(r#"{"a":1,"b":2,"a":3}"#).unwrap()),
            r#"{"a":3,"b":2}"#
        );
    }

    #[test]
    fn parse_raw_utf8_and_surrogate_pairs() {
        assert_eq!(
            dumps(&parse("\"基隆 \\ud83d\\ude00\"").unwrap()),
            r#""\u57fa\u9686 \ud83d\ude00""#
        );
    }
}
